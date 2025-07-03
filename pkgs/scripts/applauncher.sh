#!/usr/bin/env nix-shell
#!nix-shell -i bash -p jq rofi-wayland

ACTIVE_WINDOW_CLASS=$(hyprctl activewindow -j | jq -r .class)

if [ $ACTIVE_WINDOW_CLASS != "looking-glass-client" ]; then
    rofi=$(pgrep -x rofi)

    if [ -z "$rofi" ]; then
        waybar &
        rofi -show combi
        pkill waybar
    else
        kill "$rofi"
        pkill waybar
    fi
fi

