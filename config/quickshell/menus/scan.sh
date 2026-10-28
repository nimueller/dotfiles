#!/usr/bin/env bash
# Helper of the scanner window (scan.qml), on SANE's scanimage.
#   scan.sh devices
#       The scanners as JSON: [{ device, name, backend, ip }]
#   scan.sh options <device>
#       What it offers as JSON: { resolutions, modes, sources, width, height }
#       (the area in mm) and the defaults (resolution, mode, source)
#   scan.sh scan <device> <dir> <prefix> <source> <mode> <dpi> <l> <t> <w> <h> [<count>]
#       Scan into <dir>/<prefix>-NNN.png (the area in mm): all pages in the
#       feeder, or <count> of them. Prints "progress <percent>" and
#       "page <file>" as it goes, and "error <message>" if it fails.
#   scan.sh feeder <ip>
#       "loaded" once the scanner is idle with paper in its feeder, else
#       "empty" (from its eSCL status; "unknown" without one)
#   scan.sh save pdf|ocr|jpg|png <file> <page>:<degrees>...
#       Save the pages (turned by <degrees>): one PDF (`ocr`: with the text
#       Tesseract reads, so it can be searched and copied), or one image each
#       (<file> then gets -1, -2, … before the extension). Prints the files,
#       then notifies.
#
# Only network scanners: sane-airscan (eSCL and WSD) and, if it's installed,
# Epson's own backend (epsonscan2, AUR), which gets every page from the
# feeder where the eSCL of some models hands over only the first. With every
# backend installed, scanimage takes ~10 s to look for scanners instead of
# ~1 s, and the escl backend prints printers' web pages as it goes.
cache=${XDG_CACHE_HOME:-$HOME/.cache}/qs-scan
export SANE_CONFIG_DIR=$cache/sane:
mkdir -p "$cache/sane"
{
    echo airscan
    compgen -G '/usr/lib/sane/libsane-epsonscan2.so*' >/dev/null && echo epsonscan2
} >"$cache/sane/dll.conf"

notify() {
    # Keep waiting for a click on an action for a while, not forever
    timeout 300 notify-send -a Scanner "$@"
}

# airscan names the address as the type ("ip=…"), epsonscan2 at the end
# of the device ("epsonscan2:networkscanner:esci2:network:<ip>"), with
# "network scanner" as the model: then the name airscan found there.
# epsonscan2 doesn't look for scanners in the network itself: it lists the
# addresses in its configuration, one per line, whether they answer or not.
# So that's kept to the Epson scanners airscan finds (eSCL/WSD), and only
# those epsonscan2 devices are listed, first, as they get every page from
# the feeder.
epson_conf=$HOME/.epsonscan2/Network/epsonscan2.conf

list_devices() {
    timeout 30 scanimage -f '%d	%v %m	%t%n' 2>/dev/null |
        jq -Rn '[inputs | split("\t") | select(length == 3)
            | { device: .[0], name: (.[1] | sub("^(eSCL|WSD) "; "")),
                backend: (.[0] | split(":")[0]),
                ip: ((.[2] | capture("ip=(?<a>[0-9.]+)").a) // (.[0] | capture(":(?<a>[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+)$").a) // "") }]'
}

devices() {
    local all epson
    all=$(list_devices)
    if grep -qx epsonscan2 "$cache/sane/dll.conf"; then
        epson=$(jq -r '[.[] | select(.backend != "epsonscan2" and .ip != "" and (.name | test("epson"; "i"))) | .ip] | unique | .[]' <<<"$all")
        if [[ -n $epson && $epson != "$(grep -E '^[0-9.]+$' "$epson_conf" 2>/dev/null | sort -u)" ]]; then
            mkdir -p "$(dirname "$epson_conf")"
            printf '[Network]\n%s\n' "$epson" >"$epson_conf"
            all=$(list_devices)
        fi
    fi
    jq '[.[] | select(.backend != "epsonscan2")] as $found
        | map(. as $d
            | select(.backend != "epsonscan2" or ([$found[].ip] | index($d.ip)))
            | if .backend == "epsonscan2" and (.name | test("network scanner"; "i"))
                then .name = ([$found[] | select(.ip == $d.ip) | .name][0] // .name)
                else . end)
        | sort_by(.backend != "epsonscan2")' <<<"$all"
}

# From `scanimage -A`, e.g.
#   --resolution 100|200|300|600|1200dpi [300]
#   --mode Color|Gray [Color]
#   --source Flatbed|ADF [Flatbed]
#   -x 0..215.9mm [215.9]
options() {
    local out
    out=$(timeout 30 scanimage -d "$1" -A 2>/dev/null) || {
        printf '{"error": "The scanner doesn'"'"'t answer"}\n'
        return 1
    }
    awk '
        function list(s) { gsub(/dpi/, "", s); n = split(s, a, "|"); r = ""; delete seen; for (i = 1; i <= n; i++) if (!seen[a[i]]++) r = r (r != "" ? "\t" : "") a[i]; return r }
        # A range ("50..1200dpi (in steps of 1)"): the usual steps in it
        function steps(s) { gsub(/dpi/, "", s); split(s, b, /\.\./); r = ""; split("75 100 150 200 300 600 1200", c, " "); for (i = 1; i <= 7; i++) if (c[i] + 0 >= b[1] + 0 && c[i] + 0 <= b[2] + 0) r = r (r != "" ? "\t" : "") c[i]; return r }
        function dflt(s) { gsub(/[\[\]]|dpi|mm/, "", s); return s }
        $1 == "--resolution" { print "resolutions\t" ($2 ~ /\.\./ ? steps($2) : list($2)); print "resolution\t" dflt($NF) }
        $1 == "--mode" { print "modes\t" list($2); print "mode\t" dflt($3) }
        $1 == "--source" { print "sources\t" list($2); print "source\t" dflt($3) }
        $1 == "-x" { sub(/mm$/, "", $2); split($2, a, /\.\./); print "width\t" a[2] }
        $1 == "-y" { sub(/mm$/, "", $2); split($2, a, /\.\./); print "height\t" a[2] }
    ' <<<"$out" | jq -Rn '
        [inputs | split("\t")] | map({ key: .[0], value: .[1:] }) | from_entries
        | { resolutions: ((.resolutions // []) | map(tonumber? // empty)),
            modes: (.modes // []), sources: (.sources // []),
            resolution: ((.resolution // [""])[0] | tonumber? // null),
            mode: (.mode // [null])[0], source: (.source // [null])[0],
            width: ((.width // ["0"])[0] | tonumber),
            # At most A4: Epson offers the 14" of its feeder, which leaves the
            # rest of an A4 page blank
            height: ([(.height // ["0"])[0] | tonumber, 297.18] | min) }'
}

scan() {
    local device=$1 dir=$2 prefix=$3 source=$4 mode=$5 dpi=$6 l=$7 t=$8 w=$9 h=${10} count=${11}
    local args=(-d "$device" --source "$source" --mode "$mode" --resolution "$dpi"
        -l "$l" -t "$t" -x "$w" -y "$h"
        --format=png --batch="$dir/$prefix-%03d.png" --batch-print --progress)
    [[ -n $count ]] && args+=(--batch-count="$count")
    # Epson's leaves out blank pages by default: the backs of pages printed
    # on one side, which would put the pages out of order with both sides
    [[ $device == epsonscan2:* ]] && args+=(--skip-blankpages 0)
    mkdir -p "$dir"
    # --batch-print names each page on stdout; the progress (with \r) and the
    # errors come on stderr (redirected first, so its sed writes to the real
    # stdout). exec, so stopping the process stops the scan.
    exec scanimage "${args[@]}" \
        2> >(tr '\r' '\n' | sed -un \
            -e 's/^Progress: \([0-9.]*\)%.*/progress \1/p' \
            -e 's/^scanimage: .*out of documents.*/error The feeder is empty/p' \
            -e 's/^scanimage: \(sane_[a-z_]*: \)\{0,1\}\(.*\)/error \2/p') \
        > >(sed -u 's/^/page /')
}

# Only while the scanner is idle: it reports the feeder loaded while it
# pulls a page in, too
feeder() {
    local status
    status=$(curl -sk --max-time 3 "https://$1/eSCL/ScannerStatus") || { echo unknown; return; }
    if [[ $status != *"<scan:AdfState>"* ]]; then
        echo unknown
    elif [[ $status == *"<pwg:State>Idle<"* && $status == *"<scan:AdfState>ScannerAdfLoaded<"* ]]; then
        echo loaded
    else
        echo empty
    fi
}

save() {
    local kind=$1 file=$2
    shift 2
    local work=$cache/save-$$ pages=() out=() i=0
    mkdir -p "$work" "$(dirname "$file")"
    # Expanded now: $work is local, gone by the time the script exits
    # shellcheck disable=SC2064
    trap "rm -rf '$work'" EXIT

    # Never over an earlier scan: "Name (2).pdf" (images: Name (2)-1.jpg, …)
    local stem=${file%.*} ext=${file##*.} n=1
    while [[ -e $file || -e ${file%.*}-1.$ext ]]; do
        ((n++))
        file="$stem ($n).$ext"
    done

    # Each page turned, as JPEG for a PDF (a PNG of a colour page at 300 dpi
    # makes a PDF ~10× as big); the resolution stays in it, so the PDF's
    # pages get their real size
    for arg in "$@"; do
        local page=${arg%:*} deg=${arg##*:} ext=png
        ((i++))
        [[ $kind != png ]] && ext=jpg
        local dst
        dst=$work/$(printf '%03d' "$i").$ext
        if ! magick "$page" -rotate "$deg" -quality 85 "$dst"; then
            notify -u critical -i dialog-error "Scan not saved" "ImageMagick couldn't read page $i"
            return 1
        fi
        pages+=("$dst")
    done

    case $kind in
        pdf)
            magick "${pages[@]}" -compress jpeg -quality 85 "$file" && out=("$file")
            ;;
        ocr)
            printf '%s\n' "${pages[@]}" >"$work/list.txt"
            tesseract "$work/list.txt" "${file%.pdf}" -l deu+eng pdf 2>/dev/null && out=("$file")
            ;;
        jpg | png)
            if ((${#pages[@]} == 1)); then
                cp "${pages[0]}" "$file" && out=("$file")
            else
                i=0
                for page in "${pages[@]}"; do
                    ((i++))
                    cp "$page" "${file%.*}-$i.${file##*.}" && out+=("${file%.*}-$i.${file##*.}")
                done
            fi
            ;;
    esac
    if ((${#out[@]} == 0)); then
        notify -u critical -i dialog-error "Scan not saved" "Couldn't write $(basename "$file")"
        return 1
    fi
    printf '%s\n' "${out[@]}"

    # The notification waits for a click: not on the window's stdout, so it
    # isn't kept waiting for it
    {
        local n=${#pages[@]} what
        what=$( ((n == 1)) && echo "1 page" || echo "$n pages")
        case $(notify -e -A open=Open -A folder="Show in folder" "Scan saved" "$(basename "${out[0]}") · $what") in
            open) xdg-open "${out[0]}" ;;
            folder) xdg-open "$(dirname "${out[0]}")" ;;
        esac
    } >/dev/null 2>&1 &
    disown
}

cmd=${1:?usage: scan.sh devices|options|scan|feeder|save ...}
shift
case $cmd in
    devices) devices ;;
    options) options "$@" ;;
    scan) scan "$@" ;;
    feeder) feeder "$@" ;;
    save) save "$@" ;;
    *) echo "unknown command: $cmd" >&2; exit 1 ;;
esac
