#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h:h}"
AUDIO_DIR="$ROOT/marketing/shipaton/audio"
ENV_FILE="$AUDIO_DIR/.env.local"
PYTHON="/usr/local/bin/python3"
DURATION="118"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE"
  echo "Copy .env.example to .env.local and add a restricted ElevenLabs API key."
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

: "${ELEVENLABS_API_KEY:?ELEVENLABS_API_KEY is required}"
VOICE_ID="${ELEVENLABS_VOICE_ID:-JBFqnCBsd6RMkjVDRZzb}"

STARTS=(0 7 22 37 55 68 85 99 111)
LINES=(
  "Air Flick turns AirDrop into one fluid action, directly from Finder."
  "Select any file, press your shortcut, and the native AirDrop panel is ready. Cancelling keeps your trial untouched."
  "The same action lives directly inside Finder's right-click menu."
  "Or simply drag. A magnetic target meets the cursor, confirms the drop, and hands the file to AirDrop."
  "The menu bar keeps every launch method and setting one click away."
  "Setup explains every permission, lets you choose folder boundaries, and supports presets or any safe global shortcut."
  "Air Flick never asks for Full Disk Access. When a file needs permission, you choose the exact folder."
  "Every feature is available during a seven-day trial. RevenueCat powers the one-time four ninety-nine Lifetime Pro purchase and restore flow."
  "Air Flick. Select. Flick. Sent. Built for macOS and Shipaton."
)

for model in eleven_multilingual_v2 eleven_v3; do
  slug="${model#eleven_}"
  scene_dir="$AUDIO_DIR/$slug-scenes"
  mkdir -p "$scene_dir"
  compose_args=()

  for index in {1..9}; do
    padded="$(printf '%02d' "$index")"
    mp3="$scene_dir/scene-$padded.mp3"
    wav="$scene_dir/scene-$padded.wav"
    payload="$(jq -n \
      --arg text "${LINES[$index]}" \
      --arg model "$model" \
      '{
        text: $text,
        model_id: $model,
        voice_settings: {
          stability: 0.48,
          similarity_boost: 0.82,
          style: 0.18,
          use_speaker_boost: true,
          speed: 0.98
        }
      }')"

    curl --fail-with-body --silent --show-error \
      -X POST \
      "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID?output_format=mp3_44100_192" \
      -H "xi-api-key: $ELEVENLABS_API_KEY" \
      -H "Content-Type: application/json" \
      --data "$payload" \
      --output "$mp3"

    afconvert -f WAVE -d LEI16@48000 -c 1 "$mp3" "$wav"
    compose_args+=("${STARTS[$index]}" "$wav")
  done

  master_wav="$AUDIO_DIR/airfliq-shipaton-voiceover-$slug.wav"
  master_m4a="$AUDIO_DIR/airfliq-shipaton-voiceover-$slug.m4a"
  "$PYTHON" "$AUDIO_DIR/compose_voiceover.py" \
    "$master_wav" "$DURATION" "${compose_args[@]}"
  afconvert -f m4af -d aac -b 192000 "$master_wav" "$master_m4a"
done

for master in "$AUDIO_DIR"/airfliq-shipaton-voiceover-*.m4a; do
  afinfo "$master" | awk -F': ' '/estimated duration/ { printf "%s seconds  ", $2 } END { print ARGV[1] }' "$master"
done
