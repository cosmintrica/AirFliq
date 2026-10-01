#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/airfliq-folder-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
xcrun swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    -default-isolation MainActor -target "$(uname -m)-apple-macos13.0" \
    -module-cache-path "$ROOT/build/folder-test-cache" \
    "$ROOT/Sources/App/FolderAccessRequest.swift" "$ROOT/Tests/FolderAccessRequestTests.swift" \
    -o "$TEST_ROOT/FolderAccessTests"
"$TEST_ROOT/FolderAccessTests"
