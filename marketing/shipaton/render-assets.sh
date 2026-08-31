#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
MAGICK="/opt/homebrew/bin/magick"
OUT="$ROOT/marketing/shipaton/assets"
ICON="$ROOT/marketing/app-store/assets/airfliq-icon.png"
NATIVE="$ROOT/marketing/app-store/native/onboarding-ready.png"
SHORTCUT="$ROOT/marketing/app-store/native/onboarding-shortcut.png"
HERO="$ROOT/marketing/app-store/final/01-airdrop-one-move.png"
FONT="/System/Library/Fonts/Avenir Next.ttc"

mkdir -p "$OUT"

"$MAGICK" "$ICON" \
  -resize 1024x1024! \
  -strip -colorspace sRGB \
  "$OUT/airfliq-icon-1024.png"

"$MAGICK" "$HERO" \
  -resize 1500x1000^ \
  -gravity center -extent 1500x1000 \
  -strip -colorspace sRGB \
  "$OUT/airfliq-thumbnail-3x2.png"

"$MAGICK" \
  -size 1179x2556 gradient:'#08142a-#070712' \
  -fill '#15396844' -draw 'circle 590,1040 1100,1040' \
  -fill '#3420612e' -draw 'circle 910,1430 1360,1430' \
  \( "$ICON" -resize 150x150 \) -gravity north -geometry +0+104 -composite \
  -font "$FONT" -fill '#89dcff' -pointsize 30 -gravity north \
  -annotate +0+278 'AIRFLIQ' \
  -font "$FONT" -fill white -pointsize 78 -gravity north \
  -annotate +0+345 'AirDrop in one move.' \
  -font "$FONT" -fill '#aeb6c9' -pointsize 32 -gravity north \
  -annotate +0+457 'Select. Shortcut. Right-click. Drag.' \
  -stroke '#2d416a' -strokewidth 2 -fill '#111529dd' \
  -draw 'roundrectangle 42,583 1137,1638 44,44' \
  \( "$NATIVE" -background none -resize 1035x958 \
     \( +clone -background '#209cff55' -shadow 34x14+0+20 \) \
     +swap -background none -layers merge +repage \) \
  -gravity north -geometry +0+620 -composite \
  -stroke none -fill '#0d1224e8' \
  -draw 'roundrectangle 70,1730 1109,2042 38,38' \
  -stroke '#243452' -strokewidth 2 -fill '#11182b' \
  -draw 'roundrectangle 96,1760 572,1872 30,30' \
  -draw 'roundrectangle 607,1760 1083,1872 30,30' \
  -draw 'roundrectangle 96,1900 572,2012 30,30' \
  -draw 'roundrectangle 607,1900 1083,2012 30,30' \
  -stroke none -font "$FONT" -fill '#48c9ff' -pointsize 30 -gravity northwest \
  -annotate +132+1794 '⌘  Global shortcut' \
  -fill '#8b6cff' -annotate +643+1794 '⌁  Magnetic drag' \
  -fill '#62e7a5' -annotate +132+1934 '⌁  Finder right-click' \
  -fill '#f1f4ff' -annotate +643+1934 '◉  Menu bar' \
  -stroke none -fill '#168bff' -draw 'roundrectangle 96,2118 1083,2260 42,42' \
  -font "$FONT" -fill white -pointsize 39 -gravity north \
  -annotate +0+2152 '7-day full trial  ·  $4.99 lifetime' \
  -font "$FONT" -fill '#aeb6c9' -pointsize 28 -gravity north \
  -annotate +0+2323 'Native macOS  ·  Apple Silicon + Intel' \
  -font "$FONT" -fill '#65718b' -pointsize 25 -gravity north \
  -annotate +0+2390 'User-selected folders  ·  No Full Disk Access' \
  -font "$FONT" -fill '#55627b' -pointsize 24 -gravity south \
  -annotate +0+75 '#Shipaton  ·  Built with RevenueCat' \
  -strip -colorspace sRGB \
  "$OUT/airfliq-devpost-1179x2556.png"

# Shipaton requires an exact 1179x2556 screenshot of the real app without a
# device mockup. Keep this asset factual: two native AirFliq window captures,
# no generated UI, no laptop or phone frame, and no promotional copy.
"$MAGICK" \
  -size 1179x2556 gradient:'#08142a-#080811' \
  -fill '#173f7438' -draw 'circle 220,460 880,460' \
  -fill '#43276a2d' -draw 'circle 980,1970 1640,1970' \
  \( "$NATIVE" -background none -resize 1115x1032 \
     \( +clone -background '#2797ff45' -shadow 30x12+0+20 \) \
     +swap -background none -layers merge +repage \) \
  -gravity north -geometry +0+90 -composite \
  \( "$SHORTCUT" -background none -resize 1115x1032 \
     \( +clone -background '#7549ff45' -shadow 30x12+0+20 \) \
     +swap -background none -layers merge +repage \) \
  -gravity north -geometry +0+1320 -composite \
  -strip -colorspace sRGB \
  "$OUT/airfliq-app-screenshot-1179x2556.png"

# Devpost limits gallery files to 5 MB. The screenshot is fully opaque, so a
# high-quality 4:4:4 JPEG keeps interface text crisp while meeting the limit.
"$MAGICK" "$OUT/airfliq-app-screenshot-1179x2556.png" \
  -background '#080811' -alpha remove -alpha off \
  -sampling-factor 4:4:4 -quality 94 -strip \
  "$OUT/airfliq-app-screenshot-1179x2556.jpg"

for file in "$OUT"/*.png; do
  /usr/bin/sips -g pixelWidth -g pixelHeight "$file" 2>/dev/null | tail -n 2 | tr '\n' ' '
  printf ' %s\n' "$file"
done
