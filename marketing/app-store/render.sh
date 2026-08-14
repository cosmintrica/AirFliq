#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/output"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

mkdir -p "$OUT"

names=(
    "01-airdrop-in-one-move"
    "02-you-choose-the-access"
    "03-drag-drop-fly"
    "04-right-click-done"
    "05-four-ways-one-airdrop"
)

for index in 1 2 3 4 5; do
    name="${names[$((index - 1))]}"
    "$CHROME" \
        --headless=new \
        --hide-scrollbars \
        --disable-gpu \
        --force-device-scale-factor=1 \
        --window-size=2880,1800 \
        --screenshot="$OUT/$name.png" \
        "file://$HERE/index.html?slide=$index"
done

echo "Rendered Mac App Store screenshots to $OUT"
