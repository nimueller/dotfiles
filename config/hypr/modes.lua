-- Laptop and touch mode: extra settings for machines that have a lid or a
-- battery of their own, or a touch screen. Each turns itself on when the
-- hardware is there; Machine Settings can force either on or off (local.lua
-- calls modes.set). hyprland.lua applies them after local.lua, and the shell
-- reads what's in effect from $XDG_RUNTIME_DIR/dotfiles-modes.json
-- (quickshell/menus/Modes.qml).
--
-- Laptop: tap to click, three-finger swipes between workspaces (up and down:
--   open and close the overview, quickshell/menus/overview.qml), keyboard
--   backlight keys, and with the lid closed while another monitor is
--   connected, the built-in screen goes off (logind doesn't suspend then).
--   The idle dimming and suspend on battery are in hypridle.conf.
-- Touch: swipe from the screen's edge between workspaces, no cursor while
--   touching, and the on-screen keyboard (squeekboard), which shows when a
--   text field is focused and from the bar's keyboard button. On convertibles
--   with a tablet mode switch (e.g. a keyboard cover folded back or
--   detached) it shows by itself only in tablet mode; the button always works.
--   On the lock screen too, the same way, with a button of its own there.
--   Where the hyprgrass plugin is installed (touch screen gestures; not in
--   the Arch repos, built by hand), three-finger swipes switch workspaces
--   and open the overview as on the touchpad. Without it, the overview's
--   button on the bar does.
local M = {
    forced = {},
    laptop = false,
    touch = false,
    detected = {},
    touchpadOptions = {},
}

local INPUT_DEVICES = "/proc/bus/input/devices"
local POWER_SUPPLIES = "/sys/class/power_supply"
local LID_STATES = "/proc/acpi/button/lid/*/state"
local HYPRGRASS = "/usr/lib/hyprgrass/libhyprgrass.so"

-- Bits of the input device bitmaps (linux/input-event-codes.h)
local INPUT_PROP_DIRECT = 1
local SW_LID = 0
local SW_TABLET_MODE = 1
local ABS_MT_POSITION_X = 0x35

local ON_LOCK_SCREEN = { locked = true }
local KEYBOARD_BACKLIGHT = "brightnessctl -q -d '*::kbd_backlight' set "
local KEYBOARD_BACKLIGHT_STEP = "33%"
local SCREEN_KEYBOARD_SETTING = "gsettings set org.gnome.desktop.a11y.applications" .. " screen-keyboard-enabled "
local SCREEN_KEYBOARD = "sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0"
local HIDE_SCREEN_KEYBOARD = "busctl --user call " .. SCREEN_KEYBOARD .. " SetVisible b false"
-- Higher is more sensitive, but a finger that touches down after the others
-- moved 100/sensitivity px cancels the gesture: at 4.0 the third finger
-- often comes too late, below 3.0 swipes start late
local HYPRGRASS_SENSITIVITY = 3.0
-- The whole screen's width is one workspace otherwise, and a swipe of less
-- than half of it snaps back
local HYPRGRASS_WORKSPACE_SCALE = 1.6

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
    local file = io.open(path)
    if file == nil then
        return nil
    end
    local text = file:read("a")
    file:close()
    return text
end

local function exists(path)
    local file = io.open(path)
    if file == nil then
        return false
    end
    file:close()
    return true
end

local function shell(command)
    local process = io.popen(command)
    if process == nil then
        return ""
    end
    local output = process:read("a") or ""
    process:close()
    return output
end

-- A file in $XDG_RUNTIME_DIR, for the shell
local function writeRuntimeFile(name, text)
    local runtime = os.getenv("XDG_RUNTIME_DIR")
    if runtime == nil then
        return
    end
    local file = io.open(runtime .. "/" .. name, "w")
    if file == nil then
        return
    end
    file:write(text)
    file:close()
end

-- Bit n of a bitmap in /proc/bus/input/devices: hex words, the last one
-- holds bits 0-63
local function bit(map, n)
    if map == nil then
        return false
    end
    local words = {}
    for word in map:gmatch("%x+") do
        words[#words + 1] = word
    end
    local wordIndex = #words - n // 64
    local word = tonumber(words[wordIndex] or "0", 16) or 0
    return (word >> (n % 64)) & 1 == 1
end

-- One device block of /proc/bus/input/devices, as the fields it's checked by
local function parseDevice(block)
    return {
        name = block:match('N: Name="(.-)"\n'),
        sysfs = block:match("S: Sysfs=(%S+)") or "",
        switches = block:match("B: SW=([%x ]+)"),
        properties = block:match("B: PROP=([%x ]+)"),
        axes = block:match("B: ABS=([%x ]+)"),
    }
end

-- Virtual devices (Sunshine's mouse and touch screen for a streaming
-- client, ydotool) don't count
local function inputDevices()
    local devices = {}
    local text = (read(INPUT_DEVICES) or "") .. "\n"
    for block in text:gmatch("(.-)\n\n") do
        local device = parseDevice(block)
        if not device.sysfs:find("/virtual/") then
            devices[#devices + 1] = device
        end
    end
    return devices
end

local function isTouchScreen(device)
    local isDirect = bit(device.properties, INPUT_PROP_DIRECT)
    local hasMultitouch = bit(device.axes, ABS_MT_POSITION_X)
    return isDirect and hasMultitouch
end

-- A battery of the machine's own; a mouse's or a headset's has the scope Device
local function hasOwnBattery()
    for supply in shell("ls " .. POWER_SUPPLIES):gmatch("[^\n]+") do
        local path = POWER_SUPPLIES .. "/" .. supply
        local supplyType = read(path .. "/type") or ""
        local scope = read(path .. "/scope") or ""
        if supplyType:match("^Battery") and not scope:match("^Device") then
            return true
        end
    end
    return false
end

-- The kernel's input devices and batteries; also remembers the lid and the
-- tablet mode switch for their binds
local function hardware()
    local found = { laptop = false, touch = false }
    for _, device in ipairs(inputDevices()) do
        if bit(device.switches, SW_LID) then
            found.laptop = true
            M.lid = device.name
        end
        if bit(device.switches, SW_TABLET_MODE) then
            M.tabletSwitch = device.name
        end
        if isTouchScreen(device) then
            found.touch = true
        end
    end
    if hasOwnBattery() then
        found.laptop = true
    end
    return found
end

-- The laptop's own screen: eDP, or LVDS and DSI on older and ARM machines
local function isBuiltIn(monitor)
    local name = monitor.name
    return name:match("^eDP") or name:match("^LVDS") or name:match("^DSI")
end

local function isLidClosed()
    return shell("cat " .. LID_STATES .. " 2>/dev/null"):find("closed") ~= nil
end

local function hasOtherMonitor(monitors)
    for _, monitor in ipairs(monitors) do
        if not isBuiltIn(monitor) then
            return true
        end
    end
    return false
end

-- Lid closed and another monitor connected: the built-in screen goes off.
-- A rule for the screen by its description, after (and so over) its rule
-- in local.lua; opening the lid reloads the config, which brings it back.
local function dock(isClosed)
    if not (isClosed or isLidClosed()) then
        return
    end
    local monitors = hl.get_monitors()
    if not hasOtherMonitor(monitors) then
        return
    end
    for _, monitor in ipairs(monitors) do
        if isBuiltIn(monitor) then
            hl.monitor({ output = "desc:" .. monitor.description, disabled = true })
        end
    end
end

local function overviewOpen()
    hl.dispatch(hl.dsp.event("quickshell-overview open"))
end

local function overviewClose()
    hl.dispatch(hl.dsp.event("quickshell-overview close"))
end

local function bindKeyboardBacklight()
    local up = KEYBOARD_BACKLIGHT .. KEYBOARD_BACKLIGHT_STEP .. "+"
    local down = KEYBOARD_BACKLIGHT .. KEYBOARD_BACKLIGHT_STEP .. "-"
    hl.bind("XF86KbdBrightnessUp", hl.dsp.exec_cmd(up), ON_LOCK_SCREEN)
    hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd(down), ON_LOCK_SCREEN)
end

local function bindLid()
    hl.bind("switch:on:" .. M.lid, function()
        dock(true)
    end, ON_LOCK_SCREEN)
    hl.bind("switch:off:" .. M.lid, hl.dsp.exec_cmd("hyprctl reload"), ON_LOCK_SCREEN)
    hl.on("monitor.added", function()
        dock(false)
    end)
    -- A reload while docked
    dock(false)
end

local function laptop()
    hl.config({
        input = {
            touchpad = {
                tap_to_click = true,
                disable_while_typing = true,
                -- Two fingers right-click, three middle-click
                clickfinger_behavior = true,
            },
        },
    })
    hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
    hl.gesture({ fingers = 3, direction = "up", action = overviewOpen })
    hl.gesture({ fingers = 3, direction = "down", action = overviewClose })
    bindKeyboardBacklight()
    if M.lid then
        bindLid()
    end
end

local function boolText(value)
    return tostring(value == true)
end

-- Tablet mode (the switch, see touch()) for the shell
local function tabletMode(on)
    writeRuntimeFile("dotfiles-tablet", boolText(on) .. "\n")
end

local function screenKeyboardSetting(on)
    return SCREEN_KEYBOARD_SETTING .. boolText(on)
end

-- Hyprland loads the plugin after reading the config, then reads it again;
-- its functions are there from the second time on. A plugin built for
-- another Hyprland version doesn't load (with a notification).
local function touchGestures()
    if not exists(HYPRGRASS) then
        return
    end
    hl.plugin.load(HYPRGRASS)
    local hyprgrass = hl.plugin.hyprgrass
    if not hyprgrass then
        return
    end
    hl.config({ plugin = { hyprgrass = { sensitivity = HYPRGRASS_SENSITIVITY } } })
    hyprgrass.gesture({
        pattern = { kind = "swipe", fingers = 3, direction = "horizontal" },
        action = "workspace",
        scale = HYPRGRASS_WORKSPACE_SCALE,
    })
    -- Not tried on a touch screen yet: a plugin that wants another kind of
    -- action mustn't break the config
    pcall(hyprgrass.gesture, {
        pattern = { kind = "swipe", fingers = 3, direction = "up" },
        action = overviewOpen,
    })
    pcall(hyprgrass.gesture, {
        pattern = { kind = "swipe", fingers = 3, direction = "down" },
        action = overviewClose,
    })
end

local function bindTabletSwitch()
    hl.bind("switch:on:" .. M.tabletSwitch, function()
        tabletMode(true)
        hl.exec_cmd(screenKeyboardSetting(true))
    end, ON_LOCK_SCREEN)
    hl.bind("switch:off:" .. M.tabletSwitch, function()
        tabletMode(false)
        hl.exec_cmd(screenKeyboardSetting(false) .. "; " .. HIDE_SCREEN_KEYBOARD)
    end, ON_LOCK_SCREEN)
end

-- Text fields bring up the keyboard when this setting is on (squeekboard
-- follows it; the bar's button calls SetVisible and works either way). Set
-- only here, not by home-manager, which would turn it on again with every
-- switch. Without a tablet mode switch it's always on. With one, only in
-- tablet mode: it starts off, with the keyboard attached; libinput reports a
-- switch that's already on when Hyprland starts, which turns it on.
--
-- The shell reads the switch from $XDG_RUNTIME_DIR/dotfiles-tablet and makes
-- its menus bigger in tablet mode (quickshell/menus/Popup.qml). Like the
-- setting, it starts off and the switch turns it on.
local function screenKeyboard()
    hl.on("hyprland.start", function()
        hl.exec_cmd("squeekboard")
    end)
    -- Above the lock screen, and it takes touches there: hyprlock has a button
    -- for it (pkgs/scripts/lock-screen.sh), the keys go to the password field
    hl.layer_rule({ match = { namespace = "^osk$" }, above_lock = 2 })

    if M.tabletSwitch then
        bindTabletSwitch()
    end
    hl.on("hyprland.start", function()
        local hasTabletSwitch = M.tabletSwitch ~= nil
        if hasTabletSwitch then
            tabletMode(false)
        end
        hl.exec_cmd(screenKeyboardSetting(not hasTabletSwitch))
    end)
end

local function touch()
    hl.config({
        gestures = {
            workspace_swipe_touch = true,
        },
        cursor = {
            hide_on_touch = true,
        },
    })
    touchGestures()
    screenKeyboard()
end

local function decideModes()
    for _, name in ipairs({ "laptop", "touch" }) do
        local forced = M.forced[name]
        if forced == nil then
            M[name] = M.detected[name]
        else
            M[name] = forced
        end
    end
    M.forced = {}
end

local function writeModes()
    local json = string.format(
        '{"laptop":%s,"touch":%s,"detected":{"laptop":%s,"touch":%s}}\n',
        boolText(M.laptop),
        boolText(M.touch),
        boolText(M.detected.laptop),
        boolText(M.detected.touch)
    )
    writeRuntimeFile("dotfiles-modes.json", json)
end

function M.apply()
    M.detected = hardware()
    decideModes()

    if M.laptop then
        laptop()
    end
    if M.touch then
        touch()
    end
    if next(M.touchpadOptions) ~= nil then
        hl.config({ input = { touchpad = M.touchpadOptions } })
    end
    M.touchpadOptions = {}

    writeModes()
end

return M
