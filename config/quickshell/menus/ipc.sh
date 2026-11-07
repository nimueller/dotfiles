#!/usr/bin/env bash
# Call a function of the resident daemon (daemon.qml), starting it first if
# it isn't running.
#   ipc.sh notifications toggle|dnd|clear
#   ipc.sh launcher|clipboard toggle
#   ipc.sh menus toggle <menu>         (toggle.sh <menu>)
#   ipc.sh updates refresh             (after an update, Updates.qml)
daemon=$(dirname "$(readlink -f "$0")")/daemon.qml
# A new daemon takes a moment before it answers: up to two seconds
start_tries=20
start_wait=0.1

# Fails while the daemon isn't running, which is what the callers check
call() {
    qs ipc -p "$daemon" call "$@" >/dev/null 2>&1
}

if call "$@"; then
    exit 0
fi

qs -p "$daemon" -n -d >/dev/null 2>&1
for _ in $(seq "$start_tries"); do
    if call "$@"; then
        exit 0
    fi
    sleep "$start_wait"
done
exit 1
