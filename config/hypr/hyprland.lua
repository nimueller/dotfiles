-- Hyprland Lua config entry point. Modules live next to this file.
local source = debug and debug.getinfo(1, "S").source or ""
local dir = source:match("^@(.*/)") or ((os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/")
package.path = dir .. "?.lua;" .. package.path

require("general")
require("autostart")
require("keybinds")
require("windowrules")
require("workspacerules")
