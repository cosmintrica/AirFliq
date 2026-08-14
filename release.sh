#!/bin/bash
set -euo pipefail

# Produces a signed, notarized, stapled AirFliq.dmg ready to hand to anyone.
#
# One-time prerequisites:
#   1. A paid Apple Developer account.
#   2. A "Developer ID Application" certificate installed in your login keychain.
#      Xcode > Settings > Accounts > Manage Certificates > +
#   3. A notarytool keychain profile holding an app-specific password:
#        xcrun notarytool store-credentials AirFliqNotary \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
#
# Then:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./release.sh

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/AirFliq.app"
DMG="$BUILD/AirFliq.dmg"
STAGING="$BUILD/dmg-staging"

NOTARY_PROFILE="${NOTARY_PROFILE:-AirFliqNotary}"

if [ "${SIGN_IDENTITY:-}" = "" ] || [ "${SIGN_IDENTITY:-}" = "-" ]; then
    echo "error: SIGN_IDENTITY must be a Developer ID Application identity." >&2
    echo "       Available identities:" >&2
    security find-identity -v -p codesigning | sed 's/^/         /' >&2
    exit 1
fi

echo "▸ Building with a real identity"
BUILD_CONFIGURATION=Release SIGN_IDENTITY="$SIGN_IDENTITY" "$ROOT/build.sh"

echo "▸ Checking the hardened runtime took"
codesign --display --verbose=2 "$APP" 2>&1 | grep -q "flags=.*runtime" \
    || { echo "error: hardened runtime flag missing" >&2; exit 1; }

echo "▸ Staging the disk image"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "AirFliq" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

echo "▸ Signing the disk image"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

echo "▸ Notarizing (this takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "▸ Verifying as Gatekeeper would"
spctl --assess --type open --context context:primary-signature -vv "$DMG"

echo ""
echo "✅ Ready to distribute: $DMG"
