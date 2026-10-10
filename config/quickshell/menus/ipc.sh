#!/usr/bin/env bash
# Call a function of the resident daemon (daemon.qml), starting it first if
# it isn't running.
#   ipc.sh notifications toggle|dnd|clear
daemon=$(dirname "$(readlink -f "$0")")/daemon.qml
qs ipc -p "$daemon" call "$@" >/dev/null 2>&1 && exit 0
qs -p "$daemon" -n -d >/dev/null 2>&1
for _ in {1..20}; do
    qs ipc -p "$daemon" call "$@" >/dev/null 2>&1 && exit 0
    sleep 0.1
done
exit 1
