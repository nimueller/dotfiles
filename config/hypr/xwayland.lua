-- X11 programs and games: the main monitor as XWayland's primary output
local function xwaylandPrimary()
    hl.exec_cmd("~/.config/quickshell/menus/xwayland-primary.py")
end

-- XWayland dies when a monitor comes and goes while it starts (a KVM switch at
-- login), and Hyprland doesn't start it again. xwayland-restart.py does, with
-- a reload in which this file is present.
local function isRestarting()
    local runtime = os.getenv("XDG_RUNTIME_DIR")
    if runtime == nil then
        return false
    end
    local file = io.open(runtime .. "/hypr-xwayland-off")
    if file == nil then
        return false
    end
    file:close()
    return true
end

local function xwaylandRestart()
    hl.exec_cmd("~/.config/quickshell/menus/xwayland-restart.py")
end

if isRestarting() then
    hl.config({ xwayland = { enabled = false } })
end

hl.on("hyprland.start", xwaylandPrimary)
hl.on("config.reloaded", xwaylandPrimary) -- Machine Settings saved
hl.on("monitor.added", xwaylandPrimary)

-- Not on config.reloaded: the restart reloads, and an XWayland that can't
-- start at all would make it reload again and again
hl.on("hyprland.start", xwaylandRestart)
hl.on("monitor.added", xwaylandRestart)
