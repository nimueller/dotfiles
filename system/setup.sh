#!/usr/bin/env bash
# The system half of the desktop on Arch Linux: what Home Manager can't set
# up because it needs root. Every step asks first and can be repeated.
#   system/setup.sh
# 1. the session packages (packages/session.txt), together with a full
#    system upgrade: Arch doesn't support updating only some packages; then,
#    for a new machine, this machine's other packages (apps.txt, aur.txt)
# 2. PAM: unlock the `login` keyring with the login password on TTY logins
#    and at the lock screen, and keep its password in step with `passwd`;
#    the lock screen counts its failed tries on its own and then waits only
#    a minute (pam-hyprlock)
# 3. login: LightDM logs in by itself and the session locks right away
#    (config/hypr/autostart.lua), so a Wake-on-LAN boot reaches Sunshine
# 4. logind: the power button opens the power menu instead of shutting down
# 5. firewall: the network connection in firewalld's `home` zone, which
#    lets in only SSH, Samba, KDE Connect, Sunshine, mDNS and DHCPv6
# 6. Docker: container ports published on this machine only, by default
# 7. Bluetooth: bluetoothd for the Bluetooth menu, where there's an adapter,
#    and an address for controllers that come without one
# 8. power profiles: power-profiles-daemon for the battery menu, on laptops,
#    and a CPU cap in power saver where it has no CPU driver (Snapdragon)
# 9. touch screen: iptsd (touch and pen of Surfaces) for the touch screens
#    it handles at every boot, where it's installed
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
    echo "Logins on a TTY and the lock screen already unlock the keyring"
elif ask "Unlock the keyring with your password when logging in on a TTY or unlocking the lock screen (PAM)?"; then
    pam_line /etc/pam.d/login "auth       optional     pam_gnome_keyring.so"
    pam_line /etc/pam.d/login "session    optional     pam_gnome_keyring.so auto_start"
    pam_line /etc/pam.d/passwd "password   optional     pam_gnome_keyring.so"
    echo "Done. The \`login\` keyring needs your login password as its password; it then"
    echo "unlocks at the next login."
fi

echo ''
echo "== Lock screen"
# pacman keeps a changed /etc/pam.d/hyprlock (a backup file of the package)
if cmp -s "$dir/pam-hyprlock" /etc/pam.d/hyprlock; then
    echo "The lock screen already counts its failed tries on its own"
elif ask "Let the lock screen count its failed tries on its own and wait a minute after 5, instead of locking the account for 10 minutes after 3 (PAM)?"; then
    sudo install -m 644 "$dir/pam-hyprlock" /etc/pam.d/hyprlock
fi

echo ''
echo "== Login"
if ! command -v lightdm >/dev/null 2>&1; then
    echo "LightDM isn't installed (packages/apps.txt), skipping; log in on a TTY and run start-hyprland"
elif lightdm --show-config 2>&1 | grep -q 'autologin-user='; then
    echo "LightDM already logs in by itself"
elif ask "Log in by itself with LightDM? The session locks right away; its password unlocks the keyring."; then
    conf=/etc/lightdm/lightdm.conf.d/autologin.conf
    sudo mkdir -p "$(dirname "$conf")"
    printf '[Seat:*]\nautologin-user=%s\nautologin-session=hyprland\n' "$USER" | sudo tee "$conf" >/dev/null
    getent group autologin >/dev/null || sudo groupadd -r autologin
    sudo gpasswd -a "$USER" autologin >/dev/null
    sudo systemctl enable lightdm.service
    echo "Done. Takes effect after the next reboot."
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

echo ''
echo "== Bluetooth"
if [ -z "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]; then
    echo "No Bluetooth adapter, skipping"
elif systemctl is-enabled --quiet bluetooth.service 2>/dev/null; then
    echo "Bluetooth already starts at boot"
elif ask "Start Bluetooth now and at every boot (bluetooth.service, for the Bluetooth menu)?"; then
    sudo systemctl enable --now bluetooth.service
fi
# A controller without an address of its own (Qualcomm WCN399x on Snapdragon
# laptops) stays unconfigured, and BlueZ doesn't
# list it: give it one at every boot
if [ -n "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]; then
    if systemctl is-enabled --quiet bluetooth-address.service 2>/dev/null; then
        sudo install -m 755 "$dir/bluetooth-address.sh" /usr/local/lib/bluetooth-address
        echo "The Bluetooth address is already set at boot"
    elif ! sudo btmgmt info 2>/dev/null | grep -q '^hci[0-9]*:' &&
        ask "The Bluetooth controller has no address of its own, so BlueZ ignores it. Give it one from the machine id at every boot?"; then
        sudo install -m 755 "$dir/bluetooth-address.sh" /usr/local/lib/bluetooth-address
        sudo tee /etc/systemd/system/bluetooth-address.service >/dev/null <<'UNIT'
[Unit]
Description=Bluetooth address for controllers without one
After=bluetooth.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/bluetooth-address

[Install]
WantedBy=bluetooth.target
UNIT
        sudo systemctl daemon-reload
        sudo systemctl enable --now bluetooth-address.service
    fi
fi

echo ''
echo "== Power profiles"
# A battery of the machine's own; a mouse's or a headset's has the scope Device
laptop=
for d in /sys/class/power_supply/*; do
    if [ "$(cat "$d/type" 2>/dev/null)" = Battery ] && [ "$(cat "$d/scope" 2>/dev/null)" != Device ]; then
        laptop=1
    fi
done
if [ -z "$laptop" ]; then
    echo "No battery, skipping"
elif systemctl is-enabled --quiet power-profiles-daemon.service 2>/dev/null; then
    echo "power-profiles-daemon already starts at boot"
elif systemctl is-enabled --quiet tlp.service 2>/dev/null; then
    echo "TLP manages the power here, which conflicts with power-profiles-daemon; skipping"
elif ask "Power saver, balanced and performance in the battery menu: start power-profiles-daemon?"; then
    sudo systemctl enable --now power-profiles-daemon.service
fi
# Without a CPU driver of its own (only "placeholder", e.g. on Snapdragon
# laptops) power-profiles-daemon's power saver changes nothing: cap the CPU
# clusters then instead (power-saver-cpu.sh)
if systemctl is-enabled --quiet power-profiles-daemon.service 2>/dev/null; then
    if systemctl is-enabled --quiet power-saver-cpu.service 2>/dev/null; then
        sudo install -m 755 "$dir/power-saver-cpu.sh" /usr/local/lib/power-saver-cpu
        sudo systemctl restart power-saver-cpu.service
        echo "Power saver already caps the CPU"
    elif ! powerprofilesctl 2>/dev/null | grep -q CpuDriver &&
        ask "power-profiles-daemon has no CPU driver here, so power saver does nothing. Cap the CPU at about 70 % of its top speed in power saver?"; then
        sudo install -m 755 "$dir/power-saver-cpu.sh" /usr/local/lib/power-saver-cpu
        sudo tee /etc/systemd/system/power-saver-cpu.service >/dev/null <<'UNIT'
[Unit]
Description=CPU cap in power-profiles-daemon's power saver
After=power-profiles-daemon.service
Wants=power-profiles-daemon.service

[Service]
ExecStart=/usr/local/lib/power-saver-cpu
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
        sudo systemctl daemon-reload
        sudo systemctl enable --now power-saver-cpu.service
    fi
fi

echo ''
echo "== Touch screen"
# iptsd's udev rule starts it only once iptsd-check-device has accepted the
# touch screen, a request to the device right after it shows up. On the
# Surface Pro X that request now and then comes too early and fails: then
# no iptsd, no pen, and only plain touch at that boot. A rule of our own
# starts it for the touch screens that pass the check now, by their HID id,
# without asking the device.
rules=/etc/udev/rules.d/51-iptsd-known.rules
if ! command -v iptsd-check-device >/dev/null 2>&1; then
    echo "No iptsd, skipping"
else
    ids=()
    for dev in /dev/hidraw*; do
        [ -e "$dev" ] || continue
        if sudo iptsd-check-device --quiet "$dev"; then
            # the HID device above the hidraw node: bus:vendor:product.instance
            hid=$(basename "$(readlink -f "/sys/class/hidraw/${dev#/dev/}/device")")
            ids+=("${hid%.*}")
        fi
    done
    if [ ${#ids[@]} -eq 0 ]; then
        echo "No touch screen for iptsd here, skipping"
    else
        rule=$(for id in "${ids[@]}"; do
            echo "SUBSYSTEM==\"hidraw\", ACTION==\"add\", KERNELS==\"$id.*\", TAG+=\"systemd\", ENV{SYSTEMD_WANTS}+=\"iptsd@dev-%k.service\""
        done)
        if [ "$(cat "$rules" 2>/dev/null)" = "$rule" ]; then
            echo "iptsd already starts for the touch screen at every boot"
        elif ask "Start iptsd (touch and pen) for the touch screen at every boot, even when its check at boot fails?"; then
            echo "$rule" | sudo tee "$rules" >/dev/null
            sudo udevadm control --reload
        fi
    fi
fi
