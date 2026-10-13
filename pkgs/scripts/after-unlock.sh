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

# hyprlock starts together with this script: up to a second to show up
tries=0
until pgrep -xu "$UID" hyprlock >/dev/null || [ "$tries" -ge 10 ]; do
    tries=$((tries + 1))
    sleep 0.1
done
while pgrep -xu "$UID" hyprlock >/dev/null; do
    sleep 0.2
done
exec sh -c "$1"
