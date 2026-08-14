#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${REVENUECAT_VERSION:-5.82.0}"
TARGET="$ROOT/Vendor/RevenueCat/RevenueCat.xcframework"
ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/revenuecat.XXXXXX.zip")"
UNPACKED="$(mktemp -d "${TMPDIR:-/tmp}/revenuecat.XXXXXX")"
trap 'rm -f "$ARCHIVE"; rm -rf "$UNPACKED"' EXIT

echo "▸ Downloading RevenueCat $VERSION"
/usr/bin/curl --fail --location --retry 3 \
  "https://github.com/RevenueCat/purchases-ios/releases/download/$VERSION/RevenueCat.xcframework.zip" \
  --output "$ARCHIVE"
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
