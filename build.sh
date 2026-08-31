#!/bin/bash
set -euo pipefail

# Local development build. Ad-hoc signed by default; release.sh calls this with
# SIGN_IDENTITY set to a Developer ID certificate.

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/AirFliq.app"
EXT="$APP/Contents/PlugIns/AirFliqFinder.appex"
REVENUECAT_FRAMEWORK="$ROOT/Vendor/RevenueCat/RevenueCat.xcframework/macos-arm64_x86_64/RevenueCat.framework"
HOST_ARCH="$(uname -m)"
ARCHS=(arm64 x86_64)

SWIFT_6_BASE_FLAGS=(
    -swift-version 6
    -strict-concurrency=complete
    -warn-concurrency
    -warnings-as-errors
)

APP_SWIFT_6_FLAGS=("${SWIFT_6_BASE_FLAGS[@]}")
EXT_SWIFT_6_FLAGS=("${SWIFT_6_BASE_FLAGS[@]}")

# `-default-isolation` was added after Swift 6 shipped. Keep the stricter
# MainActor default on modern toolchains without breaking older Swift 6
# compilers used by GitHub's macOS runners.
if [ "${SWIFT_DEFAULT_ISOLATION:-auto}" != "off" ] && \
        swiftc -help-hidden 2>&1 | grep -q -- "-default-isolation"; then
    # AppKit application code is main-actor isolated by default. FinderSync's
    # Objective-C overrides are explicitly nonisolated in the macOS SDK, so the
    # extension needs the matching default to remain a valid Swift 6 override.
    APP_SWIFT_6_FLAGS+=(-default-isolation MainActor)
    EXT_SWIFT_6_FLAGS+=(-default-isolation nonisolated)
fi

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_STORE_BUILD="${APP_STORE_BUILD:-0}"
APP_ENTITLEMENTS="${APP_ENTITLEMENTS:-}"
EXT_ENTITLEMENTS="${EXT_ENTITLEMENTS:-$ROOT/Resources/Ext.entitlements}"
APP_PROFILE="${APP_PROFILE:-}"
EXT_PROFILE="${EXT_PROFILE:-}"
REVENUECAT_API_KEY="${REVENUECAT_API_KEY:-}"
REVENUECAT_KEYCHAIN_SERVICE="${REVENUECAT_KEYCHAIN_SERVICE:-com.cosmintrica.airfliq.revenuecat.production}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-Development}"
# The source plists use Xcode build-setting placeholders so the Xcode Cloud
# archive can keep the host app and Finder extension versions in lockstep.
# Retain deterministic defaults for this standalone swiftc build path.
MARKETING_VERSION="${MARKETING_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SWIFT_DEFINES=()

if [ "${MARKETING_CAPTURE:-0}" = "1" ]; then
    SWIFT_DEFINES+=(-D AIRFLIQ_MARKETING_CAPTURE)
fi

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    echo "error: MARKETING_VERSION must be a numeric App Store version such as 1.0.0." >&2
    exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    echo "error: BUILD_NUMBER must contain one to three integers, such as 1 or 1.2.3." >&2
    exit 1
fi

case "$BUILD_CONFIGURATION" in
    Development)
        SWIFT_BUILD_FLAGS=(-Onone -g -D DEBUG)
        ;;
    Release)
        SWIFT_BUILD_FLAGS=(-O)
        ;;
    *)
        echo "error: BUILD_CONFIGURATION must be Development or Release." >&2
        exit 1
        ;;
esac

# Keep the public SDK key out of source control. Local builds automatically use
# the production Apple key saved by the setup process. CI can build without a
# key and App Store builds require one explicitly in build-app-store.sh.
if [ "$REVENUECAT_API_KEY" = "" ]; then
    REVENUECAT_API_KEY="$(
        security find-generic-password \
            -s "$REVENUECAT_KEYCHAIN_SERVICE" \
            -a AirFliq \
            -w 2>/dev/null || true
    )"
fi

case "$REVENUECAT_API_KEY" in
    test_*)
        echo "error: RevenueCat Test Store keys cannot be used with the precompiled XCFramework." >&2
        echo "       Use the Apple public SDK key stored in Keychain." >&2
        exit 1
        ;;
    appl_*|mac_*|"") ;;
    *)
        echo "error: unsupported RevenueCat SDK key format." >&2
        exit 1
        ;;
esac
if [ "$APP_STORE_BUILD" = "1" ]; then
    APP_ENTITLEMENTS="${APP_ENTITLEMENTS:-$ROOT/Resources/AppStore-App.entitlements}"
    SWIFT_DEFINES+=(-D MAC_APP_STORE)
else
    APP_ENTITLEMENTS="${APP_ENTITLEMENTS:-$ROOT/Resources/App.entitlements}"
fi

# The hardened runtime is required for notarization and rejected for ad-hoc
# signatures, so it tracks the identity.
if [ "$SIGN_IDENTITY" = "-" ]; then
    SIGN_FLAGS=()
    echo "⚠︎ Ad-hoc signing: macOS privacy grants can reset whenever the binary changes."
    echo "  Use SIGN_IDENTITY=\"Apple Development: …\" for stable local TCC grants."
else
    SIGN_FLAGS=(--options runtime --timestamp)
fi

echo "▸ Cleaning build/"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$EXT/Contents/MacOS"

if [ ! -d "$REVENUECAT_FRAMEWORK" ]; then
    echo "error: RevenueCat framework missing. Run scripts/fetch-revenuecat.sh." >&2
    exit 1
fi

echo "▸ Generating icon"
mkdir -p "$BUILD/iconset-tool"
swiftc "${SWIFT_BUILD_FLAGS[@]}" -target "$HOST_ARCH-apple-macos13.0" \
    "${APP_SWIFT_6_FLAGS[@]}" \
    -module-cache-path "$BUILD/ModuleCache" \
    "$ROOT/Sources/Shared/AirDropIcon.swift" "$ROOT/Tools/MakeIcon.swift" \
    -o "$BUILD/iconset-tool/makeicon" -framework Cocoa
"$BUILD/iconset-tool/makeicon" "$BUILD/AppIcon.iconset"
if ! iconutil -c icns "$BUILD/AppIcon.iconset" \
        -o "$APP/Contents/Resources/AppIcon.icns"; then
    echo "  iconutil rejected a valid iconset; using the verified fallback icon"
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Building app"
echo "  configuration: $BUILD_CONFIGURATION"
if [ "$REVENUECAT_API_KEY" = "" ]; then
    echo "  RevenueCat: not embedded"
else
    echo "  RevenueCat: Apple SDK key embedded from the environment or Keychain"
fi
APP_SLICES=()
EXT_SLICES=()
for ARCH in "${ARCHS[@]}"; do
    TARGET="$ARCH-apple-macos13.0"
    ARCH_BUILD="$BUILD/arch/$ARCH"
    mkdir -p "$ARCH_BUILD"

    echo "  • $ARCH"
    swiftc "${SWIFT_BUILD_FLAGS[@]}" -target "$TARGET" \
        "${APP_SWIFT_6_FLAGS[@]}" \
        ${SWIFT_DEFINES[@]+"${SWIFT_DEFINES[@]}"} \
        -module-cache-path "$ARCH_BUILD/AppModuleCache" \
        -module-name AirFliq \
        -F "$(dirname "$REVENUECAT_FRAMEWORK")" \
        "$ROOT/Sources/Shared/AirDropIcon.swift" \
        "$ROOT"/Sources/App/*.swift \
        -o "$ARCH_BUILD/AirFliq" \
        -framework Cocoa -framework Carbon -framework FinderSync -framework ServiceManagement -framework RevenueCat \
        -Xlinker -rpath -Xlinker @executable_path/../Frameworks
    APP_SLICES+=("$ARCH_BUILD/AirFliq")

    swiftc "${SWIFT_BUILD_FLAGS[@]}" -target "$TARGET" \
        "${EXT_SWIFT_6_FLAGS[@]}" \
        -module-cache-path "$ARCH_BUILD/ExtensionModuleCache" \
        -module-name AirFliqFinder \
        -parse-as-library \
        "$ROOT/Sources/Shared/AirDropIcon.swift" \
        "$ROOT"/Sources/FinderExt/*.swift \
        -o "$ARCH_BUILD/AirFliqFinder" \
        -framework Cocoa -framework FinderSync \
        -Xlinker -e -Xlinker _NSExtensionMain
    EXT_SLICES+=("$ARCH_BUILD/AirFliqFinder")
done

echo "▸ Creating universal binaries"
xcrun lipo -create "${APP_SLICES[@]}" -output "$APP/Contents/MacOS/AirFliq"
xcrun lipo -create "${EXT_SLICES[@]}" -output "$EXT/Contents/MacOS/AirFliqFinder"
for ARCH in "${ARCHS[@]}"; do
    xcrun lipo "$APP/Contents/MacOS/AirFliq" -verify_arch "$ARCH"
    xcrun lipo "$EXT/Contents/MacOS/AirFliqFinder" -verify_arch "$ARCH"
done
echo "  arm64 + x86_64 verified"

echo "▸ Copying plists"
cp "$ROOT/Resources/App-Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Ext-Info.plist" "$EXT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable AirFliq" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.cosmintrica.airfliq" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable AirFliqFinder" "$EXT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.cosmintrica.airfliq.finder" "$EXT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$EXT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$EXT/Contents/Info.plist"
cp "$ROOT/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp -R "$REVENUECAT_FRAMEWORK" "$APP/Contents/Frameworks/RevenueCat.framework"
if [ "$REVENUECAT_API_KEY" != "" ]; then
    /usr/libexec/PlistBuddy -c "Set :AirFliqRevenueCatAPIKey $REVENUECAT_API_KEY" "$APP/Contents/Info.plist"
else
    /usr/libexec/PlistBuddy -c "Delete :AirFliqRevenueCatAPIKey" "$APP/Contents/Info.plist"
fi
if [ "$APP_PROFILE" != "" ]; then
    cp "$APP_PROFILE" "$APP/Contents/embedded.provisionprofile"
fi
if [ "$EXT_PROFILE" != "" ]; then
    cp "$EXT_PROFILE" "$EXT/Contents/embedded.provisionprofile"
fi

echo "▸ Signing as: $SIGN_IDENTITY"
# Inside out: the nested extension must be sealed before the app that contains it.
codesign --force --sign "$SIGN_IDENTITY" "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" \
    "$APP/Contents/Frameworks/RevenueCat.framework" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" \
    --entitlements "$EXT_ENTITLEMENTS" \
    "$EXT" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" \
    --entitlements "$APP_ENTITLEMENTS" \
    "$APP" >/dev/null

echo "▸ Verifying"
codesign --verify --deep --strict "$APP" && echo "  signature OK"

echo ""
echo "✅ Built: $APP"
echo ""
echo "Install:"
echo "  cp -R \"$APP\" /Applications/ && open /Applications/AirFliq.app"
