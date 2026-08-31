#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PAYWALL_STILL="$ROOT/marketing/app-store/native/paywall.png"
RAW_DIR="$ROOT/marketing/shipaton/video/raw"
SCORE="$ROOT/marketing/shipaton/audio/airfliq-original-score.wav"

if [[ ! -f "$PAYWALL_STILL" ]]; then
  echo "Missing native paywall capture: $PAYWALL_STILL" >&2
  exit 1
fi

if [[ ! -f "$SCORE" ]]; then
  echo "Missing original score: $SCORE" >&2
  exit 1
fi

FFMPEG_BIN="$(command -v ffmpeg || true)"
if [[ -z "$FFMPEG_BIN" ]]; then
  echo "ffmpeg is required to render the final media." >&2
  exit 1
fi

mkdir -p "$RAW_DIR"
AIRFLIQ_MEDIA_TEMP="$(mktemp -d /private/tmp/airfliq-final-media.XXXXXX)"
trap 'rm -rf "$AIRFLIQ_MEDIA_TEMP"' EXIT
mkdir -p "$AIRFLIQ_MEDIA_TEMP/module-cache"

# The paywall scene is generated from the latest native macOS window capture.
# A subtle camera move is applied later by both Swift composition pipelines.
"$FFMPEG_BIN" \
  -y -hide_banner -loglevel error \
  -loop 1 -framerate 60 \
  -i "$PAYWALL_STILL" \
  -t 10 \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2:flags=lanczos,format=yuv420p" \
  -c:v libx264 -preset slow -tune stillimage -crf 12 \
  -r 60 -movflags +faststart \
  "$AIRFLIQ_MEDIA_TEMP/05-paywall.mov"
mv -f "$AIRFLIQ_MEDIA_TEMP/05-paywall.mov" "$RAW_DIR/05-paywall.mov"

compile_swift_tool() {
  local source="$1"
  local output="$2"
  xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$AIRFLIQ_MEDIA_TEMP/module-cache" \
    "$ROOT/$source" \
    -o "$AIRFLIQ_MEDIA_TEMP/$output"
}

compile_swift_tool "marketing/app-store/ComposeAppPreviewFilm.swift" "compose-app-preview"
compile_swift_tool "marketing/app-store/MixAppPreviewFilm.swift" "mix-app-preview"
compile_swift_tool "marketing/shipaton/ComposeProductFilm.swift" "compose-product-film"
compile_swift_tool "marketing/shipaton/MixProductFilm.swift" "mix-product-film"

cd "$ROOT"
"$AIRFLIQ_MEDIA_TEMP/compose-app-preview"
if [[ -n "${AIRFLIQ_APP_PREVIEW_NARRATION_PATH:-}" && -f "$AIRFLIQ_APP_PREVIEW_NARRATION_PATH" ]]; then
  "$AIRFLIQ_MEDIA_TEMP/mix-app-preview" "$AIRFLIQ_APP_PREVIEW_NARRATION_PATH"
else
  "$AIRFLIQ_MEDIA_TEMP/mix-app-preview"
fi

"$AIRFLIQ_MEDIA_TEMP/compose-product-film"
if [[ -n "${AIRFLIQ_SHIPATON_NARRATION_PATH:-}" && -f "$AIRFLIQ_SHIPATON_NARRATION_PATH" ]]; then
  "$AIRFLIQ_MEDIA_TEMP/mix-product-film" "$AIRFLIQ_SHIPATON_NARRATION_PATH"
else
  "$AIRFLIQ_MEDIA_TEMP/mix-product-film"
fi

echo "Final media rendered from the current native paywall capture."
