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
# 10. touchpad: a drag goes on at the edge of the touchpad, on machines with one
# shellcheck disable=SC2024 # the redirects only give pacman's questions the terminal
dir=$(dirname "$(readlink -f "$0")")

home_services=(ssh samba kdeconnect sunshine mdns dhcpv6-client)
sunshine_ports=(
    47984/tcp 47989/tcp 47990/tcp 48010/tcp
    47998/udp 47999/udp 48000/udp 48002/udp 48010/udp
)
docker_ip=127.0.0.1
# Where the scripts that run as root at boot are installed
root_scripts=/usr/local/lib
units=/etc/systemd/system
rules_dir=/etc/udev/rules.d

# ask "question" -> true for yes
ask() {
    local option
    while true; do
        echo -n "$1 [y/n] "
        read -r -n 1 option </dev/tty
        echo ''
        case "$option" in
            y | Y)
                return 0
                ;;
            n | N)
                return 1
                ;;
        esac
    done
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

# Whether a unit starts at boot; one that isn't installed doesn't, and
# systemctl says so on stderr
is_enabled() {
    systemctl is-enabled --quiet "$1" 2>/dev/null
}

# A file's content, or nothing if it doesn't exist
read_file() {
    if [ -f "$1" ]; then
        cat "$1"
    fi
}

# The packages of a list in packages/, without comments and empty lines
packages() {
    grep -v -E '^\s*(#|$)' "$dir/packages/$1"
}

# A line in a PAM file, appended once
pam_line() {
    local file=$1 line=$2
    if grep -qF "$line" "$file"; then
        return 0
    fi
    echo "$line" | sudo tee -a "$file" >/dev/null
}

# install_root_script <file in system/> <name>: installs or updates one of the
# scripts the units below run
install_root_script() {
    sudo install -m 755 "$dir/$1" "$root_scripts/$2"
}

# install_unit <name> < unit file
install_unit() {
    sudo tee "$units/$1" >/dev/null
}

# A config file of root's, with the directory it lives in
write_root_file() {
    local file=$1
    sudo mkdir -p "$(dirname "$file")"
    sudo tee "$file" >/dev/null
}

install_session_packages() {
    local session
    mapfile -t session < <(packages session.txt)
    local question="Upgrade the system and install the session packages"
    question+=" (${#session[@]}: Hyprland, Quickshell, portals...)?"
    if ask "$question"; then
        sudo pacman -Syu --needed "${session[@]}" </dev/tty
    fi
}

install_apps() {
    local apps
    mapfile -t apps < <(packages apps.txt)
    if ask "Install the ${#apps[@]} other packages from the repositories (packages/apps.txt)?"; then
        sudo pacman -Syu --needed "${apps[@]}" </dev/tty
    fi
}

install_aur_packages() {
    local aur
    mapfile -t aur < <(packages aur.txt)
    if ! has_command yay; then
        echo "yay isn't installed, skipping the ${#aur[@]} AUR packages (packages/aur.txt)"
        return
    fi
    if ask "Install the ${#aur[@]} AUR packages with yay (packages/aur.txt)?"; then
        yay -Syu --needed "${aur[@]}" </dev/tty
    fi
}

setup_packages() {
    echo "== Packages"
    install_session_packages
    echo "The next two steps are for setting up a new machine like this one; on a machine"
    echo "that already has its packages, answer n."
    install_apps
    install_aur_packages
}

setup_keyring() {
    echo "== Keyring"
    if grep -q pam_gnome_keyring /etc/pam.d/login; then
        echo "Logins on a TTY and the lock screen already unlock the keyring"
        return
    fi
    local question="Unlock the keyring with your password when logging in on a TTY"
    question+=" or unlocking the lock screen (PAM)?"
    if ! ask "$question"; then
        return
    fi
    pam_line /etc/pam.d/login "auth       optional     pam_gnome_keyring.so"
    pam_line /etc/pam.d/login "session    optional     pam_gnome_keyring.so auto_start"
    pam_line /etc/pam.d/passwd "password   optional     pam_gnome_keyring.so"
    echo "Done. The \`login\` keyring needs your login password as its password; it then"
    echo "unlocks at the next login."
}

# pacman keeps a changed /etc/pam.d/hyprlock (a backup file of the package)
setup_lock_screen() {
    echo "== Lock screen"
    local pam=/etc/pam.d/hyprlock
    if cmp -s "$dir/pam-hyprlock" "$pam"; then
        echo "The lock screen already counts its failed tries on its own"
        return
    fi
    local question="Let the lock screen count its failed tries on its own and wait a minute after 5,"
    question+=" instead of locking the account for 10 minutes after 3 (PAM)?"
    if ask "$question"; then
        sudo install -m 644 "$dir/pam-hyprlock" "$pam"
    fi
}

setup_login() {
    echo "== Login"
    if ! has_command lightdm; then
        echo "LightDM isn't installed (packages/apps.txt), skipping;"
        echo "log in on a TTY and run start-hyprland"
        return
    fi
    if lightdm --show-config 2>&1 | grep -q 'autologin-user='; then
        echo "LightDM already logs in by itself"
        return
    fi
    local question="Log in by itself with LightDM?"
    question+=" The session locks right away; its password unlocks the keyring."
    if ! ask "$question"; then
        return
    fi
    printf '[Seat:*]\nautologin-user=%s\nautologin-session=hyprland\n' "$USER" |
        write_root_file /etc/lightdm/lightdm.conf.d/autologin.conf
    if ! getent group autologin >/dev/null; then
        sudo groupadd -r autologin
    fi
    sudo gpasswd -a "$USER" autologin >/dev/null
    sudo systemctl enable lightdm.service
    echo "Done. Takes effect after the next reboot."
}

setup_power_button() {
    echo "== Power button"
    local conf=/etc/systemd/logind.conf.d/power-key.conf
    if [ -f "$conf" ]; then
        echo "The power button already opens the power menu"
        return
    fi
    if ask "Let the power button open the power menu instead of shutting down?"; then
        printf '[Login]\nHandlePowerKey=ignore\n' | write_root_file "$conf"
        echo "Takes effect after the next reboot."
    fi
}

add_sunshine_service() {
    local services port
    services=$(sudo firewall-cmd --permanent --get-services)
    if tr ' ' '\n' <<<"$services" | grep -qx sunshine; then
        return
    fi
    sudo firewall-cmd --permanent --new-service=sunshine >/dev/null
    sudo firewall-cmd --permanent --service=sunshine --set-short=Sunshine >/dev/null
    for port in "${sunshine_ports[@]}"; do
        sudo firewall-cmd --permanent --service=sunshine --add-port="$port" >/dev/null
    done
}

# move_to_home_zone <connection> <device> <zone it was in>
move_to_home_zone() {
    local name=$1 device=$2 previous=${3:-trusted} service
    add_sunshine_service
    for service in "${home_services[@]}"; do
        sudo firewall-cmd --permanent --zone=home --add-service="$service" >/dev/null
    done
    sudo firewall-cmd --reload >/dev/null
    # The connection keeps its zone; the running firewall takes it now
    sudo nmcli connection modify "$name" connection.zone home
    sudo firewall-cmd --zone=home --change-interface="$device" >/dev/null
    echo "Done. To undo:"
    echo "  sudo nmcli connection modify '$name' connection.zone '$previous' &&"
    echo "    sudo firewall-cmd --zone='$previous' --change-interface=$device"
}

# An active connection as "name:device:type" (nmcli escapes ':' in names):
# wired and Wi-Fi ones go into the home zone
setup_connection_zone() {
    local line=$1 type rest device name zone
    type=${line##*:}
    rest=${line%:*}
    device=${rest##*:}
    name=${rest%:*}
    name=${name//\\:/:}
    case $type in
        *ethernet | *wireless) ;;
        *)
            return
            ;;
    esac

    zone=$(nmcli -g connection.zone connection show "$name")
    if [ "$zone" = home ]; then
        echo "$name ($device) is already in the home zone"
        return
    fi
    echo "$name ($device) is in the ${zone:-default} zone."
    if ask "Move it to the home zone (only SSH, Samba, KDE Connect, Sunshine, mDNS and DHCPv6 get in)?"; then
        move_to_home_zone "$name" "$device" "$zone"
    fi
}

setup_firewall() {
    echo "== Firewall"
    if ! has_command firewall-cmd || ! has_command nmcli; then
        echo "firewalld or NetworkManager isn't installed, skipping"
        return
    fi
    local line
    while IFS= read -r line; do
        setup_connection_zone "$line"
    done < <(nmcli -t -f NAME,DEVICE,TYPE connection show --active)
}

setup_docker() {
    echo "== Docker"
    local conf=/etc/docker/daemon.json
    if ! has_command docker; then
        echo "Docker isn't installed, skipping"
        return
    fi
    if [ -f "$conf" ] && grep -q '"ip"' "$conf"; then
        echo "Docker already publishes container ports at $(grep -o '"ip"[^,}]*' "$conf")"
        return
    fi
    echo "Ports published by containers bypass the firewall and are open to the network."
    if ! ask "Publish them on this machine only ($docker_ip) by default?"; then
        return
    fi
    if [ -f "$conf" ]; then
        sudo cp "$conf" "$conf.bak"
        jq --arg ip "$docker_ip" '. + {"ip": $ip}' "$conf.bak" | sudo tee "$conf" >/dev/null
    else
        echo "{ \"ip\": \"$docker_ip\" }" | write_root_file "$conf"
    fi
    sudo systemctl restart docker
    echo "Done; running containers keep their ports until they're recreated (docker compose up after down)."
    echo "A container that should be reachable from the network publishes with 0.0.0.0:<port>:<port>."
}

has_bluetooth_adapter() {
    compgen -G '/sys/class/bluetooth/*' >/dev/null
}

enable_bluetooth() {
    if is_enabled bluetooth.service; then
        echo "Bluetooth already starts at boot"
        return
    fi
    if ask "Start Bluetooth now and at every boot (bluetooth.service, for the Bluetooth menu)?"; then
        sudo systemctl enable --now bluetooth.service
    fi
}

# Whether BlueZ lists a controller, which it doesn't for one without an address
has_listed_controller() {
    sudo btmgmt info 2>/dev/null | grep -q '^hci[0-9]*:'
}

# A controller without an address of its own (Qualcomm WCN399x on Snapdragon
# laptops) stays unconfigured, and BlueZ doesn't list it: give it one at
# every boot
setup_bluetooth_address() {
    if is_enabled bluetooth-address.service; then
        install_root_script bluetooth-address.sh bluetooth-address
        echo "The Bluetooth address is already set at boot"
        return
    fi
    if has_listed_controller; then
        return
    fi
    local question="The Bluetooth controller has no address of its own, so BlueZ ignores it."
    question+=" Give it one from the machine id at every boot?"
    if ! ask "$question"; then
        return
    fi
    install_root_script bluetooth-address.sh bluetooth-address
    install_unit bluetooth-address.service <<UNIT
[Unit]
Description=Bluetooth address for controllers without one
After=bluetooth.service

[Service]
Type=oneshot
ExecStart=$root_scripts/bluetooth-address

[Install]
WantedBy=bluetooth.target
UNIT
    sudo systemctl daemon-reload
    sudo systemctl enable --now bluetooth-address.service
}

setup_bluetooth() {
    echo "== Bluetooth"
    if ! has_bluetooth_adapter; then
        echo "No Bluetooth adapter, skipping"
        return
    fi
    enable_bluetooth
    setup_bluetooth_address
}

# A battery of the machine's own; a mouse's or a headset's has the scope Device
has_own_battery() {
    local supply type scope
    for supply in /sys/class/power_supply/*; do
        type=$(read_file "$supply/type")
        scope=$(read_file "$supply/scope")
        if [ "$type" = Battery ] && [ "$scope" != Device ]; then
            return 0
        fi
    done
    return 1
}

enable_power_profiles() {
    if is_enabled power-profiles-daemon.service; then
        echo "power-profiles-daemon already starts at boot"
        return
    fi
    if is_enabled tlp.service; then
        echo "TLP manages the power here, which conflicts with power-profiles-daemon; skipping"
        return
    fi
    if ask "Power saver, balanced and performance in the battery menu: start power-profiles-daemon?"; then
        sudo systemctl enable --now power-profiles-daemon.service
    fi
}

has_cpu_driver() {
    powerprofilesctl 2>/dev/null | grep -q CpuDriver
}

# Without a CPU driver of its own (only "placeholder", e.g. on Snapdragon
# laptops) power-profiles-daemon's power saver changes nothing: cap the CPU
# clusters then instead (power-saver-cpu.sh)
setup_cpu_cap() {
    if is_enabled power-saver-cpu.service; then
        install_root_script power-saver-cpu.sh power-saver-cpu
        sudo systemctl restart power-saver-cpu.service
        echo "Power saver already caps the CPU"
        return
    fi
    if has_cpu_driver; then
        return
    fi
    local question="power-profiles-daemon has no CPU driver here, so power saver does nothing."
    question+=" Cap the CPU at about 70 % of its top speed in power saver?"
    if ! ask "$question"; then
        return
    fi
    install_root_script power-saver-cpu.sh power-saver-cpu
    install_unit power-saver-cpu.service <<UNIT
[Unit]
Description=CPU cap in power-profiles-daemon's power saver
After=power-profiles-daemon.service
Wants=power-profiles-daemon.service

[Service]
ExecStart=$root_scripts/power-saver-cpu
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
    sudo systemctl daemon-reload
    sudo systemctl enable --now power-saver-cpu.service
}

setup_power_profiles() {
    echo "== Power profiles"
    if has_own_battery; then
        enable_power_profiles
    else
        echo "No battery, skipping"
    fi
    if is_enabled power-profiles-daemon.service; then
        setup_cpu_cap
    fi
}

# The HID ids (bus:vendor:product) of the touch screens iptsd handles
iptsd_touch_screens() {
    local dev hid
    for dev in /dev/hidraw*; do
        if [ -e "$dev" ] && sudo iptsd-check-device --quiet "$dev"; then
            # the HID device above the hidraw node: bus:vendor:product.instance
            hid=$(basename "$(readlink -f "/sys/class/hidraw/${dev#/dev/}/device")")
            echo "${hid%.*}"
        fi
    done
}

# iptsd_rules <id>...: a udev rule per touch screen that starts iptsd for it
iptsd_rules() {
    local id
    for id in "$@"; do
        printf 'SUBSYSTEM=="hidraw", ACTION=="add", KERNELS=="%s.*", ' "$id"
        printf 'TAG+="systemd", ENV{SYSTEMD_WANTS}+="iptsd@dev-%%k.service"\n'
    done
}

# iptsd's udev rule starts it only once iptsd-check-device has accepted the
# touch screen, a request to the device right after it shows up. On the
# Surface Pro X that request now and then comes too early and fails: then
# no iptsd, no pen, and only plain touch at that boot. A rule of our own
# starts it for the touch screens that pass the check now, by their HID id,
# without asking the device.
setup_touch_screen() {
    echo "== Touch screen"
    local rules=$rules_dir/51-iptsd-known.rules ids rule
    if ! has_command iptsd-check-device; then
        echo "No iptsd, skipping"
        return
    fi
    mapfile -t ids < <(iptsd_touch_screens)
    if [ ${#ids[@]} -eq 0 ]; then
        echo "No touch screen for iptsd here, skipping"
        return
    fi
    rule=$(iptsd_rules "${ids[@]}")
    if [ "$(read_file "$rules")" = "$rule" ]; then
        echo "iptsd already starts for the touch screen at every boot"
        return
    fi
    local question="Start iptsd (touch and pen) for the touch screen at every boot,"
    question+=" even when its check at boot fails?"
    if ask "$question"; then
        echo "$rule" | sudo tee "$rules" >/dev/null
        sudo udevadm control --reload
    fi
}

# The input devices that are touchpads, as event<n>; udevadm complains about
# a device that went away meanwhile
touchpads() {
    local dev
    for dev in /dev/input/event*; do
        if udevadm info --query=property "$dev" 2>/dev/null | grep -q '^ID_INPUT_TOUCHPAD=1$'; then
            echo "${dev#/dev/input/}"
        fi
    done
}

# install_touchpad_edge_motion <rules file> <touchpad>...
install_touchpad_edge_motion() {
    local rules=$1 event
    shift
    install_root_script touchpad-edge-motion.py touchpad-edge-motion
    install_unit touchpad-edge-motion@.service <<UNIT
[Unit]
Description=Drag at the edge of touchpad %i
BindsTo=dev-input-%i.device
After=dev-input-%i.device

[Service]
ExecStart=$root_scripts/touchpad-edge-motion /dev/input/%i
NoNewPrivileges=yes
PrivateNetwork=yes
ProtectHome=yes
ProtectSystem=strict
UNIT
    {
        printf 'SUBSYSTEM=="input", KERNEL=="event*", ACTION!="remove", ENV{ID_INPUT_TOUCHPAD}=="1", '
        printf 'TAG+="systemd", ENV{SYSTEMD_WANTS}+="touchpad-edge-motion@%%k.service"\n'
    } | sudo tee "$rules" >/dev/null
    sudo udevadm control --reload
    sudo systemctl daemon-reload
    # The rule is for touchpads to come; those here already need another look
    # from udev, which starts the service. A change, as an add would make
    # libinput see them twice.
    for event in "$@"; do
        sudo udevadm trigger --action=change "/dev/input/$event"
    done
}

# libinput stops a drag where the finger runs out of touchpad, Windows goes on
# in that direction (touchpad-edge-motion.py). Python, as the session packages
# are installed by now and a shell can't read input events.
setup_touchpad() {
    echo "== Touchpad"
    local rules=$rules_dir/90-touchpad-edge-motion.rules found
    mapfile -t found < <(touchpads)
    if [ ${#found[@]} -eq 0 ]; then
        echo "No touchpad, skipping"
        return
    fi
    if [ -e "$rules" ]; then
        install_root_script touchpad-edge-motion.py touchpad-edge-motion
        sudo systemctl restart "touchpad-edge-motion@*.service"
        echo "A drag already goes on at the edge of the touchpad"
        return
    fi
    if ask "Keep a drag going when the finger reaches the edge of the touchpad?"; then
        install_touchpad_edge_motion "$rules" "${found[@]}"
    fi
}

main() {
    if ! has_command pacman; then
        echo "Not on Arch Linux. Install the equivalents of packages/session.txt yourself."
        exit 1
    fi
    setup_packages
    local step
    for step in \
        setup_keyring \
        setup_lock_screen \
        setup_login \
        setup_power_button \
        setup_firewall \
        setup_docker \
        setup_bluetooth \
        setup_power_profiles \
        setup_touch_screen \
        setup_touchpad; do
        echo ''
        "$step"
    done
}

main
