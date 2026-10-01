#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /private/tmp/airfliq-access-qa.XXXXXX)"
APP="$TEST_ROOT/AirFliqAccessTests.app"
FIXTURES="$TEST_ROOT/fixtures"
mkdir -p "$APP/Contents/MacOS" "$FIXTURES/Alpha" "$FIXTURES/Beta" "$FIXTURES/Gamma"
printf 'First synthetic test file\n' > "$FIXTURES/Alpha/first.txt"
printf 'Second synthetic test file\n' > "$FIXTURES/Beta/second.txt"
printf 'Cancel this access request\n' > "$FIXTURES/Gamma/cancel.txt"
python3 - "$APP/Contents/Info.plist" "$FIXTURES" <<'PY'
import plistlib,sys,pathlib
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'CFBundleIdentifier':'com.cosmintrica.airfliq.folder-access-tests.' + pathlib.Path(sys.argv[2]).parent.name.lower(),
                  'CFBundleExecutable':'AccessTests','CFBundleName':'AirFliq Access Tests',
                  'CFBundlePackageType':'APPL','QAFixtures':sys.argv[2]}, f)
PY
xcrun swiftc -D MAC_APP_STORE -swift-version 6 -strict-concurrency=complete \
    -warnings-as-errors -default-isolation MainActor -target "$(uname -m)-apple-macos13.0" \
    -module-cache-path "$ROOT/build/folder-test-cache" \
    "$ROOT/Sources/App/Permissions.swift" "$ROOT/Sources/App/FolderAccessRequest.swift" \
    "$ROOT/Tests/FolderAccessSandboxApp.swift" -o "$APP/Contents/MacOS/AccessTests"
codesign --force --sign "${SIGN_IDENTITY:--}" --entitlements "$ROOT/Resources/AppStore-App.entitlements" "$APP"
echo "$APP"
