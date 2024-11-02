#!/usr/bin/env nix-shell
#!nix-shell -i bash -p jq rofi-wayland

ACTIVE_WINDOW_CLASS=$(hyprctl activewindow -j | jq -r .class)

if [ $ACTIVE_WINDOW_CLASS != "looking-glass-client" ]; then
    rofi=$(pgrep -x rofi)

    if [ -z "$rofi" ]; then
        rofi -show combi
    else
        kill "$rofi"
    fi
fi

