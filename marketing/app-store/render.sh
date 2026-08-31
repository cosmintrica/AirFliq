#!/bin/zsh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

zsh "$HERE/compose-native.sh"

CLANG_MODULE_CACHE_PATH=/private/tmp/airfliq-clang-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/airfliq-swift-cache \
    /usr/bin/xcrun swift "$HERE/ComposePreview.swift"

echo "Rendered native Retina App Store screenshots and H.264 preview to $HERE/final"
