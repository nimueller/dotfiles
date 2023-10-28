#!/usr/bin/env nix-shell
#!nix-shell -i bash -p jq

ACTIVE_WINDOW_CLASS=$(hyprctl activewindow -j | jq -r .class)

[ $ACTIVE_WINDOW_CLASS != "looking-glass-client" ] && ulauncher-toggle

