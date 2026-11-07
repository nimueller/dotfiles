# shellcheck shell=bash
# Built with writeShellApplication (pkgs/default.nix), which adds the shebang
# Keep the screen awake (no idle lock, no suspend) for another program:
#   stay-awake on <name> [why]   until   stay-awake off <name>
# A systemd inhibitor, which hypridle respects, so it also works without
# Quickshell; the daemon only shows it (StayAwake.qml). Sunshine runs it from
# its prep commands (config/sunshine/sunshine.conf).
usage="usage: stay-awake on|off <name> [why]"
action=${1:-}
name=${2:?$usage}
why=${3:-$name}
pidfile=${XDG_RUNTIME_DIR:-/tmp}/stay-awake-$name.pid

# The pid of the shell that holds the inhibitor; none while it's off
holder_pid() {
    if [ -f "$pidfile" ]; then
        cat "$pidfile"
    fi
}

is_on() {
    local pid
    pid=$(holder_pid)
    if [ -z "$pid" ]; then
        return 1
    fi
    kill -0 "$pid" 2>/dev/null
}

# The inner shell records its pid and becomes `sleep`; ending it ends
# systemd-inhibit and with it the inhibitor
turn_on() {
    if is_on; then
        return 0
    fi
    # shellcheck disable=SC2016 # $$ and $1 belong to the inner shell
    systemd-inhibit \
        --what=idle:sleep \
        --who="$name" \
        --why="$why" \
        --mode=block \
        sh -c 'echo $$ >"$1"; exec sleep infinity' sh "$pidfile" \
        >/dev/null 2>&1 &
    disown
}

turn_off() {
    if is_on; then
        kill "$(holder_pid)"
    fi
    rm -f "$pidfile"
}

# For the on-screen display only: the inhibitor works without Hyprland
tell_quickshell() {
    local event="quickshell-awake $name $action"
    if ! hyprctl dispatch "hl.dsp.event(\"$event\")" >/dev/null; then
        echo "stay-awake: Hyprland didn't take the event" >&2
    fi
}

case $action in
    on)
        turn_on
        ;;
    off)
        turn_off
        ;;
    *)
        echo "$usage" >&2
        exit 1
        ;;
esac

tell_quickshell
