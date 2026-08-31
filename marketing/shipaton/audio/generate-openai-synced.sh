#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h:h}"
AUDIO_DIR="$ROOT/marketing/shipaton/audio"
ENV_FILE="$AUDIO_DIR/.env.local"
SCENE_ROOT="$AUDIO_DIR/openai-synced-scenes"
COMPOSER="$AUDIO_DIR/compose_voiceover.py"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

: "${OPENAI_API_KEY:?Add OPENAI_API_KEY to $ENV_FILE or export it before running this script}"

for command in curl jq ffmpeg ffprobe python3; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

MODEL="${OPENAI_TTS_MODEL:-gpt-4o-mini-tts}"
VOICE="${OPENAI_TTS_VOICE:-marin}"
INSTRUCTIONS="Confident, warm product-film narrator. Premium and understated. Conversational, never theatrical. Crisp pronunciation and short natural pauses. Pronounce AirFliq as Air Flick."

mkdir -p "$SCENE_ROOT/shipaton" "$SCENE_ROOT/app-preview"

function synthesize_clip() {
  local group="$1"
  local index="$2"
  local line="$3"
  local maximum_duration="$4"
  local padded
  padded="$(printf '%02d' "$index")"
  local source="$SCENE_ROOT/$group/scene-$padded-source.wav"
  local normalized="$SCENE_ROOT/$group/scene-$padded-normalized.wav"
  local output="$SCENE_ROOT/$group/scene-$padded.wav"

  local payload
  payload="$(jq -n \
    --arg model "$MODEL" \
    --arg voice "$VOICE" \
    --arg input "$line" \
    --arg instructions "$INSTRUCTIONS" \
    '{model: $model, voice: $voice, input: $input, instructions: $instructions, response_format: "wav", speed: 1.0}')"

  curl --fail-with-body --silent --show-error \
    https://api.openai.com/v1/audio/speech \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    --output "$source"

  ffmpeg -y -hide_banner -loglevel error \
    -i "$source" -ar 48000 -ac 1 -c:a pcm_s16le "$normalized"

  local actual_duration
  actual_duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$normalized")"
  local ratio
  ratio="$(awk -v actual="$actual_duration" -v maximum="$maximum_duration" \
    'BEGIN { if (actual > maximum) printf "%.8f", actual / maximum; else print "1.0" }')"

  ffmpeg -y -hide_banner -loglevel error \
    -i "$normalized" -filter:a "atempo=$ratio" -ar 48000 -ac 1 -c:a pcm_s16le "$output"
  print -r -- "$output"
}

# Shipaton product film: exact picture boundaries are
# 0.00, 3.50, 9.00, 18.00, 24.00, 29.95, 34.45, 42.45 and 49.98.
shipaton_starts=(0.25 3.75 9.25 18.25 24.25 30.20 34.70 42.70)
shipaton_maximums=(3.00 4.90 8.30 5.30 5.30 3.90 7.30 6.75)
shipaton_lines=(
  "AirDrop in one move. Meet AirFliq for macOS."
  "A short, transparent setup keeps you in control."
  "Choose a global shortcut that feels natural, or record your own."
  "Or just drag. A magnetic target meets your cursor."
  "Drop, get clear feedback, then continue in native AirDrop."
  "Shortcut, right-click, menu bar, or drag. Pick your path."
  "Try every feature for seven days. RevenueCat powers one simple four ninety-nine lifetime purchase."
  "AirFliq. Select. Fliq. Sent. Built for macOS and built in public."
)

shipaton_compose_args=()
for index in {1..8}; do
  clip="$(synthesize_clip shipaton "$index" "${shipaton_lines[$index]}" "${shipaton_maximums[$index]}")"
  shipaton_compose_args+=("${shipaton_starts[$index]}" "$clip")
done

shipaton_wav="$AUDIO_DIR/airfliq-shipaton-voiceover-openai.wav"
shipaton_m4a="$AUDIO_DIR/airfliq-shipaton-voiceover-openai.m4a"
python3 "$COMPOSER" "$shipaton_wav" 49.98 "${shipaton_compose_args[@]}"
ffmpeg -y -hide_banner -loglevel error \
  -i "$shipaton_wav" -c:a aac -b:a 256k -ar 48000 -ac 1 "$shipaton_m4a"

# App Store App Preview: exact picture boundaries are
# 0.00, 4.00, 11.00, 15.50, 19.50, 23.00 and 29.00.
preview_starts=(0.20 4.20 11.20 15.70 19.70 23.20)
preview_maximums=(3.40 6.30 3.90 3.40 2.90 5.20)
preview_lines=(
  "AirFliq is ready in four clear steps."
  "Choose a preset or record the shortcut that feels natural."
  "Prefer drag? AirFliq meets your cursor."
  "Drop, get clear feedback, then continue in native AirDrop."
  "Use the menu bar, shortcut, right-click, or drag."
  "Try every feature for seven days, then unlock AirFliq once for four ninety-nine."
)

preview_compose_args=()
for index in {1..6}; do
  clip="$(synthesize_clip app-preview "$index" "${preview_lines[$index]}" "${preview_maximums[$index]}")"
  preview_compose_args+=("${preview_starts[$index]}" "$clip")
done

preview_wav="$AUDIO_DIR/airfliq-app-preview-voiceover-openai.wav"
preview_m4a="$AUDIO_DIR/airfliq-app-preview-voiceover-openai.m4a"
python3 "$COMPOSER" "$preview_wav" 29.00 "${preview_compose_args[@]}"
ffmpeg -y -hide_banner -loglevel error \
  -i "$preview_wav" -c:a aac -b:a 256k -ar 48000 -ac 1 "$preview_m4a"

echo "Created exact-timeline voiceovers:"
echo "  $shipaton_wav"
echo "  $preview_wav"
echo
echo "Mix commands after generation:"
echo "  MixProductFilm $shipaton_wav"
echo "  MixAppPreviewFilm $preview_wav"
