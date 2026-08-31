#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/AirFliq.app"
PKG="$ROOT/build/AirFliq-AppStore.pkg"
ALLOW_ADHOC=0
SKIP_PACKAGE=0

usage() {
    cat <<'EOF'
Usage: scripts/verify-app-store-build.sh [options] [APP] [PKG]

Options:
  --allow-adhoc   Validate an unsigned CI build without provisioning profiles.
  --skip-package  Validate only the .app bundle.
  -h, --help      Show this help.

Expected version values may be supplied with MARKETING_VERSION and BUILD_NUMBER.
EOF
}

POSITIONAL=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --allow-adhoc)
            ALLOW_ADHOC=1
            ;;
        --skip-package)
            SKIP_PACKAGE=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            echo "error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            POSITIONAL+=("$1")
            ;;
    esac
    shift
done

if [ "${#POSITIONAL[@]}" -gt 2 ]; then
    echo "error: expected at most APP and PKG paths" >&2
    exit 2
fi
if [ "${#POSITIONAL[@]}" -ge 1 ]; then
    APP="${POSITIONAL[0]}"
fi
if [ "${#POSITIONAL[@]}" -ge 2 ]; then
    PKG="${POSITIONAL[1]}"
fi

EXT="$APP/Contents/PlugIns/AirFliqFinder.appex"
APP_BINARY="$APP/Contents/MacOS/AirFliq"
EXT_BINARY="$EXT/Contents/MacOS/AirFliqFinder"
FRAMEWORK="$APP/Contents/Frameworks/RevenueCat.framework"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airfliq-verify.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

fail() {
    echo "error: $*" >&2
    exit 1
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

entitlement_value() {
    local key_path="${2//./\\.}"
    /usr/bin/plutil -extract "$key_path" raw -o - "$1" 2>/dev/null
}

require_true_entitlement() {
    local plist="$1"
    local key="$2"
    [ "$(entitlement_value "$plist" "$key" || true)" = "true" ] || \
        fail "missing required entitlement $key in $plist"
}

require_architectures() {
    local binary="$1"
    local architecture
    for architecture in arm64 x86_64; do
        /usr/bin/xcrun lipo "$binary" -verify_arch "$architecture" >/dev/null || \
            fail "missing $architecture slice: $binary"
    done
}

[ -d "$APP" ] || fail "app bundle not found: $APP"
[ -d "$EXT" ] || fail "Finder extension not found: $EXT"
[ -f "$APP_BINARY" ] || fail "app executable not found: $APP_BINARY"
[ -f "$EXT_BINARY" ] || fail "extension executable not found: $EXT_BINARY"
[ -d "$FRAMEWORK" ] || fail "RevenueCat framework not found: $FRAMEWORK"
[ -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy" ] || \
    fail "privacy manifest is missing"

APP_BUNDLE_ID="$(plist_value "$APP/Contents/Info.plist" CFBundleIdentifier)"
EXT_BUNDLE_ID="$(plist_value "$EXT/Contents/Info.plist" CFBundleIdentifier)"
APP_VERSION="$(plist_value "$APP/Contents/Info.plist" CFBundleShortVersionString)"
APP_BUILD="$(plist_value "$APP/Contents/Info.plist" CFBundleVersion)"
APP_REVENUECAT_KEY="$(plist_value "$APP/Contents/Info.plist" AirFliqRevenueCatAPIKey || true)"
EXT_VERSION="$(plist_value "$EXT/Contents/Info.plist" CFBundleShortVersionString)"
EXT_BUILD="$(plist_value "$EXT/Contents/Info.plist" CFBundleVersion)"
EXT_LSUIELEMENT="$(plist_value "$EXT/Contents/Info.plist" LSUIElement)"

[[ "$APP_VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || \
    fail "invalid marketing version: $APP_VERSION"
[[ "$APP_BUILD" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || \
    fail "invalid build number: $APP_BUILD"
[ "$APP_BUNDLE_ID" = "com.cosmintrica.airfliq" ] || \
    fail "unexpected app bundle ID: $APP_BUNDLE_ID"
[ "$EXT_BUNDLE_ID" = "com.cosmintrica.airfliq.finder" ] || \
    fail "unexpected extension bundle ID: $EXT_BUNDLE_ID"
[ "$EXT_LSUIELEMENT" = "true" ] || \
    fail "Finder extension LSUIElement must be true"
case "$APP_REVENUECAT_KEY" in
    appl_*|mac_*) ;;
    test_*) fail "App Store build embeds a RevenueCat Test Store key" ;;
    *) fail "App Store build has no production RevenueCat public SDK key" ;;
esac
[ "$APP_VERSION" = "$EXT_VERSION" ] || \
    fail "app and extension marketing versions differ"
[ "$APP_BUILD" = "$EXT_BUILD" ] || \
    fail "app and extension build numbers differ"
if [ -n "${MARKETING_VERSION:-}" ]; then
    [ "$APP_VERSION" = "$MARKETING_VERSION" ] || \
        fail "built marketing version $APP_VERSION does not match $MARKETING_VERSION"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
    [ "$APP_BUILD" = "$BUILD_NUMBER" ] || \
        fail "built number $APP_BUILD does not match $BUILD_NUMBER"
fi

require_architectures "$APP_BINARY"
require_architectures "$EXT_BINARY"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/codesign --verify --strict --verbose=2 "$EXT"
/usr/bin/codesign --verify --strict --verbose=2 "$FRAMEWORK"

APP_ENTITLEMENTS="$TEMP_DIR/app-entitlements.plist"
EXT_ENTITLEMENTS="$TEMP_DIR/extension-entitlements.plist"
/usr/bin/codesign -d --entitlements :- "$APP" >"$APP_ENTITLEMENTS" 2>/dev/null
/usr/bin/codesign -d --entitlements :- "$EXT" >"$EXT_ENTITLEMENTS" 2>/dev/null
/usr/bin/plutil -lint "$APP_ENTITLEMENTS" >/dev/null
/usr/bin/plutil -lint "$EXT_ENTITLEMENTS" >/dev/null

require_true_entitlement "$APP_ENTITLEMENTS" com.apple.security.app-sandbox
require_true_entitlement "$APP_ENTITLEMENTS" com.apple.security.automation.apple-events
require_true_entitlement "$APP_ENTITLEMENTS" com.apple.security.files.bookmarks.app-scope
require_true_entitlement "$APP_ENTITLEMENTS" com.apple.security.files.user-selected.read-only
require_true_entitlement "$APP_ENTITLEMENTS" com.apple.security.network.client
require_true_entitlement "$EXT_ENTITLEMENTS" com.apple.security.app-sandbox
require_true_entitlement "$EXT_ENTITLEMENTS" com.apple.security.files.user-selected.read-only

/usr/bin/plutil -extract 'com\.apple\.security\.temporary-exception\.apple-events' json -o - \
    "$APP_ENTITLEMENTS" 2>/dev/null | /usr/bin/grep -q 'com.apple.finder' || \
    fail "Finder Apple Events temporary exception is missing"

if [ "$(entitlement_value "$APP_ENTITLEMENTS" com.apple.security.get-task-allow || true)" = "true" ] || \
        [ "$(entitlement_value "$EXT_ENTITLEMENTS" com.apple.security.get-task-allow || true)" = "true" ]; then
    fail "get-task-allow must not be enabled in an App Store build"
fi

if [ "$ALLOW_ADHOC" = "0" ]; then
    APP_PROFILE="$APP/Contents/embedded.provisionprofile"
    EXT_PROFILE="$EXT/Contents/embedded.provisionprofile"
    [ -f "$APP_PROFILE" ] || fail "app provisioning profile is missing"

    APP_PROFILE_PLIST="$TEMP_DIR/app-profile.plist"
    /usr/bin/security cms -D -i "$APP_PROFILE" >"$APP_PROFILE_PLIST"

    PROFILE_ARGUMENTS=(
        "$APP_PROFILE_PLIST"
        "com.cosmintrica.airfliq"
    )
    if [ -f "$EXT_PROFILE" ]; then
        EXT_PROFILE_PLIST="$TEMP_DIR/extension-profile.plist"
        /usr/bin/security cms -D -i "$EXT_PROFILE" >"$EXT_PROFILE_PLIST"
        PROFILE_ARGUMENTS+=(
            "$EXT_PROFILE_PLIST"
            "com.cosmintrica.airfliq.finder"
        )
    fi

    /usr/bin/python3 - "${PROFILE_ARGUMENTS[@]}" <<'PY'
import datetime
import plistlib
import sys

arguments = sys.argv[1:]
if len(arguments) % 2:
    raise SystemExit("error: malformed provisioning profile arguments")
expected = tuple(zip(arguments[0::2], arguments[1::2]))
teams = set()
now = datetime.datetime.now(datetime.timezone.utc)

for path, bundle_id in expected:
    with open(path, "rb") as handle:
        profile = plistlib.load(handle)
    entitlements = profile.get("Entitlements", {})
    team_ids = profile.get("TeamIdentifier", [])
    if not team_ids:
        raise SystemExit(f"error: no TeamIdentifier in {path}")
    team = team_ids[0]
    teams.add(team)
    if entitlements.get("com.apple.application-identifier") != f"{team}.{bundle_id}":
        raise SystemExit(f"error: provisioning profile does not match {bundle_id}")
    if entitlements.get("com.apple.developer.team-identifier") != team:
        raise SystemExit(f"error: profile team entitlement does not match {bundle_id}")
    if entitlements.get("get-task-allow") is True:
        raise SystemExit(f"error: development profile used for {bundle_id}")
    if profile.get("ProvisionedDevices"):
        raise SystemExit(f"error: device-provisioned profile used for {bundle_id}")
    if profile.get("ProvisionsAllDevices") is True:
        raise SystemExit(f"error: direct-distribution profile used for {bundle_id}")
    expires = profile.get("ExpirationDate")
    if expires is None:
        raise SystemExit(f"error: no ExpirationDate in profile for {bundle_id}")
    if expires.replace(tzinfo=datetime.timezone.utc) <= now:
        raise SystemExit(f"error: provisioning profile has expired for {bundle_id}")

if len(teams) != 1:
    raise SystemExit("error: app and extension profiles belong to different teams")
PY

    APP_SIGNATURE="$(/usr/bin/codesign -dvv "$APP" 2>&1)"
    EXT_SIGNATURE="$(/usr/bin/codesign -dvv "$EXT" 2>&1)"
    SIGNING_TEAM="$(printf '%s\n' "$APP_SIGNATURE" | \
        /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
    EXT_SIGNING_TEAM="$(printf '%s\n' "$EXT_SIGNATURE" | \
        /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
    APP_AUTHORITY="$(printf '%s\n' "$APP_SIGNATURE" | \
        /usr/bin/awk -F= '/^Authority=/{print $2; exit}')"
    EXT_AUTHORITY="$(printf '%s\n' "$EXT_SIGNATURE" | \
        /usr/bin/awk -F= '/^Authority=/{print $2; exit}')"
    PROFILE_TEAM="$(plist_value "$APP_PROFILE_PLIST" 'TeamIdentifier:0')"
    [ -n "$SIGNING_TEAM" ] || fail "signed app has no TeamIdentifier"
    [ "$EXT_SIGNING_TEAM" = "$SIGNING_TEAM" ] || \
        fail "app and extension signing teams differ"
    [ "$SIGNING_TEAM" = "$PROFILE_TEAM" ] || \
        fail "certificate team and provisioning profile team differ"
    [ "$(entitlement_value "$APP_ENTITLEMENTS" com.apple.application-identifier || true)" = \
        "$SIGNING_TEAM.com.cosmintrica.airfliq" ] || \
        fail "signed app identifier entitlement does not match its bundle ID"
    [ "$(entitlement_value "$APP_ENTITLEMENTS" com.apple.developer.team-identifier || true)" = \
        "$SIGNING_TEAM" ] || fail "signed app team entitlement is incorrect"
    case "$APP_AUTHORITY" in
        "Apple Distribution:"*|"3rd Party Mac Developer Application:"*) ;;
        *) fail "app is not signed with an App Store distribution certificate: $APP_AUTHORITY" ;;
    esac
    case "$EXT_AUTHORITY" in
        "Apple Distribution:"*|"3rd Party Mac Developer Application:"*) ;;
        *) fail "extension is not signed with an App Store distribution certificate: $EXT_AUTHORITY" ;;
    esac
fi

if [ "$SKIP_PACKAGE" = "0" ]; then
    [ -f "$PKG" ] || fail "installer package not found: $PKG"
    PKG_SIGNATURE="$(/usr/sbin/pkgutil --check-signature "$PKG" 2>&1)"
    printf '%s\n' "$PKG_SIGNATURE"
    printf '%s\n' "$PKG_SIGNATURE" | \
        /usr/bin/grep -Eq 'Mac Installer Distribution:|3rd Party Mac Developer Installer:' || \
        fail "package is not signed with a Mac App Store installer certificate"
    /usr/sbin/pkgutil --payload-files "$PKG" | \
        /usr/bin/grep -q '^\./AirFliq.app/Contents/MacOS/AirFliq$' || \
        fail "installer package does not contain AirFliq.app"
fi

echo "Verified AirFliq $APP_VERSION ($APP_BUILD): universal app, Finder extension, signatures and entitlements"
if [ "$SKIP_PACKAGE" = "0" ]; then
    echo "Verified signed App Store package: $PKG"
fi
