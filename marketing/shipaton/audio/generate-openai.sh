#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h:h}"
AUDIO_DIR="$ROOT/marketing/shipaton/audio"
ENV_FILE="$AUDIO_DIR/.env.local"
SCENE_DIR="$AUDIO_DIR/openai-scenes"
PYTHON="$(command -v python3)"
DURATION="49.98"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

: "${OPENAI_API_KEY:?Add OPENAI_API_KEY to $ENV_FILE or export it in your shell}"

MODEL="${OPENAI_TTS_MODEL:-gpt-4o-mini-tts}"
VOICE="${OPENAI_TTS_VOICE:-marin}"
INSTRUCTIONS="Confident, elegant product-film narrator. Warm, modern and conversational. Premium and understated, never theatrical. Crisp pronunciation with short natural pauses. Pronounce AirFliq as Air Flick."
STARTS=(0.6 8.5 22.3 28.4 34.3 44.4)
LINES=(
  "AirFliq turns AirDrop into one fluid move, right from your Mac."
  "Choose a global shortcut that feels natural. Make the launch gesture yours."
  "Or just drag. A magnetic target meets your cursor exactly when you need it."
  "Drop, and AirFliq confirms the handoff before opening the native AirDrop panel."
  "Try every feature for seven days. RevenueCat powers one simple four ninety-nine lifetime purchase."
  "No Full Disk Access. Native macOS. Select. Fliq. Sent."
)

mkdir -p "$SCENE_DIR"
compose_args=()

for index in {1..6}; do
  padded="$(printf '%02d' "$index")"
  source_wav="$SCENE_DIR/scene-$padded-source.wav"
  wav="$SCENE_DIR/scene-$padded.wav"
  payload="$(jq -n \
    --arg model "$MODEL" \
    --arg voice "$VOICE" \
    --arg input "${LINES[$index]}" \
    --arg instructions "$INSTRUCTIONS" \
    '{model: $model, voice: $voice, input: $input, instructions: $instructions, response_format: "wav", speed: 1.0}')"

  curl --fail-with-body --silent --show-error \
    https://api.openai.com/v1/audio/speech \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    --output "$source_wav"

  afconvert -f WAVE -d LEI16@48000 -c 1 "$source_wav" "$wav"
  compose_args+=("${STARTS[$index]}" "$wav")
done

master_wav="$AUDIO_DIR/airfliq-shipaton-voiceover-openai.wav"
master_m4a="$AUDIO_DIR/airfliq-shipaton-voiceover-openai.m4a"
"$PYTHON" "$AUDIO_DIR/compose_voiceover.py" \
  "$master_wav" "$DURATION" "${compose_args[@]}"
afconvert -f m4af -d aac -b 192000 "$master_wav" "$master_m4a"

echo "$master_m4a"
