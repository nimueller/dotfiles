#!/usr/bin/env bash
# Open a menu, or close it if it's already open.
#   toggle.sh audio|calendar|network|notifications|power|launcher
#   toggle.sh launcher|daemon --start     start a resident instance (Hyprland)
# Each bar menu is its own short-lived quickshell instance (<menu>.qml), so
# nothing runs while they're closed. The exceptions stay resident so they
# open instantly: the launcher, and daemon.qml (notifications, OSD) which
# holds the notification center.
dir=$(dirname "$(readlink -f "$0")")
menu=${1:?usage: toggle.sh <menu> [--start]}

case $menu in
    launcher | daemon)
        [[ $2 == --start ]] && exec qs -p "$dir/$menu.qml" -n -d >/dev/null 2>&1
        ;;
    notifications)
        exec "$dir/ipc.sh" notifications toggle
        ;;
esac

entry=$dir/$menu.qml
[[ -f $entry ]] || { echo "no such menu: $menu" >&2; exit 1; }

# The launcher only needs to be shown; if it isn't running, start it shown
if [[ $menu == launcher ]]; then
    qs ipc -p "$entry" call launcher toggle >/dev/null 2>&1 && exit 0
    QS_OPEN=1 exec qs -p "$entry" -n -d >/dev/null 2>&1
fi

qs kill -p "$entry" >/dev/null 2>&1 && exit 0

# Clicking the bar icon while the menu is open closes it through the focus
# grab first, so don't reopen if it closed a moment ago.
stamp=$XDG_RUNTIME_DIR/qs-$menu-closed
if [[ -e $stamp ]] && (($(date +%s%3N) - $(stat -c %.3Y "$stamp" | tr -d .) < 500)); then
    exit 0
fi

exec qs -p "$entry" -n -d >/dev/null 2>&1
