#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/airfliq-finder-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
xcrun swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    -module-cache-path "$ROOT/build/finder-test-cache" \
    "$ROOT/Sources/Shared/FinderSendRequest.swift" "$ROOT/Tests/FinderSendRequestTests.swift" \
    -o "$TEST_ROOT/FinderSendRequestTests"
"$TEST_ROOT/FinderSendRequestTests"
