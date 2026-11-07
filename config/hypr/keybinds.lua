local mainMod = "SUPER"
local resizeStep = 50
local menus = "~/.config/quickshell/menus/"
-- Prefer the chromium/Electron player, fall back to any
local playerctl = "playerctl -p chromium,%any "

-- Binds that also work on the lock screen, and ones that repeat while held
local locked = { locked = true }
local lockedRepeating = { locked = true, repeating = true }
-- Caps Lock / Num Lock still do their job
local lockedPassThrough = { locked = true, non_consuming = true }

local function exec(command, rules)
    return hl.dsp.exec_cmd(command, rules)
end

local function super(keys)
    return mainMod .. " + " .. keys
end

-- Launcher in the resident quickshell daemon (quickshell/menus/Launcher.qml)
hl.bind(super("D"), hl.dsp.event("quickshell-launcher"))

-- Brightness
hl.bind("XF86MonBrightnessUp", hl.dsp.event("quickshell-osd brightness +5"), lockedRepeating)
hl.bind("XF86MonBrightnessDown", hl.dsp.event("quickshell-osd brightness -5"), lockedRepeating)

-- Media
local mediaKeys = {
    { "XF86AudioPlay", "play-pause" },
    { "XF86AudioPause", "pause" },
    { "XF86AudioNext", "next" },
    { "XF86AudioPrev", "previous" },
    { "XF86AudioStop", "stop" },
}
for _, mediaKey in ipairs(mediaKeys) do
    local key, command = mediaKey[1], mediaKey[2]
    hl.bind(key, exec(playerctl .. command), locked)
end
hl.bind("XF86Calculator", exec("gnome-calculator"))

-- Case power button opens the power menu (logind must ignore the key, see
-- /etc/systemd/logind.conf.d/power-key.conf)
hl.bind("XF86PowerOff", exec(menus .. "toggle.sh power"))

-- Volume and brightness: the quickshell daemon changes them and shows the OSD
-- (config/quickshell/menus/Osd.qml); events, so no process starts per press
hl.bind("XF86AudioMicMute", hl.dsp.event("quickshell-osd mic-mute"), locked)
hl.bind("XF86AudioMute", hl.dsp.event("quickshell-osd mute"), locked)
hl.bind("XF86AudioRaiseVolume", hl.dsp.event("quickshell-osd volume +5"), lockedRepeating)
hl.bind("XF86AudioLowerVolume", hl.dsp.event("quickshell-osd volume -5"), lockedRepeating)

-- Caps Lock / Num Lock state in the OSD
hl.bind("Caps_Lock", hl.dsp.event("quickshell-osd lock caps"), lockedPassThrough)
hl.bind("Num_Lock", hl.dsp.event("quickshell-osd lock num"), lockedPassThrough)

-- Workspace controls (key 0 maps to workspace 10)
for workspace = 1, 10 do
    local key = workspace % 10
    hl.bind(super(key), hl.dsp.focus({ workspace = workspace }))
    hl.bind(super("SHIFT + " .. key), hl.dsp.window.move({ workspace = workspace }))
end
hl.bind(super("mouse_down"), hl.dsp.focus({ workspace = "e+1" }))
hl.bind(super("mouse_up"), hl.dsp.focus({ workspace = "e-1" }))

-- Special workspaces
hl.bind(super("S"), hl.dsp.workspace.toggle_special("music"))
hl.bind(super("C"), hl.dsp.workspace.toggle_special("chat"))
hl.bind(super("P"), hl.dsp.workspace.toggle_special("passwords"))

-- Generic
local fullscreen = hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })
hl.bind("ALT + F4", hl.dsp.window.close())
hl.bind(super("SHIFT + Q"), hl.dsp.window.close())
hl.bind(super("F"), hl.dsp.window.float({ action = "toggle" }))
hl.bind(super("M"), hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(super("SHIFT + M"), fullscreen)
hl.bind("F11", fullscreen)

-- Window groups: tabs in one tile (group settings in general.lua). New
-- windows join the focused group; SUPER + H/L switch tabs.
hl.bind(super("G"), hl.dsp.group.toggle())
hl.bind(super("SHIFT + G"), hl.dsp.window.move({ out_of_group = true }))
hl.bind(super("Tab"), hl.dsp.group.next())
hl.bind(super("SHIFT + Tab"), hl.dsp.group.prev())

-- Move/resize windows with keyboard and mouse
hl.bind(super("H"), hl.dsp.focus({ direction = "left" }))
hl.bind(super("L"), hl.dsp.focus({ direction = "right" }))
hl.bind(super("J"), hl.dsp.focus({ direction = "down" }))
hl.bind(super("K"), hl.dsp.focus({ direction = "up" }))
hl.bind(super("up"), hl.dsp.window.resize({ x = 0, y = -resizeStep, relative = true }))
hl.bind(super("down"), hl.dsp.window.resize({ x = 0, y = resizeStep, relative = true }))
hl.bind(super("left"), hl.dsp.window.resize({ x = -resizeStep, y = 0, relative = true }))
hl.bind(super("right"), hl.dsp.window.resize({ x = resizeStep, y = 0, relative = true }))
hl.bind(super("mouse:272"), hl.dsp.window.drag(), { mouse = true })
hl.bind(super("mouse:273"), hl.dsp.window.resize(), { mouse = true })

-- Utilities
-- Screenshot editor (config/quickshell/menus/screenshot.py): select, draw,
-- scale, copy or save, or record a video; while a recording runs,
-- SUPER + SHIFT + S stops it
hl.bind(super("SHIFT + S"), exec(menus .. "screenshot.py"))
hl.bind(super("CONTROL + SHIFT + S"), exec(menus .. "screenshot.py window"))
hl.bind("Print", exec(menus .. "screenshot.py screen"))
-- Colour picker
hl.bind(super("SHIFT + C"), exec("hyprpicker -a"))
-- Lock the screen (pkgs/scripts/lock-screen.sh)
hl.bind(super("Escape"), exec("lock-screen"))
-- Details of the focused window
hl.bind(super("I"), exec(menus .. "toggle.sh window"))
-- Sound menu (quickshell/menus/audio.qml), and the full mixer
hl.bind(super("A"), exec(menus .. "toggle.sh audio"))
hl.bind(super("SHIFT + A"), exec("pavucontrol", { float = true }))

-- German letters on a US layout, at their German key positions. The letters
-- sit on F13-F16 of the keymap (keymap.xkb); Hyprland sends those keys to the
-- focused window, which also works in XWayland apps (wtype didn't).
local germanLetters = {
    { "semicolon", "odiaeresis" }, -- ö Ö
    { "bracketleft", "udiaeresis" }, -- ü Ü
    { "apostrophe", "adiaeresis" }, -- ä Ä
    { "minus", "ssharp" }, -- ß ẞ
}
for _, letter in ipairs(germanLetters) do
    local key, keysym = letter[1], letter[2]
    hl.bind(super(key), hl.dsp.send_shortcut({ mods = "", key = keysym }))
    hl.bind(super("SHIFT + " .. key), hl.dsp.send_shortcut({ mods = "SHIFT", key = keysym }))
end

-- Clipboard history (quickshell/menus/Clipboard.qml)
hl.bind(super("V"), hl.dsp.event("quickshell-clipboard"))
-- Workspaces with their windows (quickshell/menus/overview.qml)
hl.bind(super("W"), hl.dsp.event("quickshell-overview"))

-- Program shortcuts
hl.bind(super("T"), exec("kitty"))
hl.bind(super("E"), exec("nautilus", { float = true }))
hl.bind(super("SHIFT + E"), exec("nautilus"))
hl.bind(super("B"), exec("flatpak run com.brave.Browser"))
