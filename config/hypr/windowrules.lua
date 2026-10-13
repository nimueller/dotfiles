hl.window_rule({
    name  = "floating-windows",
    match = { float = true },

    border_size = 1,
    rounding    = 10,
})

-- Special workspaces
hl.window_rule({ match = { class = "^com\\.github\\.th[-_]ch\\.youtube[-_]music$" }, workspace = "special:music silent" })
hl.window_rule({ match = { class = "discord" },                        workspace = "special:chat silent" })
hl.window_rule({ match = { class = "org.keepassxc.KeePassXC" },        workspace = "special:passwords silent" })

hl.window_rule({
    name  = "wine-system-tray",
    match = { title = "Wine System Tray" },

    opacity          = "0.0 override 0.0 override",
    no_anim          = true,
    no_focus         = true,
    no_initial_focus = true,
})

hl.window_rule({ match = { class = "upc.exe" },                             tile = true })
hl.window_rule({ match = { class = "polkit-gnome-authentication-agent-1" }, pin = true })
hl.window_rule({ match = { title = "Picture-in-Picture" },                  float = true, pin = true })
hl.window_rule({ match = { class = "looking-glass-client" },                float = true })

hl.window_rule({
    name  = "calculator",
    match = { class = "org.gnome.Calculator" },

    float = true,
    size  = "660 742",
    move  = "0 670",
    pin   = true,
})

-- Machine Settings (config/quickshell/menus/settings.qml)
hl.window_rule({ match = { title = "^Machine Settings$" }, float = true, size = "860 600", center = true })

-- File chooser (Nautilus, config/xdg-desktop-portal): floating and centred,
-- also for apps that don't name their window to the portal (Hyprland floats
-- the others by itself). To Hyprland it's a Nautilus window like the others,
-- told apart only by its title: what the app asked for, or "Files" without
-- one; Nautilus' own windows are titled after their folder.
hl.window_rule({
    name  = "file-chooser",
    match = {
        class         = "^org\\.gnome\\.Nautilus$",
        initial_title = "^(Files|(Open|Save|Select|Choose|Export|Import|Upload|Attach|Add|Browse|Pick)\\b.*|File Upload|Enter name of file.*)$",
    },

    float  = true,
    size   = "890 550", -- like with a parent app; without one it opens at its tiled size
    center = true,
})
