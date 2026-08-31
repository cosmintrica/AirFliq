#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
OUTPUT_DIR="$ROOT/marketing/shipaton/video"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT="$OUTPUT_DIR/airfliq-demo-raw-$STAMP.mov"

mkdir -p "$OUTPUT_DIR"

echo "AirFliq Shipaton recording"
echo ""
echo "1. Close personal and unrelated apps."
echo "2. Disable notifications and hide unrelated menu bar icons."
echo "3. Open Finder with the prepared demo files."
echo "4. Keep marketing/shipaton/video-plan.md visible on another device."
echo "5. In the native toolbar, choose Record Selected Portion or the main display."
echo "6. Stop before 1:58. Never choose an AirDrop recipient."
echo ""
echo "The native macOS recording toolbar will open now."
echo "Output: $OUTPUT"

/usr/sbin/screencapture -v -Jvideo -i -U -k "$OUTPUT"

echo ""
echo "Recording saved to: $OUTPUT"
