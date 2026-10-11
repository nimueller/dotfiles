hl.on("hyprland.start", function()
    -- System programs
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 || notify-send 'Polkit authentication agent not found' 'Point its path in ~/.config/hypr/autostart.lua to the installed agent.'")
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("sunshine")
    hl.exec_cmd("~/.config/quickshell/menus/toggle.sh daemon --start") -- bar, launcher, notifications, OSD
    hl.exec_cmd("hyprpaper")

    -- Utilities
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")

    -- User programs
    hl.exec_cmd("zen-browser", { workspace = "1 silent" })
    hl.exec_cmd("kitty", { workspace = "2 silent" })
    hl.exec_cmd("pear-desktop")
    hl.exec_cmd("thunderbird")
    hl.exec_cmd("nextcloud")
    hl.exec_cmd("secret-tool lookup keepass password | keepassxc --pw-stdin --keyfile /home/nico/.ssh/Database.key /home/nico/Nextcloud/Database.kdbx")
end)
