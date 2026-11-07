# shellcheck shell=bash
# Built with writeShellApplication (pkgs/default.nix), which adds the shebang
# The idle steps only laptops take (config/hypr/hypridle.conf):
#   laptop-idle dim       the backlight down to 10 % (from more), remembered
#   laptop-idle undim     back to where it was, after dim
#   laptop-idle suspend   suspend, but only on battery
# Does nothing outside the laptop mode (config/hypr/modes.lua).
# brightnessctl, busctl and systemctl come from the system.
usage="usage: laptop-idle dim|undim|suspend"
runtime=${XDG_RUNTIME_DIR:-/tmp}
modes=$runtime/dotfiles-modes.json
dimmed=$runtime/laptop-idle-dimmed
dim_percent=10
upower=org.freedesktop.UPower
upower_path=/org/freedesktop/UPower

# modes.lua writes the file; before it has, no mode is on
is_laptop_mode() {
    if [ ! -f "$modes" ]; then
        return 1
    fi
    grep -q '"laptop":true' "$modes"
}

backlight_percent() {
    brightnessctl -m -c backlight info | cut -d, -f4 | tr -d %
}

# -s saves the brightness for undim's -r
dim() {
    local percent
    percent=$(backlight_percent)
    if [ "$percent" -le "$dim_percent" ]; then
        return 0
    fi
    brightnessctl -q -c backlight -s set "$dim_percent%"
    touch "$dimmed"
}

undim() {
    if [ ! -e "$dimmed" ]; then
        return 0
    fi
    rm -f "$dimmed"
    brightnessctl -q -c backlight -r
}

is_on_battery() {
    local on_battery
    on_battery=$(busctl get-property "$upower" "$upower_path" "$upower" OnBattery)
    [ "$on_battery" = "b true" ]
}

suspend_on_battery() {
    if is_on_battery; then
        systemctl suspend
    fi
}

if ! is_laptop_mode; then
    exit 0
fi

case ${1:-} in
    dim)
        dim
        ;;
    undim)
        undim
        ;;
    suspend)
        suspend_on_battery
        ;;
    *)
        echo "$usage" >&2
        exit 1
        ;;
esac
