#!/usr/bin/env bash
# Open a menu, or close it if it's already open.
#   toggle.sh audio|battery|battery-history|bluetooth|calendar|kdeconnect|network|notifications|power|scan|settings|system|window|launcher|clipboard
#   toggle.sh daemon --start|--restart   start the resident daemon (Hyprland),
#                                        or restart it to apply changes
# All of them are part of the resident daemon.qml, so they open without
# starting quickshell. The menus (<menu>.qml) are only created while open
# (Menus.qml); the launcher, the clipboard history and the notification
# center stay loaded.
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

[[ -f $dir/$menu.qml ]] || { echo "no such menu: $menu" >&2; exit 1; }
exec "$dir/ipc.sh" menus toggle "$menu"
