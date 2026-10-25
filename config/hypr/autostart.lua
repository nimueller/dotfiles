local M = {}

-- Start `command` unless a process of ours matches `pattern` (pgrep -f; a
-- bracket in it keeps the check's own shell from matching)
local function daemon(pattern, command)
    hl.exec_cmd(string.format("pgrep -u \"$USER\" -f '%s' >/dev/null || %s", pattern, command))
end

-- System programs. Also run again after the shutdown was cancelled
-- (quickshell/menus/shutdown.sh): hyprshutdown ends them right away.
function M.daemons()
    daemon("[p]olkit-gnome-authentication-agent-1", "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 || notify-send 'Polkit authentication agent not found' 'Point its path in ~/.config/hypr/autostart.lua to the installed agent.'")
    daemon("[w]l-paste --watch cliphist", "wl-paste --watch cliphist store")
    daemon("^[s]unshine", "sunshine")
    hl.exec_cmd("~/.config/quickshell/menus/toggle.sh daemon --start") -- bar, launcher, notifications, OSD; only one
    daemon("^[h]yprpaper", "hyprpaper")
    daemon("^[h]ypridle", "hypridle") -- lock and screens off when idle, lock before suspend (hypridle.conf)
end

hl.on("hyprland.start", function()
    -- The login screen: the session logs in by itself (LightDM autologin, so
    -- a Wake-on-LAN boot can be reached over Sunshine) and locks right away.
    -- The password also unlocks the keyring: /etc/pam.d/hyprlock includes
    -- login, which has pam_gnome_keyring (system/setup.sh).
    hl.exec_cmd("lock-screen")

    M.daemons()

    -- Utilities
    -- then the systemd services of the graphical session (home-manager/desktop)
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user start hyprland-session.target")

    -- User programs, once unlocked: most keep secrets in the keyring and would
    -- otherwise wait for its own password prompt (Brave doesn't load any page).
    -- after-unlock runs only its first argument: quote commands with arguments
    hl.exec_cmd("after-unlock 'flatpak run com.brave.Browser'", { workspace = "1 silent" })
    hl.exec_cmd("after-unlock kitty", { workspace = "2 silent" })
    hl.exec_cmd("after-unlock pear-desktop")
    hl.exec_cmd("after-unlock thunderbird")
    hl.exec_cmd("after-unlock nextcloud")
end)

return M
