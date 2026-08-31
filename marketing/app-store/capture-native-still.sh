#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
MODE="${1:?usage: capture-native-still.sh MODE OUTPUT.png}"
OUTPUT="${2:?usage: capture-native-still.sh MODE OUTPUT.png}"
APP="$ROOT/build/AirFliq.app"
WINDOWS="$ROOT/build/tools/list-airfliq-windows"

if [[ ! -x "$APP/Contents/MacOS/AirFliq" ]]; then
  echo "Missing App Store test build at $APP" >&2
  exit 1
fi
if [[ ! -x "$WINDOWS" ]]; then
  mkdir -p "${WINDOWS:h}"
  swiftc "$ROOT/marketing/app-store/ListWindows.swift" \
    -o "$WINDOWS" -framework CoreGraphics -framework Foundation
fi

mkdir -p "${OUTPUT:h}"
AIRFLIQ_CAPTURE_MODE="$MODE" "$APP/Contents/MacOS/AirFliq" >/dev/null 2>&1 &
app_pid=$!
trap 'kill "$app_pid" 2>/dev/null || true' EXIT

window_id=""
for attempt in {1..100}; do
  window_id="$($WINDOWS | jq -r 'first(.[] | select(.layer == 0) | .id) // empty')"
  [[ -n "$window_id" ]] && break
  sleep 0.05
done

if [[ -z "$window_id" ]]; then
  echo "AirFliq did not expose a capturable window for mode: $MODE" >&2
  exit 1
fi

# Let the native entrance animation settle so the still records the final
# presentation rather than a partially transparent transition frame.
sleep 0.9
/usr/sbin/screencapture -l"$window_id" -x "$OUTPUT"
echo "$OUTPUT"
