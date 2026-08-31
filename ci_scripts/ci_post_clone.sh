#!/bin/sh
# Prepare dependencies and the build-only configuration in Xcode Cloud.
set -eu

repo_root="${CI_PRIMARY_REPOSITORY_PATH:?ci_post_clone: CI_PRIMARY_REPOSITORY_PATH is required}"
key="${AIRFLIQ_REVENUECAT_PUBLIC_SDK_KEY:-}"

[ -n "$key" ] || {
  echo "ci_post_clone: AIRFLIQ_REVENUECAT_PUBLIC_SDK_KEY is required" >&2
  exit 1
}

case "$key" in
  appl_*|mac_*|"") ;;
  test_*)
    echo "ci_post_clone: RevenueCat Test Store keys are not valid for this App Store build" >&2
    exit 1
    ;;
  *)
    echo "ci_post_clone: unsupported RevenueCat public SDK key format" >&2
    exit 1
    ;;
esac

"$repo_root/scripts/fetch-revenuecat.sh"

config_dir="$repo_root/Configurations"
secret_file="$config_dir/Secrets.xcconfig"
umask 077
{
  printf 'AIRFLIQ_REVENUECAT_API_KEY = %s\n' "$key"
  printf 'CURRENT_PROJECT_VERSION = %s\n' "${CI_BUILD_NUMBER:-1}"
} > "$secret_file"

echo "ci_post_clone: RevenueCat and release configuration are ready"
