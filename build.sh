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

SWIFT_6_FLAGS=(
    -swift-version 6
    -strict-concurrency=complete
    -warn-concurrency
    -warnings-as-errors
)

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_STORE_BUILD="${APP_STORE_BUILD:-0}"
APP_ENTITLEMENTS="${APP_ENTITLEMENTS:-}"
EXT_ENTITLEMENTS="${EXT_ENTITLEMENTS:-$ROOT/Resources/Ext.entitlements}"
APP_PROFILE="${APP_PROFILE:-}"
EXT_PROFILE="${EXT_PROFILE:-}"
REVENUECAT_API_KEY="${REVENUECAT_API_KEY:-}"
SWIFT_DEFINES=()
if [ "$APP_STORE_BUILD" = "1" ]; then
    APP_ENTITLEMENTS="${APP_ENTITLEMENTS:-$ROOT/Resources/AppStore-App.entitlements}"
    SWIFT_DEFINES=(-D MAC_APP_STORE)
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
swiftc -O -target "$HOST_ARCH-apple-macos13.0" \
    "${SWIFT_6_FLAGS[@]}" \
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
APP_SLICES=()
EXT_SLICES=()
for ARCH in "${ARCHS[@]}"; do
    TARGET="$ARCH-apple-macos13.0"
    ARCH_BUILD="$BUILD/arch/$ARCH"
    mkdir -p "$ARCH_BUILD"

    echo "  • $ARCH"
    swiftc -O -target "$TARGET" \
        "${SWIFT_6_FLAGS[@]}" \
        ${SWIFT_DEFINES[@]+"${SWIFT_DEFINES[@]}"} \
        -default-isolation MainActor \
        -module-cache-path "$ARCH_BUILD/AppModuleCache" \
        -module-name AirFliq \
        -F "$(dirname "$REVENUECAT_FRAMEWORK")" \
        "$ROOT/Sources/Shared/AirDropIcon.swift" \
        "$ROOT"/Sources/App/*.swift \
        -o "$ARCH_BUILD/AirFliq" \
        -framework Cocoa -framework Carbon -framework FinderSync -framework ServiceManagement -framework RevenueCat \
        -Xlinker -rpath -Xlinker @executable_path/../Frameworks
    APP_SLICES+=("$ARCH_BUILD/AirFliq")

    swiftc -O -target "$TARGET" \
        "${SWIFT_6_FLAGS[@]}" \
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
cp "$ROOT/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp -R "$REVENUECAT_FRAMEWORK" "$APP/Contents/Frameworks/RevenueCat.framework"
if [ "$REVENUECAT_API_KEY" != "" ]; then
    /usr/libexec/PlistBuddy -c "Add :AirFliqRevenueCatAPIKey string $REVENUECAT_API_KEY" "$APP/Contents/Info.plist"
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
