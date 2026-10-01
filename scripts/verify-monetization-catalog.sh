#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$ROOT/build/catalog-tests"
mkdir -p "$TEST_ROOT"
FRAMEWORKS="$ROOT/Vendor/RevenueCat/RevenueCat.xcframework/macos-arm64_x86_64"
# Exercise both the standalone build and Xcode's default MainActor isolation.
for isolation in explicit default-main-actor; do
    COMPILER_FLAGS=(-D MAC_APP_STORE -swift-version 6 -strict-concurrency=complete)
    if [ "$isolation" = default-main-actor ]; then
        COMPILER_FLAGS+=(-default-isolation MainActor)
    fi
    xcrun swiftc "${COMPILER_FLAGS[@]}" \
        -target "$(uname -m)-apple-macos13.0" -O \
        -warn-concurrency -warnings-as-errors \
        -module-cache-path "$TEST_ROOT/module-cache" \
        -F "$FRAMEWORKS" -framework RevenueCat -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        "$ROOT/Sources/App/Monetization.swift" "$ROOT/Sources/App/TrialPersistence.swift" \
        "$ROOT/Tests/MonetizationCatalogTests.swift" -o "$TEST_ROOT/MonetizationCatalogTests"
    echo "Catalog regression checks ($isolation isolation)"
    "$TEST_ROOT/MonetizationCatalogTests"
done
