hl.on("hyprland.start", function()
    -- System programs
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 || notify-send 'Authentication Agent not found.' 'You have to manually adjust the path to point to the right authentication agent installable. Adjust ~/.config/hypr/autostart.lua'")
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("sunshine")
    hl.exec_cmd("waybar")
    hl.exec_cmd("swayosd-server")
    hl.exec_cmd("~/.config/quickshell/menus/toggle.sh launcher --start") -- resident so SUPER+D opens instantly
    hl.exec_cmd("hyprpaper")

    -- Utilities
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

    -- User programs
    hl.exec_cmd("zen-browser", { workspace = "1 silent" })
    hl.exec_cmd("kitty", { workspace = "2 silent" })
    hl.exec_cmd("pear-desktop")
    hl.exec_cmd("thunderbird")
    hl.exec_cmd("nextcloud")
    hl.exec_cmd("secret-tool lookup keepass password | keepassxc --pw-stdin --keyfile /home/nico/.ssh/Database.key /home/nico/Nextcloud/Database.kdbx")
end)
