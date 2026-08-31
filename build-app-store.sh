#!/bin/bash
set -euo pipefail

# Builds a sandboxed, universal Mac App Store package.
#
# Required:
#   SIGN_IDENTITY       Apple Distribution application certificate
#   INSTALLER_IDENTITY  Mac Installer Distribution certificate
#   APP_PROFILE         Mac App Store profile for com.cosmintrica.airfliq
#   EXT_PROFILE         Mac App Store profile for com.cosmintrica.airfliq.finder
#   REVENUECAT_API_KEY  Public macOS SDK key from RevenueCat
# Optional:
#   MARKETING_VERSION   Numeric App Store version, defaults to App-Info.plist
#   BUILD_NUMBER        Numeric App Store build, defaults to App-Info.plist

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/AirFliq.app"
PKG="$BUILD/AirFliq-AppStore.pkg"

for variable in SIGN_IDENTITY INSTALLER_IDENTITY APP_PROFILE EXT_PROFILE REVENUECAT_API_KEY; do
    if [ "${!variable:-}" = "" ]; then
        echo "error: $variable is required. See docs/APP-STORE.md." >&2
        exit 1
    fi
done

for profile in "$APP_PROFILE" "$EXT_PROFILE"; do
    if [ ! -f "$profile" ]; then
        echo "error: provisioning profile not found: $profile" >&2
        exit 1
    fi
done

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airfliq-store.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

decode_profile() {
    /usr/bin/security cms -D -i "$1" > "$2"
}

make_entitlements() {
    local template="$1"
    local profile_plist="$2"
    local output="$3"
    local application_identifier
    local team_identifier

    application_identifier=$(
        /usr/libexec/PlistBuddy \
            -c "Print :Entitlements:com.apple.application-identifier" \
            "$profile_plist"
    )
    team_identifier=$(
        /usr/libexec/PlistBuddy \
            -c "Print :Entitlements:com.apple.developer.team-identifier" \
            "$profile_plist"
    )

    cp "$template" "$output"
    /usr/libexec/PlistBuddy \
        -c "Add :com.apple.application-identifier string $application_identifier" \
        "$output"
    /usr/libexec/PlistBuddy \
        -c "Add :com.apple.developer.team-identifier string $team_identifier" \
        "$output"
}

APP_PROFILE_PLIST="$TEMP_DIR/app-profile.plist"
EXT_PROFILE_PLIST="$TEMP_DIR/extension-profile.plist"
APP_SIGNING_ENTITLEMENTS="$TEMP_DIR/app.entitlements"
EXT_SIGNING_ENTITLEMENTS="$TEMP_DIR/extension.entitlements"

decode_profile "$APP_PROFILE" "$APP_PROFILE_PLIST"
decode_profile "$EXT_PROFILE" "$EXT_PROFILE_PLIST"
make_entitlements "$ROOT/Resources/AppStore-App.entitlements" \
    "$APP_PROFILE_PLIST" "$APP_SIGNING_ENTITLEMENTS"
make_entitlements "$ROOT/Resources/Ext.entitlements" \
    "$EXT_PROFILE_PLIST" "$EXT_SIGNING_ENTITLEMENTS"

APP_IDENTIFIER=$(
    /usr/libexec/PlistBuddy \
        -c "Print :Entitlements:com.apple.application-identifier" \
        "$APP_PROFILE_PLIST"
)
EXT_IDENTIFIER=$(
    /usr/libexec/PlistBuddy \
        -c "Print :Entitlements:com.apple.application-identifier" \
        "$EXT_PROFILE_PLIST"
)

case "$APP_IDENTIFIER" in
    *.com.cosmintrica.airfliq) ;;
    *)
        echo "error: APP_PROFILE does not match com.cosmintrica.airfliq" >&2
        exit 1
        ;;
esac
case "$EXT_IDENTIFIER" in
    *.com.cosmintrica.airfliq.finder) ;;
    *)
        echo "error: EXT_PROFILE does not match com.cosmintrica.airfliq.finder" >&2
        exit 1
        ;;
esac

echo "▸ Building the sandboxed App Store edition"
APP_STORE_BUILD=1 \
BUILD_CONFIGURATION=Release \
APP_ENTITLEMENTS="$APP_SIGNING_ENTITLEMENTS" \
EXT_ENTITLEMENTS="$EXT_SIGNING_ENTITLEMENTS" \
APP_PROFILE="$APP_PROFILE" \
EXT_PROFILE="$EXT_PROFILE" \
SIGN_IDENTITY="$SIGN_IDENTITY" \
REVENUECAT_API_KEY="$REVENUECAT_API_KEY" \
"$ROOT/build.sh"

echo "▸ Verifying trial policy"
/bin/bash "$ROOT/scripts/verify-trial-policy.sh"

echo "▸ Verifying sandbox, privacy manifest and universal binaries"
/usr/bin/test -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy"

echo "▸ Packaging for App Store Connect"
/usr/bin/productbuild \
    --component "$APP" /Applications \
    --sign "$INSTALLER_IDENTITY" \
    "$PKG"

MARKETING_VERSION="${MARKETING_VERSION:-}" \
BUILD_NUMBER="${BUILD_NUMBER:-}" \
    "$ROOT/scripts/verify-app-store-build.sh" "$APP" "$PKG"

/usr/bin/shasum -a 256 "$PKG" >"$PKG.sha256"

echo ""
echo "✅ Ready for validation and upload: $PKG"
echo "   SHA-256: $PKG.sha256"
echo "   This script never uploads or submits the package."
