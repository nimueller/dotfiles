#!/bin/sh
# Give Bluetooth controllers that come without an address of their own one,
# so that BlueZ can use them: Qualcomm's WCN399x (Surface Pro X and other
# Snapdragon laptops) whose device tree has none stays "unconfigured" and
# bluetoothd doesn't list it. The address comes from the machine id, so it
# stays the same and paired devices keep knowing this machine.
# Installed by system/setup.sh as /usr/local/lib/bluetooth-address and run at
# boot by bluetooth-address.service.

hash=$(printf 'bluetooth-%s' "$(cat /etc/machine-id)" | sha256sum | cut -c1-12)
# Unicast and locally administered (first byte xxxxxx10)
first=$(printf '%02X' $(((0x$(echo "$hash" | cut -c1-2) & 0xfc) | 0x02)))
address=$(echo "$first$(echo "$hash" | cut -c3-12)" | tr a-f A-F | sed 's/../&:/g; s/:$//')

# The controller shows up early but answers only once its firmware has
# loaded, which can take half a minute after boot
for _ in $(seq 60); do
    pending=
    for hci in /sys/class/bluetooth/hci*; do
        [ -e "$hci" ] || continue
        index=${hci##*/hci}
        if btmgmt --index "$index" config 2>/dev/null | grep -q 'missing options:.*public-address'; then
            echo "hci$index: setting the address $address"
            btmgmt --index "$index" public-addr "$address" || pending=1
        elif ! btmgmt info 2>/dev/null | grep -q "^hci$index:"; then
            pending=1 # neither configured nor asking for an address yet
        fi
    done
    [ -z "$pending" ] && exit 0
    sleep 1
done
echo "A Bluetooth controller didn't answer"
exit 1
