#!/bin/zsh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ASSETS="$HERE/assets"
NATIVE="$HERE/native"
OUT="$HERE/final"
TMP="$OUT/.compose-native"

FONT="/System/Library/Fonts/SFNS.ttf"
ROUNDED="/System/Library/Fonts/SFNSRounded.ttf"
MONO="/System/Library/Fonts/SFNSMono.ttf"

CANVAS_W=2880
CANVAS_H=1800
LEFT_X=138
LEFT_W=1040

mkdir -p "$OUT" "$TMP"
trap 'rm -rf "$TMP"' EXIT

# The App Store set shares one deliberately restrained AirFliq surface: deep navy,
# a quiet cyan and violet flight ribbon, and enough contrast for Retina type.
make_base() {
    local output="$1"

    magick \
        -size ${CANVAS_W}x${CANVAS_H} gradient:'#081a34-#070716' \
        \( "$ASSETS/flight-ribbon.png" \
            -filter Lanczos -resize '3200x2048!' \
            -alpha set -channel A -evaluate multiply 0.24 +channel \) \
        -gravity southeast -geometry -240-220 -compose screen -composite \
        \( -size ${CANVAS_W}x${CANVAS_H} radial-gradient:'#00000000-#02040ac0' \) \
        -compose over -composite \
        -colorspace sRGB -depth 8 "$output"
}

add_brand() {
    local input="$1"
    local output="$2"

    magick "$input" \
        \( "$ASSETS/airfliq-icon.png" -filter Lanczos -resize 92x92 \) \
        -gravity northwest -geometry +138+86 -compose over -composite \
        -font "$ROUNDED" -fill '#f7f9ff' -stroke '#f7f9ff' -strokewidth 1.8 \
        -pointsize 43 -weight 900 -gravity northwest -annotate +254+95 'AirFliq' \
        -font "$MONO" -fill '#98a6c0' -stroke none -pointsize 18 -weight 800 \
        -annotate +256+151 'SELECT. FLIQ. SENT.' \
        "$output"
}

make_copy_layer() {
    local kicker="$1"
    local line_one="$2"
    local line_two="$3"
    local body="$4"
    local accent="$5"
    local output="$6"

    magick -size ${LEFT_W}x960 xc:none \
        -font "$MONO" -fill '#8fa1bf' -stroke none -pointsize 25 -weight 800 \
        -gravity northwest -annotate +0+12 "$kicker" \
        -font "$ROUNDED" -fill '#f7f9ff' -stroke '#f7f9ff' -strokewidth 7.2 \
        -pointsize 132 -weight 900 -annotate +0+106 "$line_one" \
        -fill "$accent" -stroke "$accent" -strokewidth 6.4 \
        -pointsize 126 -annotate +0+252 "$line_two" \
        \( -background none -size ${LEFT_W}x260 \
            -font "$FONT" -fill '#b7c1d4' -stroke '#b7c1d4' -strokewidth 0.75 \
            -pointsize 38 -weight 700 -gravity northwest \
            caption:"$body" \) \
        -geometry +0+492 -compose over -composite \
        "$output"
}

# The label is trimmed to its real painted bounds and then centered in the
# capsule. This avoids baseline offsets and keeps every pill mathematically even.
make_pill() {
    local label="$1"
    local width="$2"
    local output="$3"

    magick -size ${width}x82 xc:none \
        -fill '#11192bd9' -stroke '#91b8ff38' -strokewidth 2 \
        -draw "roundrectangle 1,1,$((width - 2)),80,40,40" \
        \( -background none -font "$FONT" -fill '#e1e7f2' \
            -stroke '#e1e7f2' -strokewidth 0.35 -pointsize 26 -weight 800 \
            label:"$label" -trim +repage \) \
        -gravity center -compose over -composite \
        "$output"
}

add_pills() {
    local input="$1"
    local one="$2"
    local two="$3"
    local three="$4"
    local output="$5"
    local width=320
    local gap=30

    make_pill "$one" "$width" "$TMP/pill-1.png"
    make_pill "$two" "$width" "$TMP/pill-2.png"
    make_pill "$three" "$width" "$TMP/pill-3.png"

    magick "$input" \
        \( "$TMP/pill-1.png" \) -gravity northwest -geometry +${LEFT_X}+1410 -compose over -composite \
        \( "$TMP/pill-2.png" \) -gravity northwest -geometry +$((LEFT_X + width + gap))+1410 -compose over -composite \
        \( "$TMP/pill-3.png" \) -gravity northwest -geometry +$((LEFT_X + 2 * (width + gap)))+1410 -compose over -composite \
        "$output"
}

add_copy() {
    local input="$1"
    local kicker="$2"
    local line_one="$3"
    local line_two="$4"
    local body="$5"
    local accent="$6"
    local output="$7"

    make_copy_layer "$kicker" "$line_one" "$line_two" "$body" "$accent" "$TMP/copy.png"
    magick "$input" "$TMP/copy.png" \
        -gravity northwest -geometry +${LEFT_X}+292 -compose over -composite \
        "$output"
}

prepare_capture() {
    local input="$1"
    local geometry="$2"
    local output="$3"

    # Crop the photographed window footer from marketing images only. The
    # shipping app retains its original pricing footer and all visual styles.
    # These captures come from the 660pt native window (without outer shadows).
    case "${input:t}" in
        onboarding-ready.png|onboarding-shortcut.png)
            local w h
            read w h <<< "$(magick identify -format '%w %h' "$input")"
            magick "$input" -crop "${w}x$((h - w * 110 / 660))+0+$((w * 32 / 660))" +repage "$TMP/setup-detail.png"
            input="$TMP/setup-detail.png"
            ;;
    esac

    magick "$input" \
        -filter Lanczos -resize "$geometry" \
        -unsharp 0x0.55+0.5+0.02 \
        -bordercolor none -border 26 \
        \( +clone -background '#000000a0' -shadow 60x22+0+30 \) \
        +swap -background none -layers merge +repage \
        "$output"
}

finish_png() {
    local input="$1"
    local output="$2"

    magick "$input" \
        -background '#050915' -alpha remove -alpha off \
        -colorspace sRGB -depth 8 -strip \
        -define png:color-type=2 -define png:compression-level=9 \
        "$output"
}

render_ready() {
    add_brand "$TMP/master-base.png" "$TMP/brand.png"
    add_copy "$TMP/brand.png" \
        'AIR DROP, ACCELERATED' \
        'AirDrop.' 'One move.' \
        'Choose files with your shortcut. Or send a Finder selection with right-click and drag-and-drop.' \
        '#4bd7ff' "$TMP/copy-ready.png"
    add_pills "$TMP/copy-ready.png" 'macOS 13+' 'Universal' 'Native AirDrop' "$TMP/pills-ready.png"
    prepare_capture "$NATIVE/onboarding-ready.png" '1380x1280' "$TMP/capture-ready.png"

    magick "$TMP/pills-ready.png" "$TMP/capture-ready.png" \
        -gravity northwest -geometry +1270+205 -compose over -composite \
        "$TMP/ready.png"
    finish_png "$TMP/ready.png" "$OUT/01-airdrop-one-move.png"
}

render_drag() {
    add_brand "$TMP/master-base.png" "$TMP/brand.png"
    add_copy "$TMP/brand.png" \
        'MAGNETIC DRAG TARGET' \
        'Drag it.' 'Fliq it.' \
        'Pick up a file. AirFliq meets your cursor and hands it straight to the native AirDrop panel.' \
        '#50d8ff' "$TMP/copy-drag.png"
    add_pills "$TMP/copy-drag.png" 'Appears nearby' 'Drop anywhere' 'Instant handoff' "$TMP/pills-drag.png"

    # There is no fabricated completion state. The composition pairs the real
    # setup capture with the real drag-hover capture already recorded from AirFliq.
    prepare_capture "$NATIVE/onboarding-ready.png" '930x960' "$TMP/capture-menu-drag.png"
    # Keep the compact native drag target close to its Retina capture size.
    # Enlarging this 454x240 window to card scale softens its type and icon.
    prepare_capture "$NATIVE/drag-target-hover.png" '560x296' "$TMP/capture-hover.png"

    magick "$TMP/pills-drag.png" \
        \( -size 1490x1320 xc:none \
            -fill '#0b1223a8' -stroke '#5f8dff2f' -strokewidth 2 \
            -draw 'roundrectangle 1,1,1488,1318,70,70' \) \
        -gravity northwest -geometry +1260+230 -compose over -composite \
        "$TMP/capture-menu-drag.png" -gravity northwest -geometry +1732+265 -compose over -composite \
        "$TMP/capture-hover.png" -gravity northwest -geometry +1430+1140 -compose over -composite \
        "$TMP/drag.png"
    finish_png "$TMP/drag.png" "$OUT/02-drag-drop-fliq.png"
}

render_menu() {
    add_brand "$TMP/master-base.png" "$TMP/brand.png"
    add_copy "$TMP/brand.png" \
        'BUILT AROUND YOUR WORKFLOW' \
        'Four ways.' 'One AirDrop.' \
        "Shortcut, right-click, drag target or menu bar. Every path opens Apple's familiar panel." \
        '#45d5ff' "$TMP/copy-menu.png"
    add_pills "$TMP/copy-menu.png" 'Choose files' 'Multiple items' 'Native AirDrop' "$TMP/pills-menu.png"
    prepare_capture "$NATIVE/file-picker.png" '1110x1144' "$TMP/capture-menu.png"

    magick "$TMP/pills-menu.png" \
        \( -size 1440x1400 xc:none \
            -fill '#0a1020a8' -stroke '#7a63ff32' -strokewidth 2 \
            -draw 'roundrectangle 1,1,1438,1398,72,72' \) \
        -gravity northwest -geometry +1310+190 -compose over -composite \
        "$TMP/capture-menu.png" -gravity northwest -geometry +1475+285 -compose over -composite \
        "$TMP/menu.png"
    finish_png "$TMP/menu.png" "$OUT/03-four-ways.png"
}

render_shortcut() {
    add_brand "$TMP/master-base.png" "$TMP/brand.png"
    add_copy "$TMP/brand.png" \
        'YOUR LAUNCH GESTURE' \
        'Your shortcut.' 'Your way.' \
        'Choose a preset or record the global combination that already feels natural.' \
        '#8a6cff' "$TMP/copy-shortcut.png"
    add_pills "$TMP/copy-shortcut.png" 'Eight presets' 'Custom keys' 'Global access' "$TMP/pills-shortcut.png"
    prepare_capture "$NATIVE/onboarding-shortcut.png" '1380x1280' "$TMP/capture-shortcut.png"

    magick "$TMP/pills-shortcut.png" "$TMP/capture-shortcut.png" \
        -gravity northwest -geometry +1270+205 -compose over -composite \
        "$TMP/shortcut.png"
    finish_png "$TMP/shortcut.png" "$OUT/04-your-shortcut.png"
}

make_base "$TMP/master-base.png"
render_ready
render_drag
render_menu
render_shortcut

echo "Composed four native Retina App Store screenshots in $OUT"
