#!/usr/bin/env bash
# Show or hide the on-screen keyboard (squeekboard, started by modes.lua in
# touch mode), which otherwise only shows for a focused text field. Started
# here if it isn't running. For the bar's keyboard button and the system menu.
pidof squeekboard >/dev/null || {
    squeekboard >/dev/null 2>&1 &
    sleep 1
}
osk=(sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0)
if [[ $(busctl --user get-property "${osk[@]}" Visible) == "b true" ]]; then show=false; else show=true; fi
busctl --user call "${osk[@]}" SetVisible b "$show"
