#!/usr/bin/env bash
# Keep the screen awake (no idle lock, no suspend) for another program:
#   stay-awake.sh on <name> [why]   until   stay-awake.sh off <name>
# A systemd inhibitor, which hypridle respects, so it also works without
# Quickshell; the daemon only shows it (StayAwake.qml). For Sunshine, in
# ~/.config/sunshine/sunshine.conf:
#   global_prep_cmd = [{"do":"/home/<user>/.config/quickshell/menus/stay-awake.sh on sunshine Streaming","undo":"/home/<user>/.config/quickshell/menus/stay-awake.sh off sunshine","elevated":false}]
action=$1
name=${2:?usage: stay-awake.sh on|off <name> [why]}
pidfile=${XDG_RUNTIME_DIR:-/tmp}/stay-awake-$name.pid

case $action in
    on)
        if ! kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
            # The inner shell records its pid and becomes `sleep`; ending it
            # ends systemd-inhibit and with it the inhibitor
            # shellcheck disable=SC2016 # $$ and $1 belong to the inner shell
            systemd-inhibit --what=idle:sleep --who="$name" --why="${3:-$name}" --mode=block \
                sh -c 'echo $$ >"$1"; exec sleep infinity' sh "$pidfile" >/dev/null 2>&1 &
            disown
        fi
        ;;
    off)
        kill "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null
        rm -f "$pidfile"
        ;;
    *)
        echo "usage: stay-awake.sh on|off <name> [why]" >&2
        exit 1
        ;;
esac

hyprctl dispatch "hl.dsp.event(\"quickshell-awake $name $action\")" >/dev/null 2>&1
exit 0
