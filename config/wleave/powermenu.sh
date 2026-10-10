#!/usr/bin/env bash
# Open wleave as a centred row of round buttons. wleave stretches its buttons
# to fill the screen minus the margins, so compute the margins from the
# focused monitor's logical size to keep every button SIZE x SIZE.

pgrep -x wleave >/dev/null && exit 0

SIZE=120     # button diameter in logical px
SPACING=32   # gap between buttons
COUNT=5      # buttons in layout.json

read -r width height < <(hyprctl monitors -j |
    jq -r '.[] | select(.focused) | "\((.width / .scale) | floor) \((.height / .scale) | floor)"')

row=$((COUNT * SIZE + (COUNT - 1) * SPACING))
margin_x=$(((width - row) / 2))
margin_y=$(((height - SIZE) / 2))

exec wleave \
    --buttons-per-row "$COUNT" \
    --column-spacing "$SPACING" \
    --margin-left "$margin_x" --margin-right "$margin_x" \
    --margin-top "$margin_y" --margin-bottom "$margin_y" \
    --button-aspect-ratio 1 \
    --close-on-lost-focus \
    --no-version-info
