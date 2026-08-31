#!/bin/sh
# Verify the exported App Store product, including its nested Finder extension.
set -eu

[ "${CI_XCODEBUILD_ACTION:-}" = "archive" ] || exit 0
[ "${CI_XCODE_SCHEME:-}" = "AirFliq" ] || exit 0
[ "${CI_BUNDLE_ID:-}" = "com.cosmintrica.airfliq" ] || exit 0

if [ "${CI_XCODEBUILD_EXIT_CODE:-1}" != "0" ]; then
  echo "ci_post_xcodebuild: xcodebuild failed; skipping artifact verification" >&2
  exit 0
fi

repo_root="${CI_PRIMARY_REPOSITORY_PATH:?ci_post_xcodebuild: CI_PRIMARY_REPOSITORY_PATH is required}"
artifact_root="${CI_APP_STORE_SIGNED_APP_PATH:-${CI_ARCHIVE_PATH:-}}"
[ -n "$artifact_root" ] && [ -e "$artifact_root" ] || {
  echo "ci_post_xcodebuild: no App Store signed archive path was provided" >&2
  exit 1
}

if [ -d "$artifact_root/Contents" ] && [ "$(basename "$artifact_root")" = "AirFliq.app" ]; then
  app="$artifact_root"
else
  app="$(find "$artifact_root" -type d -name AirFliq.app -print -quit)"
fi
[ -n "${app:-}" ] || {
  echo "ci_post_xcodebuild: AirFliq.app was not found in the archive" >&2
  exit 1
}

"$repo_root/scripts/verify-app-store-build.sh" --skip-package "$app"
echo "ci_post_xcodebuild: signed App Store product verified"
