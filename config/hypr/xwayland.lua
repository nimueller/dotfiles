-- X11 programs and games: the main monitor as XWayland's primary output
local function xwaylandPrimary()
    hl.exec_cmd("~/.config/quickshell/menus/xwayland-primary.py")
end

hl.on("hyprland.start", xwaylandPrimary)
hl.on("config.reloaded", xwaylandPrimary) -- Machine Settings saved
hl.on("monitor.added", xwaylandPrimary)
