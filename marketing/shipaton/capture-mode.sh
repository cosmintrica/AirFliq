#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
MODE="${1:?usage: capture-mode.sh MODE DURATION OUTPUT.mov}"
DURATION="${2:?usage: capture-mode.sh MODE DURATION OUTPUT.mov}"
OUTPUT="${3:?usage: capture-mode.sh MODE DURATION OUTPUT.mov}"
APP="${AIRFLIQ_CAPTURE_APP:-$ROOT/build/AirFliq.app}"
WINDOWS="$ROOT/build/tools/list-airfliq-windows"

if [[ ! -x "$APP/Contents/MacOS/AirFliq" ]]; then
  APP="/Applications/AirFliq.app"
fi
if [[ ! -x "$APP/Contents/MacOS/AirFliq" ]]; then
  echo "Missing AirFliq capture build. Run ./build.sh first." >&2
  exit 1
fi

if [[ ! -x "$WINDOWS" ]]; then
  mkdir -p "${WINDOWS:h}"
  swiftc "$ROOT/marketing/app-store/ListWindows.swift" \
    -o "$WINDOWS" -framework CoreGraphics -framework Foundation
fi

mkdir -p "${OUTPUT:h}"
AIRFLIQ_CAPTURE_MODE="$MODE" "$APP/Contents/MacOS/AirFliq" >/dev/null 2>&1 &

window_id=""
for attempt in {1..80}; do
  window_id="$($WINDOWS | jq -r 'first(.[] | select(.layer == 0) | .id) // empty')"
  [[ -n "$window_id" ]] && break
  sleep 0.05
done

if [[ -z "$window_id" ]]; then
  echo "AirFliq did not expose a capturable window for mode: $MODE" >&2
  exit 1
fi

echo "Capturing AirFliq window $window_id in mode $MODE"
screencapture -v -V"$DURATION" -l"$window_id" -x "$OUTPUT"
echo "$OUTPUT"
