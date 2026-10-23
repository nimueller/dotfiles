#!/usr/bin/env bash
# Reboot or shut down from the power menu (power.qml): close the apps and
# Hyprland with hyprshutdown first, which shows the apps that hold it up,
# then run the command.
#   shutdown.sh <label> <command>
# hyprshutdown ends every program of the session at once, the shell, the
# wallpaper and the idle lock too, and has no way to leave some running. On
# Cancel, start them again (autostart.lua: daemons).
label=$1 command=$2

# Seconds the apps get to close before they are killed (hyprshutdown itself
# only waits, or kills on its Force quit button)
timeout=30

command -v hyprshutdown >/dev/null || exec sh -c "$command"

# Kill what hyprshutdown waits for: the windows and Hyprland's own children
# but Xwayland. With none left it exits Hyprland and runs the command.
force_quit() {
    local hyprland pid
    hyprland=$(hyprctl instances -j | jq --arg i "$HYPRLAND_INSTANCE_SIGNATURE" '.[] | select(.instance == $i) | .pid')
    for pid in $({ hyprctl clients -j | jq '.[].pid'; [[ -n $hyprland ]] && pgrep -P "$hyprland"; } | sort -u); do
        ((pid > 0 && pid != $$ && pid != shutdown)) || continue
        [[ $(ps -o comm= -p "$pid") == Xwayland ]] && continue
        kill -KILL "$pid" 2>/dev/null
    done
}

# Only there once hyprshutdown has closed everything
closed=${XDG_RUNTIME_DIR:-/tmp}/hyprshutdown-closed
rm -f "$closed"
hyprshutdown --no-fork -t "$label" -p "touch '$closed'; $command" &
shutdown=$!

# Ends with hyprshutdown, so Cancel stops it too
(
    for ((i = 0; i < timeout; i++)); do
        sleep 1
        kill -0 "$shutdown" 2>/dev/null || exit
    done
    force_quit
    # Still held up (an app that can't be killed): run the command anyway
    sleep 5
    kill -0 "$shutdown" 2>/dev/null || exit
    touch "$closed"
    kill "$shutdown"
    sh -c "$command"
) &

wait "$shutdown"
sleep 0.5
[[ -e $closed ]] || hyprctl eval 'require("autostart").daemons()' >/dev/null
