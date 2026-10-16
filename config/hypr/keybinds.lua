local mainMod = "SUPER"
local resizeStep = 50

local function exec(cmd, rules) return hl.dsp.exec_cmd(cmd, rules) end

-- Launcher
hl.bind(mainMod .. " + D", hl.dsp.event("quickshell-launcher")) -- launcher in the resident quickshell daemon (quickshell/menus/Launcher.qml)

-- Brightness
hl.bind("XF86MonBrightnessUp",   hl.dsp.event("quickshell-osd brightness +5"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.event("quickshell-osd brightness -5"), { locked = true, repeating = true })

-- Media (prefer the chromium/Electron player, fall back to any)
hl.bind("XF86AudioPlay",  exec("playerctl -p chromium,%any play-pause"), { locked = true })
hl.bind("XF86AudioPause", exec("playerctl -p chromium,%any pause"),      { locked = true })
hl.bind("XF86AudioNext",  exec("playerctl -p chromium,%any next"),       { locked = true })
hl.bind("XF86AudioPrev",  exec("playerctl -p chromium,%any previous"),   { locked = true })
hl.bind("XF86AudioStop",  exec("playerctl -p chromium,%any stop"),       { locked = true })
hl.bind("XF86Calculator", exec("gnome-calculator"))

-- Case power button opens the power menu (logind must ignore the key, see
-- /etc/systemd/logind.conf.d/power-key.conf)
hl.bind("XF86PowerOff", exec("~/.config/quickshell/menus/toggle.sh power"))

-- Volume and brightness: the quickshell daemon changes them and shows the OSD
-- (config/quickshell/menus/Osd.qml); events, so no process starts per press
hl.bind("XF86AudioMicMute",     hl.dsp.event("quickshell-osd mic-mute"),  { locked = true })
hl.bind("XF86AudioMute",        hl.dsp.event("quickshell-osd mute"),      { locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.event("quickshell-osd volume +5"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.event("quickshell-osd volume -5"), { locked = true, repeating = true })

-- Caps Lock / Num Lock state in the OSD; non_consuming so the keys still work
hl.bind("Caps_Lock", hl.dsp.event("quickshell-osd lock caps"), { locked = true, non_consuming = true })
hl.bind("Num_Lock",  hl.dsp.event("quickshell-osd lock num"),  { locked = true, non_consuming = true })

-- Workspace controls (key 0 maps to workspace 10)
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Special workspaces
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("music"))
hl.bind(mainMod .. " + C", hl.dsp.workspace.toggle_special("chat"))
hl.bind(mainMod .. " + P", hl.dsp.workspace.toggle_special("passwords"))

-- Generic
hl.bind("ALT + F4",                hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F",         hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + M",         hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind("F11",                     hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))

-- Window groups: tabs in one tile (group settings in general.lua). New
-- windows join the focused group; SUPER + H/L switch tabs.
hl.bind(mainMod .. " + G",         hl.dsp.group.toggle())
hl.bind(mainMod .. " + SHIFT + G", hl.dsp.window.move({ out_of_group = true }))
hl.bind(mainMod .. " + Tab",       hl.dsp.group.next())
hl.bind(mainMod .. " + SHIFT + Tab", hl.dsp.group.prev())

-- Move/resize windows with keyboard and mouse
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + up",    hl.dsp.window.resize({ x = 0, y = -resizeStep, relative = true }))
hl.bind(mainMod .. " + down",  hl.dsp.window.resize({ x = 0, y = resizeStep, relative = true }))
hl.bind(mainMod .. " + left",  hl.dsp.window.resize({ x = -resizeStep, y = 0, relative = true }))
hl.bind(mainMod .. " + right", hl.dsp.window.resize({ x = resizeStep, y = 0, relative = true }))
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Utilities
-- Screenshot editor (config/quickshell/menus/screenshot.sh): select, draw, scale, copy or save
hl.bind(mainMod .. " + SHIFT + S",           exec("~/.config/quickshell/menus/screenshot.sh"))
hl.bind(mainMod .. " + CONTROL + SHIFT + S", exec("~/.config/quickshell/menus/screenshot.sh window"))
hl.bind("Print",                             exec("~/.config/quickshell/menus/screenshot.sh screen"))
hl.bind(mainMod .. " + SHIFT + C",           exec("hyprpicker -a")) -- Colour picker
hl.bind(mainMod .. " + Escape",              exec("pidof hyprlock || hyprlock")) -- Lock the screen
hl.bind(mainMod .. " + I",                   exec("~/.config/quickshell/menus/toggle.sh window")) -- Details of the focused window
hl.bind(mainMod .. " + A",                   exec("~/.config/quickshell/menus/toggle.sh audio")) -- Sound menu (quickshell/menus/audio.qml)
hl.bind(mainMod .. " + SHIFT + A",           exec("pavucontrol", { float = true })) -- Full mixer

-- German letters on a US layout, at their German key positions. The letters
-- sit on F13-F16 of the keymap (keymap.xkb); Hyprland sends those keys to the
-- focused window, which also works in XWayland apps (wtype didn't).
local function letter(key, shifted)
    return hl.dsp.send_shortcut({ mods = shifted and "SHIFT" or "", key = key })
end
hl.bind(mainMod .. " + semicolon",           letter("odiaeresis"))      -- ö
hl.bind(mainMod .. " + SHIFT + semicolon",   letter("odiaeresis", true)) -- Ö
hl.bind(mainMod .. " + bracketleft",         letter("udiaeresis"))      -- ü
hl.bind(mainMod .. " + SHIFT + bracketleft", letter("udiaeresis", true)) -- Ü
hl.bind(mainMod .. " + apostrophe",          letter("adiaeresis"))      -- ä
hl.bind(mainMod .. " + SHIFT + apostrophe",  letter("adiaeresis", true)) -- Ä
hl.bind(mainMod .. " + minus",               letter("ssharp"))          -- ß
hl.bind(mainMod .. " + SHIFT + minus",       letter("ssharp", true))    -- ẞ

hl.bind(mainMod .. " + V", hl.dsp.event("quickshell-clipboard")) -- clipboard history (quickshell/menus/Clipboard.qml)

-- Program shortcuts
hl.bind(mainMod .. " + T",         exec("kitty"))
hl.bind(mainMod .. " + E",         exec("nautilus", { float = true }))
hl.bind(mainMod .. " + SHIFT + E", exec("nautilus"))
hl.bind(mainMod .. " + B",         exec("flatpak run com.brave.Browser"))
