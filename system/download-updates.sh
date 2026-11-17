#!/usr/bin/env bash
# Downloads the waiting pacman updates into pacman's cache, so the update
# itself (the bar's update chip, `upgrade`) only has to install them. Runs
# as root (download-updates.timer, from system/setup.sh).
#
# checkupdates syncs a copy of the package databases: the real ones stay as
# they are, so nothing here can lead to a partial upgrade, unlike
# pacman -Syuw. Skipped on a metered connection (a phone's hotspot).
set -u

dest=org.freedesktop.NetworkManager
path=/org/freedesktop/NetworkManager

# NetworkManager's Metered: 1 is yes, 3 a guess of yes. Without
# NetworkManager the connection counts as not metered
is_metered() {
    local reply
    reply=$(busctl --system get-property "$dest" "$path" "$dest" Metered 2>/dev/null) || return 1
    case $reply in
        "u 1" | "u 3")
            return 0
            ;;
    esac
    return 1
}

if is_metered; then
    echo "Metered connection, not downloading"
    exit 0
fi

# Lists the updates and downloads them; 2 means there are none
checkupdates --download
status=$?
if [ "$status" -eq 2 ]; then
    exit 0
fi
exit "$status"
