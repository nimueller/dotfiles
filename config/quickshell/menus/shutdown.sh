#!/usr/bin/env bash
# Reboot or shut down from the power menu (power.qml): close the apps and
# Hyprland with hyprshutdown first, which shows the apps that hold it up,
# then run the command.
#   shutdown.sh <label> <command>
# hyprshutdown ends every program of the session at once, the shell, the
# wallpaper and the idle lock too, and has no way to leave some running. On
# Cancel, start them again (autostart.lua: daemons).
label=$1 command=$2

command -v hyprshutdown >/dev/null || exec sh -c "$command"

# Only there once hyprshutdown has closed everything
closed=${XDG_RUNTIME_DIR:-/tmp}/hyprshutdown-closed
rm -f "$closed"
hyprshutdown --no-fork -t "$label" -p "touch '$closed'; $command"
sleep 0.5
[[ -e $closed ]] || hyprctl eval 'require("autostart").daemons()' >/dev/null
