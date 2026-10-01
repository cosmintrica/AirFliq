#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/airfliq-setup-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
APP="$TEST_ROOT/SetupTests.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.cosmintrica.airfliq.setup-tests</string>
<key>CFBundleExecutable</key><string>SetupTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
SOURCES=("$ROOT"/Sources/Shared/*.swift)
for source in "$ROOT"/Sources/App/*.swift; do
    [[ "${source##*/}" == main.swift ]] || SOURCES+=("$source")
done
FRAMEWORKS="$ROOT/Vendor/RevenueCat/RevenueCat.xcframework/macos-arm64_x86_64"
xcrun swiftc -D MAC_APP_STORE -swift-version 6 -strict-concurrency=complete \
    -target "$(uname -m)-apple-macos13.0" \
    -warnings-as-errors -default-isolation MainActor \
    -module-cache-path "$ROOT/build/setup-test-cache" \
    -F "$FRAMEWORKS" -framework RevenueCat -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    "${SOURCES[@]}" "$ROOT/Tests/OnboardingProgressTests.swift" \
    -o "$APP/Contents/MacOS/SetupTests"
"$APP/Contents/MacOS/SetupTests"
