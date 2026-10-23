#!/usr/bin/env bash
# Open a menu, or close it if it's already open.
#   toggle.sh audio|battery|battery-history|bluetooth|calendar|kdeconnect|network|notifications|power|launcher|clipboard
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
            # From qs: an instance's command line is just /usr/bin/quickshell
            mapfile -t pids < <(qs list -p "$dir/daemon.qml" 2>/dev/null | awk '/Process ID:/ { print $3 }')
            alive() { for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && return 0; done; return 1; }
            qs kill -p "$dir/daemon.qml" >/dev/null 2>&1
            # The new instance (-n) won't start while the old one is still
            # there, and a stuck one mustn't block it
            for _ in {1..20}; do
                alive || break
                sleep 0.1
            done
            if alive; then
                kill -9 "${pids[@]}" 2>/dev/null
                sleep 0.2
            fi
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
# (date -r, not stat -c %.3Y: that one writes a decimal comma in some locales,
# which (( )) takes for the comma operator, so the menu never opened again)
if [[ -e $stamp ]] && (($(date +%s%3N) - $(date -r "$stamp" +%s%3N) < 500)); then
    exit 0
fi

exec qs -p "$entry" -n -d >/dev/null 2>&1
