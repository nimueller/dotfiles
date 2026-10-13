# shellcheck shell=bash
# Built with writeShellApplication (pkgs/default.nix), which adds the shebang
# Runs a shell command once the `login` keyring is unlocked. The session logs
# in by itself and locks right away; the lock screen's password unlocks the
# keyring (PAM), and programs that keep secrets there (Brave, Nextcloud,
# KeePassXC's autostart) start only then instead of waiting for a prompt.
#   after-unlock 'command'
# Without a keyring to wait for, it runs the command after 10 seconds.
# The command replaces this script, so it keeps the PID that Hyprland's
# exec rules (workspace = ...) look for.
tries=0
while true; do
    if locked=$(busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login \
        org.freedesktop.Secret.Collection Locked 2>/dev/null); then
        [ "$locked" = "b false" ] && break
    else
        tries=$((tries + 1))
        [ "$tries" -ge 10 ] && break
    fi
    sleep 1
done
exec sh -c "$1"
