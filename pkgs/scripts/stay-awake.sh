# shellcheck shell=bash
# Built with writeShellApplication (pkgs/default.nix), which adds the shebang
# Keep the screen awake (no idle lock, no suspend) for another program:
#   stay-awake on <name> [why]   until   stay-awake off <name>
# A systemd inhibitor, which hypridle respects, so it also works without
# Quickshell; the daemon only shows it (StayAwake.qml). Sunshine runs it from
# its prep commands (config/sunshine/sunshine.conf).
action=${1:-}
name=${2:?usage: stay-awake on|off <name> [why]}
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
        kill "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null || true
        rm -f "$pidfile"
        ;;
    *)
        echo "usage: stay-awake on|off <name> [why]" >&2
        exit 1
        ;;
esac

# Tell the Quickshell daemon, for the on-screen display
hyprctl dispatch "hl.dsp.event(\"quickshell-awake $name $action\")" >/dev/null 2>&1 || true
