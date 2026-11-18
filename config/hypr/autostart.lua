local M = {}

local menus = "~/.config/quickshell/menus/"
local polkitAgent = "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
local polkitMissing = "notify-send 'Polkit authentication agent not found'"
    .. " 'Point its path in ~/.config/hypr/autostart.lua to the installed agent.'"
-- The systemd services of the graphical session (home-manager/desktop) need
-- the session's environment first
local sessionEnvironment = "WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE"
local startSession = "dbus-update-activation-environment --systemd "
    .. sessionEnvironment
    .. " && systemctl --user start hyprland-session.target"

-- Start `command` unless the command line of a process of ours starts with
-- `program` (pgrep -f). Anchored, as the check's own shell has `command` in
-- its command line, too, but starts with `sh -c`.
local function daemon(program, command)
    hl.exec_cmd(string.format("pgrep -u \"$USER\" -f '^%s' >/dev/null || %s", program, command))
end

-- System programs. Also run again after the shutdown was cancelled
-- (quickshell/menus/shutdown.py): hyprshutdown ends them right away.
function M.daemons()
    daemon(polkitAgent, polkitAgent .. " || " .. polkitMissing)
    daemon("wl-paste --watch cliphist", "wl-paste --watch cliphist store")
    daemon("sunshine", "sunshine")
    -- Bar, launcher, notifications, OSD; and SUPER + W. Only one of each.
    hl.exec_cmd(menus .. "toggle.sh daemon --start")
    hl.exec_cmd(menus .. "toggle.sh overview --start")
    daemon("hyprpaper", "hyprpaper")
    -- Lock and screens off when idle, lock before suspend (hypridle.conf)
    daemon("hypridle", "hypridle")
end

hl.on("hyprland.start", function()
    -- The login screen: the session logs in by itself (LightDM autologin, so
    -- a Wake-on-LAN boot can be reached over Sunshine) and locks right away.
    -- The password also unlocks the keyring: /etc/pam.d/hyprlock includes
    -- login, which has pam_gnome_keyring (system/setup.sh).
    hl.exec_cmd("lock-screen")

    M.daemons()
    hl.exec_cmd(startSession)

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
