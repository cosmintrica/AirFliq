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
  "Xcode 26."*) ;;
  *)
  echo "ci_pre_xcodebuild: expected a stable Xcode 26.x, found $xcode_version" >&2
  exit 1
  ;;
esac
if xcodebuild -version | grep -qi beta; then
  echo "ci_pre_xcodebuild: beta Xcode cannot produce an App Store archive" >&2
  exit 1
fi

repo_root="${CI_PRIMARY_REPOSITORY_PATH:?ci_pre_xcodebuild: CI_PRIMARY_REPOSITORY_PATH is required}"
test -d "$repo_root/Vendor/RevenueCat/RevenueCat.xcframework"
test -s "$repo_root/Configurations/Secrets.xcconfig"
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

echo "ci_pre_xcodebuild: stable Xcode 26.x App Store archive contract verified"
