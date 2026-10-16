# shellcheck shell=bash
# Built with writeShellApplication (pkgs/default.nix), which adds the shebang
# The idle steps only laptops take (config/hypr/hypridle.conf):
#   laptop-idle dim       the backlight down to 10 % (from more), remembered
#   laptop-idle undim     back to where it was, after dim
#   laptop-idle suspend   suspend, but only on battery
# Does nothing outside the laptop mode (config/hypr/modes.lua).
# brightnessctl, busctl and systemctl come from the system.
runtime=${XDG_RUNTIME_DIR:-/tmp}
dimmed=$runtime/laptop-idle-dimmed

grep -q '"laptop":true' "$runtime/dotfiles-modes.json" 2>/dev/null || exit 0

case ${1:-} in
    dim)
        percent=$(brightnessctl -m -c backlight info 2>/dev/null | cut -d, -f4 | tr -d %)
        if [ "${percent:-0}" -gt 10 ] && brightnessctl -q -c backlight -s set 10%; then
            touch "$dimmed"
        fi
        ;;
    undim)
        if [ -e "$dimmed" ]; then
            rm -f "$dimmed"
            brightnessctl -q -c backlight -r
        fi
        ;;
    suspend)
        if [ "$(busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery)" = "b true" ]; then
            systemctl suspend
        fi
        ;;
    *)
        echo "usage: laptop-idle dim|undim|suspend" >&2
        exit 1
        ;;
esac
