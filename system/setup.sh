#!/usr/bin/env bash
# The system half of the desktop on Arch Linux: what Home Manager can't set
# up because it needs root. Every step asks first and can be repeated.
#   system/setup.sh
# 1. the session packages (packages/session.txt), together with a full
#    system upgrade: Arch doesn't support updating only some packages; then,
#    for a new machine, this machine's other packages (apps.txt, aur.txt)
# 2. PAM: unlock the `login` keyring with the login password on TTY logins,
#    and keep its password in step with `passwd`
# 3. logind: the power button opens the power menu instead of shutting down
# 4. firewall: the network connection in firewalld's `home` zone, which
#    lets in only SSH, Samba, KDE Connect, Sunshine, mDNS and DHCPv6
# 5. Docker: container ports published on this machine only, by default
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
if ask "Upgrade the system and install the session packages (${#session[@]}: Hyprland, Quickshell, portals...)?"; then
    sudo pacman -Syu --needed "${session[@]}" </dev/tty
fi
echo "The next two steps are for setting up a new machine like this one; on a machine"
echo "that already has its packages, answer n."
mapfile -t apps < <(packages apps.txt)
if ask "Install the ${#apps[@]} other packages from the repositories (packages/apps.txt)?"; then
    sudo pacman -Syu --needed "${apps[@]}" </dev/tty
fi
mapfile -t aur < <(packages aur.txt)
if command -v yay >/dev/null 2>&1; then
    if ask "Install the ${#aur[@]} AUR packages with yay (packages/aur.txt)?"; then
        yay -Syu --needed "${aur[@]}" </dev/tty
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

echo ''
echo "== Firewall"
if ! command -v firewall-cmd >/dev/null 2>&1 || ! command -v nmcli >/dev/null 2>&1; then
    echo "firewalld or NetworkManager isn't installed, skipping"
else
    # Active wired and Wi-Fi connections as "name:device" (nmcli escapes ':' in names)
    while IFS= read -r line; do
        type=${line##*:}
        rest=${line%:*}
        device=${rest##*:}
        name=${rest%:*}
        name=${name//\\:/:}
        case $type in *ethernet | *wireless) ;; *) continue ;; esac

        zone=$(nmcli -g connection.zone connection show "$name")
        if [ "$zone" = home ]; then
            echo "$name ($device) is already in the home zone"
            continue
        fi
        echo "$name ($device) is in the ${zone:-default} zone."
        if ask "Move it to the home zone (only SSH, Samba, KDE Connect, Sunshine, mDNS and DHCPv6 get in)?"; then
            if ! sudo firewall-cmd --permanent --get-services | tr ' ' '\n' | grep -qx sunshine; then
                sudo firewall-cmd --permanent --new-service=sunshine >/dev/null
                sudo firewall-cmd --permanent --service=sunshine --set-short=Sunshine >/dev/null
                for port in 47984/tcp 47989/tcp 47990/tcp 48010/tcp 47998/udp 47999/udp 48000/udp 48002/udp 48010/udp; do
                    sudo firewall-cmd --permanent --service=sunshine --add-port="$port" >/dev/null
                done
            fi
            for service in ssh samba kdeconnect sunshine mdns dhcpv6-client; do
                sudo firewall-cmd --permanent --zone=home --add-service="$service" >/dev/null
            done
            sudo firewall-cmd --reload >/dev/null
            # The connection keeps its zone; the running firewall takes it now
            sudo nmcli connection modify "$name" connection.zone home
            sudo firewall-cmd --zone=home --change-interface="$device" >/dev/null
            echo "Done. To undo:"
            echo "  sudo nmcli connection modify '$name' connection.zone '${zone:-trusted}' && sudo firewall-cmd --zone='${zone:-trusted}' --change-interface=$device"
        fi
    done < <(nmcli -t -f NAME,DEVICE,TYPE connection show --active)
fi

echo ''
echo "== Docker"
conf=/etc/docker/daemon.json
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker isn't installed, skipping"
elif [ -f "$conf" ] && grep -q '"ip"' "$conf"; then
    echo "Docker already publishes container ports at $(grep -o '"ip"[^,}]*' "$conf")"
else
    echo "Ports published by containers bypass the firewall and are open to the network."
    if ask "Publish them on this machine only (127.0.0.1) by default?"; then
        if [ -f "$conf" ]; then
            sudo cp "$conf" "$conf.bak"
            jq '. + {"ip": "127.0.0.1"}' "$conf.bak" | sudo tee "$conf" >/dev/null
        else
            sudo mkdir -p "$(dirname "$conf")"
            echo '{ "ip": "127.0.0.1" }' | sudo tee "$conf" >/dev/null
        fi
        sudo systemctl restart docker
        echo "Done; running containers keep their ports until they're recreated (docker compose up after down)."
        echo "A container that should be reachable from the network publishes with 0.0.0.0:<port>:<port>."
    fi
fi
