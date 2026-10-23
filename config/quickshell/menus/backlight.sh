#!/usr/bin/env bash
# The built-in screen's brightness in percent, on one scale for the keys
# (Osd.qml) and the slider in the system menu (system.qml). A backlight
# whose driver already maps its values onto a perceived curve (scale
# "non-linear", e.g. pwm-backlight on the Surface Pro X) as it is, others
# (linear to the power) bent by an exponent of 4 so the steps look even.
# Never below 2 % of the backlight's range, where the screen goes dark
# (brightnessctl's own -n takes raw steps, not percent).
#   backlight.sh get | set <percent> | step <+/-percent>
# Prints the percent afterwards.
set -u
min=2 # % of the raw range

IFS=, read -r dev _ cur _ max < <(brightnessctl -m -c backlight info 2>/dev/null) || exit 1
exp=4
[[ $(cat "/sys/class/backlight/$dev/scale" 2>/dev/null) == non-linear ]] && exp=1

# raw -> percent, percent -> raw (at least min)
percent() { awk -v r="$1" -v m="$max" -v e="$exp" 'BEGIN { printf "%d", 100 * (r / m) ^ (1 / e) + 0.5 }'; }
raw() { awk -v p="$1" -v m="$max" -v e="$exp" -v n="$min" 'BEGIN { p = p > 100 ? 100 : p < 0 ? 0 : p; r = m * (p / 100) ^ e; if (r < m * n / 100) r = m * n / 100; printf "%d", r + 0.5 }'; }

case ${1:-get} in
    get) ;;
    set) cur=$(raw "${2:?percent}") ;;
    step) cur=$(raw $(($(percent "$cur") + ${2:?step}))) ;;
    *) exit 2 ;;
esac
[[ ${1:-get} == get ]] || brightnessctl -q -d "$dev" set "$cur"
percent "$cur"
echo
