#!/usr/bin/env bash
# Open a menu, or close it if it's already open.
#   toggle.sh audio|network|notifications|power|launcher
# Each menu is its own short-lived quickshell instance (<menu>.qml), so
# nothing runs while the menus are closed.
menu=${1:?usage: toggle.sh <menu>}
entry=$(dirname "$(readlink -f "$0")")/$menu.qml
[[ -f $entry ]] || { echo "no such menu: $menu" >&2; exit 1; }

qs kill -p "$entry" >/dev/null 2>&1 && exit 0

# Clicking the bar icon while the menu is open closes it through the focus
# grab first, so don't reopen if it closed a moment ago.
stamp=$XDG_RUNTIME_DIR/qs-$menu-closed
if [[ -e $stamp ]] && (($(date +%s%3N) - $(stat -c %.3Y "$stamp" | tr -d .) < 500)); then
    exit 0
fi

exec qs -p "$entry" -n -d >/dev/null 2>&1
