#!/usr/bin/env bash
# Show or hide the on-screen keyboard (squeekboard, started by modes.lua in
# touch mode), which otherwise only shows for a focused text field. Started
# here if it isn't running. For the bar's keyboard button and the system menu.
osk=(sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0)
# squeekboard's D-Bus interface shows up a moment after it starts
start_wait=1

if ! pidof squeekboard >/dev/null; then
    squeekboard >/dev/null 2>&1 &
    sleep "$start_wait"
fi

visible=$(busctl --user get-property "${osk[@]}" Visible)
if [[ $visible == "b true" ]]; then
    show=false
else
    show=true
fi
busctl --user call "${osk[@]}" SetVisible b "$show"
