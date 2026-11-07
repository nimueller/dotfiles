#!/bin/sh
# Give Bluetooth controllers that come without an address of their own one,
# so that BlueZ can use them: Qualcomm's WCN399x (Snapdragon laptops) whose
# device tree has none stays "unconfigured" and bluetoothd doesn't list it.
# The address comes from the machine id, so it stays the same and paired
# devices keep knowing this machine.
# Installed by system/setup.sh as /usr/local/lib/bluetooth-address and run at
# boot by bluetooth-address.service.

# The controller shows up early but answers only once its firmware has
# loaded, which can take half a minute after boot: a try every second
tries=60
try_wait=1

# Twelve hex digits from the machine id, as an address that is unicast and
# locally administered (first byte xxxxxx10)
machine_address() {
    hash=$(printf 'bluetooth-%s' "$(cat /etc/machine-id)" | sha256sum | cut -c1-12)
    first_byte=$(echo "$hash" | cut -c1-2)
    first_byte=$(printf '%02X' $(((0x$first_byte & 0xfc) | 0x02)))
    rest=$(echo "$hash" | cut -c3-12)
    echo "$first_byte$rest" |
        tr a-f A-F |
        sed 's/../&:/g; s/:$//'
}

# configure_controller <index>: gives the controller the address if it asks
# for one; fails while it's neither configured nor asking yet. btmgmt
# complains about a controller whose firmware is still loading.
configure_controller() {
    index=$1
    if btmgmt --index "$index" config 2>/dev/null | grep -q 'missing options:.*public-address'; then
        echo "hci$index: setting the address $address"
        btmgmt --index "$index" public-addr "$address"
        return
    fi
    btmgmt info 2>/dev/null | grep -q "^hci$index:"
}

# Fails while a controller isn't ready yet
configure_controllers() {
    all_ready=true
    for hci in /sys/class/bluetooth/hci*; do
        # Without any controller the pattern stays as it is
        if [ ! -e "$hci" ]; then
            continue
        fi
        if ! configure_controller "${hci##*/hci}"; then
            all_ready=false
        fi
    done
    [ "$all_ready" = true ]
}

address=$(machine_address)
for _ in $(seq "$tries"); do
    if configure_controllers; then
        exit 0
    fi
    sleep "$try_wait"
done
echo "A Bluetooth controller didn't answer"
exit 1
