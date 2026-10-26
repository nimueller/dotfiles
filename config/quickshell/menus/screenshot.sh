#!/usr/bin/env bash
# Screenshots with an editor in Quickshell (screenshot.qml).
#   screenshot.sh [region|window|screen]
#       Freeze every monitor (grim), then open the editor on top: pick a
#       region or a window, adjust it, draw on it, choose the resolution, copy
#       or save. `window` and `screen` start with the active window or the
#       focused monitor already selected.
#   screenshot.sh --export <dir> <source.png> <layer.png|-> <WxH+X+Y> <percent> copy|save|text
#       Run by the editor as it closes: draws the layer over the screenshot,
#       crops and scales it, copies it (and saves it), with a notification.
#       `text` copies what's in it instead: the content of the QR codes or
#       barcodes (zbar), else the text Tesseract reads.
dir=$(dirname "$(readlink -f "$0")")
runtime=${XDG_RUNTIME_DIR:-/tmp}/qs-screenshot
saved=$HOME/Pictures/Screenshots

notify() {
    # Keep waiting for a click on an action for a while, not forever
    timeout 300 notify-send -a Screenshot "$@"
}

# Success only pops up: transient, so it stays out of the notification center
notify_done() {
    notify -e "$@"
}

# Escapes text for a notification body, which takes markup
markup() {
    local s=${1//&/&amp;}
    s=${s//</&lt;}
    printf '%s' "${s//>/&gt;}"
}

read_text() {
    local img=$1 text what
    if text=$(zbarimg --raw -q "$img"); then
        what="QR code"
    else
        # Twice the size: Tesseract misses small letters at 1x
        text=$(magick "$img" -colorspace Gray -resize 200% png:- | tesseract - - -l deu+eng -c page_separator= 2>/dev/null)
        what="Text"
    fi
    if [[ -z ${text//[[:space:]]/} ]]; then
        notify -i dialog-information "No text found" "Neither a QR code nor text in the selection"
        return 1
    fi
    printf '%s' "$text" | wl-copy --type text/plain

    local preview=$text
    ((${#preview} > 300)) && preview="${preview:0:300}…"
    if [[ $text =~ ^https?://[^[:space:]]+$ ]]; then
        case $(notify_done -i edit-paste -A open=Open "$what copied" "$(markup "$preview")") in
            open) xdg-open "$text" ;;
        esac
    else
        notify_done -i edit-paste "$what copied" "$(markup "$preview")"
    fi
}

export_shot() {
    local shot=$1 source=$2 layer=$3 geometry=$4 percent=$5 action=$6
    local out=$runtime/last.png args=("$source")

    [[ $layer != - ]] && args+=("$layer" -composite)
    args+=(-crop "$geometry" +repage)
    # The text is read at full size
    [[ $percent != 100 && $action != text ]] && args+=(-resize "$percent%")
    if ! magick "${args[@]}" "$out"; then
        notify -u critical -i dialog-error "Screenshot failed" "ImageMagick couldn't write the image"
        rm -rf "$shot"
        return 1
    fi
    rm -rf "$shot"
    if [[ $action == text ]]; then
        read_text "$out"
        return
    fi
    wl-copy --type image/png <"$out"

    local size file
    size=$(magick identify -format "%w × %h" "$out")
    if [[ $action == save ]]; then
        mkdir -p "$saved"
        file=$saved/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png
        cp "$out" "$file"
        case $(notify_done -i "$file" -A open=Open -A folder="Show in folder" "Screenshot saved" "$(basename "$file") · $size, also copied") in
            open) xdg-open "$file" ;;
            folder) xdg-open "$saved" ;;
        esac
    else
        case $(notify_done -i "$out" -A save=Save "Screenshot copied" "$size") in
            save)
                mkdir -p "$saved"
                file=$saved/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png
                cp "$out" "$file"
                notify_done -i "$file" "Screenshot saved" "$(basename "$file")"
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
qs list -p "$entry" 2>/dev/null | grep -q "Process ID:" && exit 0

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
