ACTIVE_WINDOW_CLASS=$(hyprctl activewindow -j | jq -r .class)

if [ "$ACTIVE_WINDOW_CLASS" != "looking-glass-client" ]; then
    exec ~/.config/quickshell/menus/toggle.sh launcher
fi
