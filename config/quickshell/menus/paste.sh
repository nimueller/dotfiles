#!/usr/bin/env bash
# Copies stdin, then pastes it into the window that gets the focus back once
# the picker that ran this is gone: Ctrl+V, or Ctrl+Shift+V in terminals.
# Used by the clipboard history (Clipboard.qml) and the launcher's emoji.
#   printf %s text | paste.sh
# The picker closes and gives the focus back meanwhile
focus_wait=0.15

wl-copy || exit 1
sleep "$focus_wait"

class=$(hyprctl activewindow -j | jq -r .class)
case $class in
    kitty | Alacritty | foot | footclient | org.wezfurlong.wezterm | com.mitchellh.ghostty | xterm*)
        mods="CTRL SHIFT"
        ;;
    *)
        mods="CTRL"
        ;;
esac

# Hyprland sends the shortcut (send_shortcut), which also reaches XWayland
# apps; wtype's virtual keyboard doesn't
hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"$mods\", key = \"v\" })"
