# shellcheck shell=bash
# Built with writeShellApplication (pkgs/default.nix), which adds the shebang
# Runs a shell command once the lock screen at login is unlocked. The session
# logs in by itself and locks right away; the lock screen's password unlocks
# the `login` keyring (PAM) before hyprlock exits, and programs that keep
# secrets there (Brave, Nextcloud, KeePassXC's autostart) start only then
# instead of waiting for a prompt.
#   after-unlock 'command'
# It watches hyprlock instead of asking the keyring whether it's unlocked:
# gnome-keyring crashes now and then on that property read (since GLib 2.90),
# and the autostarts waiting on it went down with it.
# The command replaces this script, so it keeps the PID that Hyprland's
# exec rules (workspace = ...) look for.
command=$1
# hyprlock starts together with this script: up to a second to show up
show_tries=10
show_wait=0.1
unlock_wait=0.2

is_locked() {
    pgrep -xu "$UID" hyprlock >/dev/null
}

for _ in $(seq "$show_tries"); do
    if is_locked; then
        break
    fi
    sleep "$show_wait"
done

while is_locked; do
    sleep "$unlock_wait"
done
exec sh -c "$command"
