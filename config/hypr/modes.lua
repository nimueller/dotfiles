-- Laptop and touch mode: extra settings for machines that have a lid or a
-- battery of their own, or a touch screen. Each turns itself on when the
-- hardware is there; Machine Settings can force either on or off (local.lua
-- calls modes.set). hyprland.lua applies them after local.lua, and the shell
-- reads what's in effect from $XDG_RUNTIME_DIR/dotfiles-modes.json
-- (quickshell/menus/Modes.qml).
--
-- Laptop: tap to click, three-finger swipes between workspaces, keyboard
--   backlight keys, and with the lid closed while another monitor is
--   connected, the built-in screen goes off (logind doesn't suspend then).
--   The idle dimming and suspend on battery are in hypridle.conf.
-- Touch: swipe from the screen's edge between workspaces, no cursor while
--   touching, and the on-screen keyboard (squeekboard), which shows when a
--   text field is focused and from the bar's keyboard button. On convertibles
--   with a tablet mode switch (e.g. a keyboard cover folded back or
--   detached) it shows by itself only in tablet mode; the button always works.
--   Where the hyprgrass plugin is installed (touch screen gestures; not in
--   the Arch repos, built by hand), three-finger swipes switch workspaces
--   as on the touchpad.
local M = { forced = {}, laptop = false, touch = false, detected = {}, touchpadOptions = {} }

-- Forced modes, from local.lua: { laptop = true|false, touch = true|false };
-- a mode that isn't named is detected
function M.set(modes)
    for name, on in pairs(modes) do
        M.forced[name] = on
    end
end

-- Touchpad options from local.lua (Machine Settings), e.g.
-- { clickfinger_behavior = false }: applied after the modes, so they win
-- over laptop mode's and general.lua's, with or without laptop mode
function M.touchpad(options)
    for name, value in pairs(options) do
        M.touchpadOptions[name] = value
    end
end

local function read(path)
    local f = io.open(path)
    if not f then return nil end
    local text = f:read("a")
    f:close()
    return text
end

local function exists(path)
    local f = io.open(path)
    if f then f:close() end
    return f ~= nil
end

local function shell(cmd)
    local p = io.popen(cmd)
    if not p then return "" end
    local out = p:read("a") or ""
    p:close()
    return out
end

-- Bit n of a bitmap in /proc/bus/input/devices: hex words, the last one
-- holds bits 0-63
local function bit(map, n)
    if not map then return false end
    local words = {}
    for w in map:gmatch("%x+") do words[#words + 1] = w end
    local word = tonumber(words[#words - n // 64] or "0", 16) or 0
    return (word >> (n % 64)) & 1 == 1
end

local INPUT_PROP_DIRECT = 1
local SW_LID = 0
local SW_TABLET_MODE = 1
local ABS_MT_POSITION_X = 0x35

-- The kernel's input devices. Virtual ones (Sunshine's mouse and touch
-- screen for a streaming client, ydotool) don't count.
local function hardware()
    local found = { laptop = false, touch = false }
    for block in ((read("/proc/bus/input/devices") or "") .. "\n"):gmatch("(.-)\n\n") do
        if not (block:match("S: Sysfs=(%S+)") or ""):find("/virtual/") then
            if bit(block:match("B: SW=([%x ]+)"), SW_LID) then
                found.laptop = true
                M.lid = block:match('N: Name="(.-)"\n')
            end
            if bit(block:match("B: SW=([%x ]+)"), SW_TABLET_MODE) then
                M.tabletSwitch = block:match('N: Name="(.-)"\n')
            end
            if bit(block:match("B: PROP=([%x ]+)"), INPUT_PROP_DIRECT) and bit(block:match("B: ABS=([%x ]+)"), ABS_MT_POSITION_X) then
                found.touch = true
            end
        end
    end
    -- A battery of the machine's own; a mouse's or a headset's has the scope Device
    if shell([[for d in /sys/class/power_supply/*; do [ "$(cat "$d/type" 2>/dev/null)" = Battery ] && [ "$(cat "$d/scope" 2>/dev/null)" != Device ] && echo y; done]]):find("y") then
        found.laptop = true
    end
    return found
end

-- The laptop's own screen: eDP, or LVDS and DSI on older and ARM machines
local function builtIn(monitor)
    return monitor.name:match("^eDP") or monitor.name:match("^LVDS") or monitor.name:match("^DSI")
end

local function lidClosed()
    return shell("cat /proc/acpi/button/lid/*/state 2>/dev/null"):find("closed") ~= nil
end

-- Lid closed and another monitor connected: the built-in screen goes off.
-- A rule for the screen by its description, after (and so over) its rule
-- in local.lua; opening the lid reloads the config, which brings it back.
local function dock(closed)
    if not (closed or lidClosed()) then return end
    local monitors = hl.get_monitors()
    local other = false
    for _, m in ipairs(monitors) do
        if not builtIn(m) then other = true end
    end
    if not other then return end
    for _, m in ipairs(monitors) do
        if builtIn(m) then hl.monitor({ output = "desc:" .. m.description, disabled = true }) end
    end
end

local function laptop()
    hl.config({
        input = {
            touchpad = {
                tap_to_click         = true,
                disable_while_typing = true,
                clickfinger_behavior = true, -- two fingers right-click, three middle-click
            },
        },
    })
    hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

    local kbd = "brightnessctl -q -d '*::kbd_backlight' set "
    hl.bind("XF86KbdBrightnessUp",   hl.dsp.exec_cmd(kbd .. "33%+"), { locked = true })
    hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd(kbd .. "33%-"), { locked = true })

    if M.lid then
        hl.bind("switch:on:" .. M.lid,  function() dock(true) end,                 { locked = true })
        hl.bind("switch:off:" .. M.lid, hl.dsp.exec_cmd("hyprctl reload"),         { locked = true })
        hl.on("monitor.added", function() dock(false) end)
        dock(false) -- a reload while docked
    end
end

local HYPRGRASS = "/usr/lib/hyprgrass/libhyprgrass.so"

local function touch()
    hl.config({
        gestures = {
            workspace_swipe_touch = true,
        },
        cursor = {
            hide_on_touch = true,
        },
    })

    -- Hyprland loads the plugin after reading the config, then reads it
    -- again; its functions are there from the second time on. A plugin built
    -- for another Hyprland version doesn't load (with a notification).
    if exists(HYPRGRASS) then
        hl.plugin.load(HYPRGRASS)
        if hl.plugin.hyprgrass then
            -- Higher is more sensitive, but a finger that touches down after the
            -- others moved 100/sensitivity px cancels the gesture: at 4.0 the
            -- third finger often comes too late, below 3.0 swipes start late
            hl.config({ plugin = { hyprgrass = { sensitivity = 3.0 } } })
            hl.plugin.hyprgrass.gesture({
                pattern = { kind = "swipe", fingers = 3, direction = "horizontal" },
                action  = "workspace",
                -- the whole screen's width is one workspace otherwise, and
                -- a swipe of less than half of it snaps back
                scale   = 1.6,
            })
        end
    end

    hl.on("hyprland.start", function()
        hl.exec_cmd("squeekboard")
    end)

    -- Text fields bring up the keyboard when this setting is on (squeekboard
    -- follows it; the bar's button calls SetVisible and works either way).
    -- Set only here, not by home-manager, which would turn it on again with
    -- every switch. Without a tablet mode switch it's always on. With one,
    -- only in tablet mode: it starts off, with the keyboard attached;
    -- libinput reports a switch that's already on when Hyprland starts,
    -- which turns it on.
    local auto = "gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled "
    if M.tabletSwitch then
        local hide = "busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b false"
        hl.bind("switch:on:" .. M.tabletSwitch,  hl.dsp.exec_cmd(auto .. "true"),                    { locked = true })
        hl.bind("switch:off:" .. M.tabletSwitch, hl.dsp.exec_cmd(auto .. "false; " .. hide), { locked = true })
    end
    hl.on("hyprland.start", function()
        hl.exec_cmd(auto .. (M.tabletSwitch and "false" or "true"))
    end)
end

local function json(on)
    return on and "true" or "false"
end

function M.apply()
    M.detected = hardware()
    for _, name in ipairs({ "laptop", "touch" }) do
        local forced = M.forced[name]
        if forced == nil then M[name] = M.detected[name] else M[name] = forced end
    end
    M.forced = {}

    if M.laptop then laptop() end
    if M.touch then touch() end
    if next(M.touchpadOptions) then
        hl.config({ input = { touchpad = M.touchpadOptions } })
    end
    M.touchpadOptions = {}

    local runtime = os.getenv("XDG_RUNTIME_DIR")
    local f = runtime and io.open(runtime .. "/dotfiles-modes.json", "w")
    if f then
        f:write(string.format('{"laptop":%s,"touch":%s,"detected":{"laptop":%s,"touch":%s}}\n',
            json(M.laptop), json(M.touch), json(M.detected.laptop), json(M.detected.touch)))
        f:close()
    end
end

return M
