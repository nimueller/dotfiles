#!/usr/bin/env bash
# What the connected monitors support, for Machine Settings (settings.qml):
# one line each, e.g. "DP-1 vrr=1 wide=1 hdr=0".
#   vrr   the kernel's vrr_capable (the driver checked monitor and link)
#   wide  BT.2020 in the EDID's colorimetry block
#   hdr   PQ (SMPTE ST 2084) in the EDID's HDR metadata block
# Hyprland reads wide and hdr from the EDID the same way (libdisplay-info,
# whose di-edid-decode this uses); modetest is libdrm's.

# Without a tool its fields are left out: unknown, so not switched off
command -v modetest >/dev/null && has_modetest=1
command -v di-edid-decode >/dev/null && has_edid=1

# vrr_capable of every connector: "DP-1 1". modetest opens a card by its
# DRM driver's name, which is the kernel module's, or nvidia's plus "-drm"
vrr=$([[ $has_modetest ]] && for card in /sys/class/drm/card[0-9]; do
    driver=$(basename "$(readlink -f "$card/device/driver")")
    { modetest -M "$driver" -c 2>/dev/null || modetest -M "$driver-drm" -c 2>/dev/null; } | awk '
        $3 == "connected" || $3 == "disconnected" { name = $4 }
        /vrr_capable:/ { want = 1 }
        want && $1 == "value:" { print name, $2; want = 0 }'
done)

for connector in /sys/class/drm/card*-*; do
    [[ $(cat "$connector/status" 2>/dev/null) == connected ]] || continue
    name=${connector##*/card[0-9]-}
    line=$name
    if [[ $has_modetest ]]; then
        v=$(awk -v n="$name" '$1 == n { print $2; exit }' <<<"$vrr")
        line+=" vrr=${v:-0}"
    fi
    if [[ $has_edid ]]; then
        edid=$(di-edid-decode <"$connector/edid" 2>/dev/null)
        grep -q BT2020RGB <<<"$edid" && line+=" wide=1" || line+=" wide=0"
        grep -q 'SMPTE ST2084' <<<"$edid" && line+=" hdr=1" || line+=" hdr=0"
    fi
    echo "$line"
done
