#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_VERSION="5.82.0"
DEFAULT_SHA256="23e9025551a1e9e6fb251d4a113a2b20c4cf65317c9cc243a215730d38ebe626"
VERSION="${REVENUECAT_VERSION:-$DEFAULT_VERSION}"
EXPECTED_SHA256="${REVENUECAT_SHA256:-}"
TARGET="$ROOT/Vendor/RevenueCat/RevenueCat.xcframework"
ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/revenuecat.XXXXXX.zip")"
UNPACKED="$(mktemp -d "${TMPDIR:-/tmp}/revenuecat.XXXXXX")"
trap 'rm -f "$ARCHIVE"; rm -rf "$UNPACKED"' EXIT

if [ "$EXPECTED_SHA256" = "" ]; then
  if [ "$VERSION" = "$DEFAULT_VERSION" ]; then
    EXPECTED_SHA256="$DEFAULT_SHA256"
  else
    echo "error: set REVENUECAT_SHA256 when overriding REVENUECAT_VERSION" >&2
    exit 1
  fi
fi

if [[ ! "$EXPECTED_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "error: REVENUECAT_SHA256 must be a 64-character SHA-256 digest" >&2
  exit 1
fi

echo "▸ Downloading RevenueCat $VERSION"
/usr/bin/curl --fail --location --retry 3 \
  "https://github.com/RevenueCat/purchases-ios/releases/download/$VERSION/RevenueCat.xcframework.zip" \
  --output "$ARCHIVE"

ACTUAL_SHA256="$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
EXPECTED_SHA256_LOWER="$(printf '%s' "$EXPECTED_SHA256" | /usr/bin/tr '[:upper:]' '[:lower:]')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256_LOWER" ]; then
  echo "error: RevenueCat archive checksum mismatch" >&2
  echo "       expected $EXPECTED_SHA256" >&2
  echo "       received $ACTUAL_SHA256" >&2
  exit 1
fi

/usr/bin/unzip -tq "$ARCHIVE"
/usr/bin/ditto -x -k "$ARCHIVE" "$UNPACKED"

echo "▸ Installing the universal macOS framework"
rm -rf "$TARGET"
mkdir -p "$TARGET"
/usr/bin/ditto \
  "$UNPACKED/RevenueCat.xcframework/macos-arm64_x86_64" \
  "$TARGET/macos-arm64_x86_64"
cp "$UNPACKED/RevenueCat.xcframework/Info.plist" "$TARGET/Info.plist"
echo "✅ RevenueCat is ready."
