#!/usr/bin/env bash
# Open a menu, or close it if it's already open.
#   toggle.sh audio|calendar|kdeconnect|network|notifications|power|launcher|clipboard
#   toggle.sh daemon --start|--restart   start the resident daemon (Hyprland),
#                                        or restart it to apply changes
# Each bar menu is its own short-lived quickshell instance (<menu>.qml), so
# nothing runs while they're closed. The launcher, the clipboard history and
# the notification center are part of the resident daemon.qml instead, so
# they open instantly.
dir=$(dirname "$(readlink -f "$0")")
menu=${1:?usage: toggle.sh <menu> [--start]}

case $menu in
    daemon)
        if [[ $2 == --restart ]]; then
            pid=$(pgrep -f "quickshell.* -p $dir/daemon.qml" | head -1)
            qs kill -p "$dir/daemon.qml" >/dev/null 2>&1
            # Don't let a stuck instance block the new one (-n)
            for _ in {1..20}; do
                if [[ -z $pid ]] || ! kill -0 "$pid" 2>/dev/null; then break; fi
                sleep 0.1
            done
            [[ -n $pid ]] && kill -9 "$pid" 2>/dev/null
        fi
        [[ $2 == --start || $2 == --restart ]] && exec qs -p "$dir/daemon.qml" -n -d >/dev/null 2>&1
        exit 1
        ;;
    launcher | clipboard | notifications)
        exec "$dir/ipc.sh" "$menu" toggle
        ;;
esac

entry=$dir/$menu.qml
[[ -f $entry ]] || { echo "no such menu: $menu" >&2; exit 1; }

qs kill -p "$entry" >/dev/null 2>&1 && exit 0

# Clicking the bar icon while the menu is open closes it through the focus
# grab first, so don't reopen if it closed a moment ago.
stamp=$XDG_RUNTIME_DIR/qs-$menu-closed
if [[ -e $stamp ]] && (($(date +%s%3N) - $(stat -c %.3Y "$stamp" | tr -d .) < 500)); then
    exit 0
fi

exec qs -p "$entry" -n -d >/dev/null 2>&1
