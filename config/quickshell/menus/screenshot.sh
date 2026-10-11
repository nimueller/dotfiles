#!/usr/bin/env bash
# Screenshots with an editor in Quickshell (screenshot.qml).
#   screenshot.sh [region|window|screen]
#       Freeze every monitor (grim), then open the editor on top: pick a
#       region or a window, adjust it, draw on it, choose the resolution, copy
#       or save. `window` and `screen` start with the active window or the
#       focused monitor already selected.
#   screenshot.sh --export <dir> <source.png> <layer.png|-> <WxH+X+Y> <percent> copy|save
#       Run by the editor as it closes: draws the layer over the screenshot,
#       crops and scales it, copies it (and saves it), with a notification.
dir=$(dirname "$(readlink -f "$0")")
runtime=${XDG_RUNTIME_DIR:-/tmp}/qs-screenshot
saved=$HOME/Pictures/Screenshots

notify() {
    # Keep waiting for a click on an action for a while, not forever
    timeout 300 notify-send -a Screenshot "$@"
}

export_shot() {
    local shot=$1 source=$2 layer=$3 geometry=$4 percent=$5 action=$6
    local out=$runtime/last.png args=("$source")

    [[ $layer != - ]] && args+=("$layer" -composite)
    args+=(-crop "$geometry" +repage)
    [[ $percent != 100 ]] && args+=(-resize "$percent%")
    if ! magick "${args[@]}" "$out"; then
        notify -u critical -i dialog-error "Screenshot failed" "ImageMagick couldn't write the image"
        rm -rf "$shot"
        return 1
    fi
    rm -rf "$shot"
    wl-copy --type image/png <"$out"

    local size file
    size=$(magick identify -format "%w × %h" "$out")
    if [[ $action == save ]]; then
        mkdir -p "$saved"
        file=$saved/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png
        cp "$out" "$file"
        case $(notify -i "$file" -A open=Open -A folder="Show in folder" "Screenshot saved" "$(basename "$file") · $size, also copied") in
            open) xdg-open "$file" ;;
            folder) xdg-open "$saved" ;;
        esac
    else
        case $(notify -i "$out" -A save=Save "Screenshot copied" "$size") in
            save)
                mkdir -p "$saved"
                file=$saved/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png
                cp "$out" "$file"
                notify -i "$file" "Screenshot saved" "$(basename "$file")"
                ;;
        esac
    fi
}

if [[ $1 == --export ]]; then
    shift
    export_shot "$@"
    exit
fi

entry=$dir/screenshot.qml
pgrep -f "quickshell.* -p $entry" >/dev/null && exit 0

# Leftovers of cancelled or crashed editors
mkdir -p "$runtime"
find "$runtime" -mindepth 1 -maxdepth 1 -type d -mmin +10 -exec rm -rf {} +

shot=$runtime/$(date +%s%N)
mkdir -p "$shot"
monitors=$(hyprctl monitors -j)
# Uncompressed PNGs: ~70 ms for 4K instead of ~270 ms; the export compresses
while read -r name; do
    grim -l 0 -o "$name" "$shot/$name.png" &
done < <(jq -r '.[].name' <<<"$monitors")
printf '%s' "$monitors" >"$shot/monitors.json"
hyprctl clients -j >"$shot/clients.json"
wait

QS_SCREENSHOT_DIR=$shot QS_SCREENSHOT_MODE=${1:-region} exec qs -p "$entry" -n -d >/dev/null 2>&1
