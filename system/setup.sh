#!/usr/bin/env bash
# The system half of the desktop on Arch Linux: what Home Manager can't set
# up because it needs root. Every step asks first and can be repeated.
#   system/setup.sh
# 1. the session packages (packages/session.txt), then optionally this
#    machine's other packages (packages/apps.txt, packages/aur.txt)
# 2. PAM: unlock the `login` keyring with the login password on TTY logins,
#    and keep its password in step with `passwd`
# 3. logind: the power button opens the power menu instead of shutting down
# shellcheck disable=SC2024 # the redirects only give pacman's questions the terminal
dir=$(dirname "$(readlink -f "$0")")

ask() {
    local option
    while true; do
        echo -n "$1 [y/n] "
        read -r -n 1 option </dev/tty
        echo ''
        case "$option" in
            y | Y) return 0 ;;
            n | N) return 1 ;;
        esac
    done
}

packages() {
    grep -v -E '^\s*(#|$)' "$dir/packages/$1"
}

# A line in a PAM file, appended once
pam_line() {
    local file=$1 line=$2
    grep -qF "$line" "$file" || echo "$line" | sudo tee -a "$file" >/dev/null
}

if ! command -v pacman >/dev/null 2>&1; then
    echo "Not on Arch Linux. Install the equivalents of packages/session.txt yourself."
    exit 1
fi

echo "== Packages"
mapfile -t session < <(packages session.txt)
if ask "Install the session packages (${#session[@]}: Hyprland, Quickshell, portals, PipeWire...)?"; then
    sudo pacman -S --needed "${session[@]}" </dev/tty
fi
mapfile -t apps < <(packages apps.txt)
if ask "Install this machine's other ${#apps[@]} packages from the repositories?"; then
    sudo pacman -S --needed "${apps[@]}" </dev/tty
fi
mapfile -t aur < <(packages aur.txt)
if command -v yay >/dev/null 2>&1; then
    if ask "Install the ${#aur[@]} AUR packages with yay?"; then
        yay -S --needed "${aur[@]}" </dev/tty
    fi
else
    echo "yay isn't installed, skipping the ${#aur[@]} AUR packages (packages/aur.txt)"
fi

echo ''
echo "== Keyring"
if grep -q pam_gnome_keyring /etc/pam.d/login; then
    echo "TTY logins already unlock the keyring"
elif ask "Unlock the keyring with your password when logging in on a TTY (PAM)?"; then
    pam_line /etc/pam.d/login "auth       optional     pam_gnome_keyring.so"
    pam_line /etc/pam.d/login "session    optional     pam_gnome_keyring.so auto_start"
    pam_line /etc/pam.d/passwd "password   optional     pam_gnome_keyring.so"
    echo "Done. The \`login\` keyring needs your login password as its password; it then"
    echo "unlocks at the next login (system/merge-keyrings.sh moves other keyrings into it)."
fi

echo ''
echo "== Power button"
conf=/etc/systemd/logind.conf.d/power-key.conf
if [ -f "$conf" ]; then
    echo "The power button already opens the power menu"
elif ask "Let the power button open the power menu instead of shutting down?"; then
    sudo mkdir -p "$(dirname "$conf")"
    printf '[Login]\nHandlePowerKey=ignore\n' | sudo tee "$conf" >/dev/null
    echo "Takes effect after the next reboot."
fi
