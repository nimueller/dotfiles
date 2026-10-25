# shellcheck shell=bash
# Built with writeShellApplication (pkgs/default.nix), which adds the shebang
# Locks the screen with hyprlock, unless it's locked already:
#   lock-screen            lock (hypridle.conf, keybinds.lua, the power menu, the login)
#   lock-screen button     the lock screen's keyboard button, only in the touch mode
#   lock-screen keyboard   shows or hides the on-screen keyboard (the button's click)
#   lock-screen capslock   a warning while Caps Lock is on (the lock screen's label)
# In the touch mode (config/hypr/modes.lua) the on-screen keyboard (squeekboard)
# may show above the lock screen. It shows by itself where it would for a
# text field (in tablet mode, or always without a tablet mode switch): hyprlock
# has no text input of its own that would bring it up. After unlocking it hides.
# busctl, pgrep and hyprctl come from the system, jq from the package.
runtime=${XDG_RUNTIME_DIR:-/tmp}

touch_mode() {
    grep -q '"touch":true' "$runtime/dotfiles-modes.json" 2>/dev/null
}

# modes.lua writes the file only where there's a tablet mode switch
tablet_mode() {
    [ ! -e "$runtime/dotfiles-tablet" ] || grep -q true "$runtime/dotfiles-tablet"
}

# osk call SetVisible b true, osk get-property Visible
osk() {
    local verb=$1
    shift
    busctl --user "$verb" sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 "$@" 2>/dev/null
}

case ${1:-} in
    button)
        touch_mode && echo "󰌌"
        exit 0
        ;;
    keyboard)
        if [ "$(osk get-property Visible)" = "b true" ]; then
            osk call SetVisible b false
        else
            osk call SetVisible b true
        fi
        exit 0
        ;;
    capslock)
        if [ "$(hyprctl devices -j | jq '[.keyboards[] | select(.main) | .capsLock] | any')" = true ]; then
            echo "󰪛   Caps Lock is on"
        fi
        exit 0
        ;;
    "") ;;
    *)
        echo "usage: lock-screen [button|keyboard|capslock]" >&2
        exit 1
        ;;
esac

pgrep -xu "$UID" hyprlock >/dev/null && exit 0
if ! touch_mode; then
    exec hyprlock
fi

hyprlock &
lock=$!
# hyprlock takes clicks only on the screen the pointer entered, and a touch
# doesn't count as entering: the pointer put where it is gives it the screen
# for the keyboard button. Its surface takes a moment to show up (longer
# after a suspend), so a few times over the first seconds.
(
    for _ in $(seq 8); do
        sleep 0.5
        kill -0 "$lock" 2>/dev/null || exit 0
        read -r x y < <(hyprctl cursorpos | tr -d ,)
        hyprctl dispatch "hl.dsp.cursor.move({ x = $x, y = $y })" >/dev/null
    done
) &
# At the login squeekboard starts along with the lock screen, and the
# tablet mode switch reports its state a moment later: tries for a few seconds
for _ in $(seq 20); do
    sleep 0.25
    kill -0 "$lock" 2>/dev/null || break
    if tablet_mode && osk call SetVisible b true; then
        break
    fi
done
wait "$lock" || true
osk call SetVisible b false || true
