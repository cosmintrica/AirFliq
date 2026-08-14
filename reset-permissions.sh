#!/bin/bash
set -euo pipefail

# Returns AirFliq to a genuine first-launch state for local testing.
# This intentionally resets only AirFliq's privacy decisions, Finder extension,
# onboarding and free-send test state.

APP_ID="com.cosmintrica.airfliq"
EXTENSION_ID="com.cosmintrica.airfliq.finder"
LEGACY_APP_ID="com.cosmintrica.airdropper"
LEGACY_EXTENSION_ID="com.cosmintrica.airdropper.finder"

echo "▸ Stopping AirFliq"
/usr/bin/killall AirFliq 2>/dev/null || true

echo "▸ Resetting Finder and Files & Folders privacy decisions"
/usr/bin/tccutil reset All "$APP_ID" 2>/dev/null || true
# macOS 27 can leave per-service decisions behind after `reset All`, so reset
# the exact AirFliq services too. The bundle ID keeps this scoped to this app.
/usr/bin/tccutil reset AppleEvents "$APP_ID" 2>/dev/null || true
/usr/bin/tccutil reset SystemPolicyDocumentsFolder "$APP_ID" 2>/dev/null || true
/usr/bin/tccutil reset SystemPolicyDownloadsFolder "$APP_ID" 2>/dev/null || true

echo "▸ Disabling the Finder extension"
/usr/bin/pluginkit -e ignore -i "$EXTENSION_ID"
/usr/bin/pluginkit -e ignore -i "$LEGACY_EXTENSION_ID" 2>/dev/null || true

echo "▸ Resetting onboarding state"
/usr/bin/defaults delete "$APP_ID" hasRunSetup 2>/dev/null || true
/usr/bin/defaults delete "$APP_ID" hasRequestedAutomation 2>/dev/null || true
/usr/bin/defaults delete "$APP_ID" airfliq.onboarding.didRequestFinderAutomation.v1 2>/dev/null || true
/usr/bin/defaults delete "$APP_ID" hasRequestedFiles 2>/dev/null || true
/usr/bin/defaults delete "$APP_ID" hasRequestedFinderExtension 2>/dev/null || true
/usr/bin/defaults delete "$APP_ID" airfliq.onboarding.didRequestFinderExtension.v1 2>/dev/null || true
/usr/bin/defaults delete "$APP_ID" selectedFolderBookmarks 2>/dev/null || true
/usr/bin/defaults delete "$APP_ID" airfliq.successfulSends.v1 2>/dev/null || true
/usr/bin/defaults delete "$APP_ID" shortcutConfigured.v2 2>/dev/null || true
/usr/bin/defaults delete "$APP_ID" shortcutName 2>/dev/null || true
/usr/bin/defaults delete "$APP_ID" shortcutKeyCode.v2 2>/dev/null || true
/usr/bin/defaults delete "$APP_ID" shortcutModifiers.v2 2>/dev/null || true
/usr/bin/defaults delete "$APP_ID" dragToSendEnabled 2>/dev/null || true

# Remove first-launch data from pre-rename builds as well.
/usr/bin/tccutil reset All "$LEGACY_APP_ID" 2>/dev/null || true
/usr/bin/defaults delete "$LEGACY_APP_ID" 2>/dev/null || true

echo ""
echo "✅ AirFliq will show all three permissions and the shortcut step as new on next launch."
