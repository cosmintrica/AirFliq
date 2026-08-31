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

temporary_root=""
cleanup() {
  [ -z "$temporary_root" ] || rm -rf "$temporary_root"
}
trap cleanup EXIT HUP INT TERM

if [ -f "$artifact_root" ] && [ "${artifact_root##*.}" = "zip" ]; then
  temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/airfliq-cloud-export.XXXXXX")"
  /usr/bin/ditto -x -k "$artifact_root" "$temporary_root"
  search_root="$temporary_root"
else
  search_root="$artifact_root"
fi

package=""
if [ -f "$search_root" ] && [ "${search_root##*.}" = "pkg" ]; then
  package="$search_root"
else
  package="$(find "$search_root" -type f -name AirFliq.pkg -print -quit)"
fi

if [ -d "$search_root/Contents" ] && [ "$(basename "$search_root")" = "AirFliq.app" ]; then
  app="$search_root"
else
  app="$(find "$search_root" -type d -name AirFliq.app -print -quit)"
fi

if [ -z "${app:-}" ] && [ -n "$package" ]; then
  if [ -z "$temporary_root" ]; then
    temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/airfliq-cloud-export.XXXXXX")"
  fi
  expanded_package="$temporary_root/expanded-package"
  /usr/sbin/pkgutil --expand-full "$package" "$expanded_package"
  app="$(find "$expanded_package" -type d -name AirFliq.app -print -quit)"
fi

[ -n "${app:-}" ] || {
  echo "ci_post_xcodebuild: AirFliq.app was not found in the archive" >&2
  exit 1
}

if [ -n "$package" ]; then
  "$repo_root/scripts/verify-app-store-build.sh" "$app" "$package"
else
  "$repo_root/scripts/verify-app-store-build.sh" --skip-package "$app"
fi
echo "ci_post_xcodebuild: signed App Store product verified"
