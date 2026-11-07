#!/usr/bin/env bash
# Open a menu, or close it if it's already open.
#   toggle.sh <menu>
#       audio, battery, battery-history, bluetooth, calendar, kdeconnect,
#       network, notifications, overview, power, scan, settings, system,
#       window, launcher or clipboard
#   toggle.sh daemon|overview --start|--restart
#       start a resident process (Hyprland), or restart it to apply changes
# All of them are part of the resident daemon.qml, so they open without
# starting quickshell. The menus (<menu>.qml) are only created while open
# (Menus.qml); the launcher, the clipboard history and the notification
# center stay loaded.
dir=$(dirname "$(readlink -f "$0")")
usage="usage: toggle.sh <menu> | toggle.sh daemon|overview --start|--restart"
menu=${1:?$usage}
option=${2:-}
# How long an old instance gets to end before it's killed: two seconds
stop_tries=20
stop_wait=0.1
kill_wait=0.2

fail_usage() {
    echo "$usage" >&2
    exit 1
}

# From qs: an instance's command line is just /usr/bin/quickshell. Without a
# running instance qs complains, and there's nothing to list.
instance_pids() {
    local qml=$1
    qs list -p "$qml" 2>/dev/null | awk '/Process ID:/ { print $3 }'
}

is_any_alive() {
    local pid
    for pid in "$@"; do
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# The new instance (-n) won't start while the old one is still there, and a
# stuck one mustn't block it
stop_instance() {
    local qml=$1 pids
    mapfile -t pids < <(instance_pids "$qml")
    qs kill -p "$qml" >/dev/null 2>&1
    for _ in $(seq "$stop_tries"); do
        if ! is_any_alive "${pids[@]}"; then
            return 0
        fi
        sleep "$stop_wait"
    done
    if is_any_alive "${pids[@]}"; then
        kill -9 "${pids[@]}" 2>/dev/null
        sleep "$kill_wait"
    fi
}

# The daemon and the overview are resident processes; overview.qml is one of
# its own (GPU rendering, see there)
run_resident() {
    local qml=$dir/$menu.qml
    case $option in
        --start) ;;
        --restart)
            stop_instance "$qml"
            ;;
        "")
            if [[ $menu != overview ]]; then
                fail_usage
            fi
            exec hyprctl dispatch 'hl.dsp.event("quickshell-overview")' >/dev/null
            ;;
        *)
            fail_usage
            ;;
    esac
    exec qs -p "$qml" -n -d >/dev/null 2>&1
}

case $menu in
    overview | daemon)
        run_resident
        ;;
    launcher | clipboard | notifications)
        exec "$dir/ipc.sh" "$menu" toggle
        ;;
esac

if [[ ! -f $dir/$menu.qml ]]; then
    echo "no such menu: $menu" >&2
    exit 1
fi
exec "$dir/ipc.sh" menus toggle "$menu"
