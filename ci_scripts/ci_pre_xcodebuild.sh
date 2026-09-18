#!/bin/sh
# Refuse an accidental beta/wrong-scheme distribution before Xcode archives.
set -eu

[ "${CI_XCODEBUILD_ACTION:-}" = "archive" ] || exit 0

[ "${CI_XCODE_SCHEME:-}" = "AirFliq" ] || {
  echo "ci_pre_xcodebuild: the archive scheme must be AirFliq" >&2
  exit 1
}
[ "${CI_BUNDLE_ID:-}" = "com.cosmintrica.airfliq" ] || {
  echo "ci_pre_xcodebuild: the archive bundle ID must be com.cosmintrica.airfliq" >&2
  exit 1
}

xcode_version="$(xcodebuild -version | sed -n '1p')"
case "$xcode_version" in
  "Xcode 26."*|"Xcode 27."*) ;;
  *)
  echo "ci_pre_xcodebuild: expected a stable Xcode 26.x or 27.x, found $xcode_version" >&2
  exit 1
  ;;
esac
if xcodebuild -version | grep -qi beta; then
  echo "ci_pre_xcodebuild: beta Xcode cannot produce an App Store archive" >&2
  exit 1
fi

repo_root="${CI_PRIMARY_REPOSITORY_PATH:?ci_pre_xcodebuild: CI_PRIMARY_REPOSITORY_PATH is required}"
test -d "$repo_root/Vendor/RevenueCat/RevenueCat.xcframework"
secret_file="$repo_root/Configurations/Secrets.xcconfig"
test -s "$secret_file"
resolved_revenuecat_key="$(
  sed -n 's/^[[:space:]]*AIRFLIQ_REVENUECAT_API_KEY[[:space:]]*=[[:space:]]*//p' \
    "$secret_file" | tail -n 1
)"
case "$resolved_revenuecat_key" in
  appl_*|mac_*) ;;
  *)
    echo "ci_pre_xcodebuild: Secrets.xcconfig has no production RevenueCat public SDK key" >&2
    exit 1
    ;;
esac
if grep -Eq '^[[:space:]]*AIRFLIQ_REVENUECAT_API_KEY[[:space:]]*=' \
    "$repo_root/AirFliq.xcodeproj/project.pbxproj"; then
  echo "ci_pre_xcodebuild: project build settings override the RevenueCat secret" >&2
  exit 1
fi
"$repo_root/scripts/verify-trial-policy.sh"
plutil -lint \
  "$repo_root/Resources/App-Info.plist" \
  "$repo_root/Resources/Ext-Info.plist" \
  "$repo_root/Resources/AppStore-App.entitlements" \
  "$repo_root/Resources/Ext.entitlements" >/dev/null
[ "$(plutil -extract LSUIElement raw -o - "$repo_root/Resources/Ext-Info.plist")" = "true" ] || {
  echo "ci_pre_xcodebuild: Finder extension LSUIElement must be true for App Store validation" >&2
  exit 1
}

echo "ci_pre_xcodebuild: stable Xcode App Store archive contract verified"
