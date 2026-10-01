#!/bin/bash
set -euo pipefail

# Walk through AirFliq's setup from the very first screen with a local test
# build (Development configuration). It resets only AirFliq's own setup state:
# onboarding progress, skipped steps, shortcut, chosen folders, drag target and
# today's free-send count. Purchases and the trial are not touched.
#
#   scripts/test-onboarding.sh                 # keep the Finder extension as is
#   scripts/test-onboarding.sh --finder-off    # also switch the extension off,
#                                              # to test the Right-click guide

APP="${AIRFLIQ_TEST_APP:-/Applications/AirFliq.app}"
EXTENSION_ID="com.cosmintrica.airfliq.finder"

if [ ! -x "$APP/Contents/MacOS/AirFliq" ]; then
    echo "error: $APP is missing. Install the test build first." >&2
    exit 1
fi

echo "▸ Quitting AirFliq"
/usr/bin/killall AirFliq 2>/dev/null || true
sleep 0.5

if [ "${1:-}" = "--finder-off" ]; then
    echo "▸ Switching the Finder extension off (turn it back on from the Setup guide)"
    /usr/bin/pluginkit -e ignore -i "$EXTENSION_ID" || true
fi

echo "▸ Launching $APP with a fresh setup"
/usr/bin/open -n -a "$APP" --env AIRFLIQ_RESET_SETUP=1

echo ""
echo "✅ Setup starts from the first step. Quit and relaunch normally to keep your choices."
