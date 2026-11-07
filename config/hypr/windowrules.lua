hl.window_rule({
    name = "floating-windows",
    match = { float = true },

    border_size = 1,
    rounding = 10,
})

-- Special workspaces
hl.window_rule({
    match = { class = "^com\\.github\\.th[-_]ch\\.youtube[-_]music$" },
    workspace = "special:music silent",
})
hl.window_rule({ match = { class = "discord" }, workspace = "special:chat silent" })
hl.window_rule({
    match = { class = "org.keepassxc.KeePassXC" },
    workspace = "special:passwords silent",
})

hl.window_rule({
    name = "wine-system-tray",
    match = { title = "Wine System Tray" },

    opacity = "0.0 override 0.0 override",
    no_anim = true,
    no_focus = true,
    no_initial_focus = true,
})

-- The browser gets focus when it asks for it: a link clicked in kitty shows
-- it on its workspace instead of a tab opening out of sight. Only for the
-- browser: for all windows, apps that ask for focus when they start would
-- pull their workspace forward despite "silent" (workspacerules.lua)
hl.window_rule({ match = { class = "^brave-browser$" }, focus_on_activate = true })

-- Since Hyprland 0.57, render.cm_auto_hdr offers HDR to fullscreen windows, so
-- a fullscreen video in the browser switches the monitor to HDR with a modeset.
-- This rule skips that offer, as before 0.57. Only for the browser, other
-- fullscreen apps keep cm_auto_hdr.
hl.window_rule({ match = { class = "^brave-browser$" }, no_auto_hdr = true })

hl.window_rule({ match = { class = "upc.exe" }, tile = true })
hl.window_rule({ match = { class = "polkit-gnome-authentication-agent-1" }, pin = true })
hl.window_rule({ match = { title = "Picture-in-Picture" }, float = true, pin = true })
hl.window_rule({ match = { class = "looking-glass-client" }, float = true })

hl.window_rule({
    name = "calculator",
    match = { class = "org.gnome.Calculator" },

    float = true,
    size = "660 742",
    move = "0 670",
    pin = true,
})

-- The windows of the shell, floating and centred at their size:
-- Machine Settings (config/quickshell/menus/settings.qml), Battery History
-- (battery-history.qml) and the Scanner (scan.qml)
local function centredWindow(title, size)
    hl.window_rule({
        match = { title = "^" .. title .. "$" },
        float = true,
        size = size,
        center = true,
    })
end
centredWindow("Machine Settings", "860 600")
centredWindow("Battery History", "760 720")
centredWindow("Scanner", "1040 740")

-- File chooser (Nautilus, config/xdg-desktop-portal): floating and centred,
-- also for apps that don't name their window to the portal (Hyprland floats
-- the others by itself). To Hyprland it's a Nautilus window like the others,
-- told apart only by its title: what the app asked for, or "Files" without
-- one; Nautilus' own windows are titled after their folder.
local chooserVerbs = "(Open|Save|Select|Choose|Export|Import|Upload|Attach|Add|Browse|Pick)\\b.*"
local chooserTitles = {
    "Files",
    chooserVerbs,
    "File Upload",
    "Enter name of file.*",
}
hl.window_rule({
    name = "file-chooser",
    match = {
        class = "^org\\.gnome\\.Nautilus$",
        initial_title = "^(" .. table.concat(chooserTitles, "|") .. ")$",
    },

    float = true,
    -- Like with a parent app; without one it opens at its tiled size
    size = "890 550",
    center = true,
})
