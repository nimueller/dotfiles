hl.on("hyprland.start", function()
    -- The login screen: the session logs in by itself (LightDM autologin, so
    -- a Wake-on-LAN boot can be reached over Sunshine) and locks right away.
    -- The password also unlocks the keyring: /etc/pam.d/hyprlock includes
    -- login, which has pam_gnome_keyring (system/setup.sh).
    hl.exec_cmd("hyprlock")

    -- System programs
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 || notify-send 'Polkit authentication agent not found' 'Point its path in ~/.config/hypr/autostart.lua to the installed agent.'")
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("sunshine")
    hl.exec_cmd("~/.config/quickshell/menus/toggle.sh daemon --start") -- bar, launcher, notifications, OSD
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hypridle") -- lock and screens off when idle, lock before suspend (hypridle.conf)

    -- Utilities
    -- then the systemd services of the graphical session (home-manager/desktop)
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user start hyprland-session.target")

    -- User programs, once unlocked: most keep secrets in the keyring and would
    -- otherwise wait for its own password prompt (Brave doesn't load any page)
    hl.exec_cmd("after-unlock brave", { workspace = "1 silent" })
    hl.exec_cmd("after-unlock kitty", { workspace = "2 silent" })
    hl.exec_cmd("after-unlock pear-desktop")
    hl.exec_cmd("after-unlock thunderbird")
    hl.exec_cmd("after-unlock nextcloud")
end)
