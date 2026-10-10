local mainMod = "SUPER"
local resizeStep = 50

local function exec(cmd, rules) return hl.dsp.exec_cmd(cmd, rules) end

-- Launcher
hl.bind(mainMod .. " + D", exec("applauncher"))

-- Brightness
hl.bind("XF86MonBrightnessUp",   exec("brightnessctl set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", exec("brightnessctl set 5%-"), { locked = true, repeating = true })

-- Media (prefer the chromium/Electron player, fall back to any)
hl.bind("XF86AudioPlay",  exec("playerctl -p chromium,%any play-pause"), { locked = true })
hl.bind("XF86AudioPause", exec("playerctl -p chromium,%any pause"),      { locked = true })
hl.bind("XF86AudioNext",  exec("playerctl -p chromium,%any next"),       { locked = true })
hl.bind("XF86AudioPrev",  exec("playerctl -p chromium,%any previous"),   { locked = true })
hl.bind("XF86AudioStop",  exec("playerctl -p chromium,%any stop"),       { locked = true })
hl.bind("XF86Calculator", exec("gnome-calculator"))

-- Volume
hl.bind("XF86AudioMicMute",     exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86AudioMute",        exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),   { locked = true })
hl.bind("XF86AudioRaiseVolume", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })

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
hl.bind(mainMod .. " + SHIFT + S",           exec("hyprshot -o $HOME/Pictures/Screenshots/ -m region"))
hl.bind(mainMod .. " + CONTROL + SHIFT + S", exec("hyprshot -o $HOME/Pictures/Screenshots/ -m window"))
hl.bind(mainMod .. " + SHIFT + C",           exec("hyprpicker -a")) -- Colour picker

-- German umlauts on a US layout
hl.bind(mainMod .. " + semicolon",           exec("wtype 'ö'"))
hl.bind(mainMod .. " + SHIFT + semicolon",   exec("wtype 'Ö'"))
hl.bind(mainMod .. " + bracketleft",         exec("wtype 'ü'"))
hl.bind(mainMod .. " + SHIFT + bracketleft", exec("wtype 'Ü'"))
hl.bind(mainMod .. " + apostrophe",          exec("wtype 'ä'"))
hl.bind(mainMod .. " + SHIFT + apostrophe",  exec("wtype 'Ä'"))
hl.bind(mainMod .. " + minus",               exec("wtype 'ß'"))

hl.bind(mainMod .. " + V", exec("cliphist list | rofi -dmenu | cliphist decode | tee >(wtype -) | wl-copy"))

-- Program shortcuts
hl.bind(mainMod .. " + T",         exec("kitty"))
hl.bind(mainMod .. " + E",         exec("nautilus", { float = true }))
hl.bind(mainMod .. " + SHIFT + E", exec("nautilus"))
hl.bind(mainMod .. " + B",         exec("zen-browser"))
