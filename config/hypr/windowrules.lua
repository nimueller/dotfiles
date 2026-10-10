hl.window_rule({
    name  = "floating-windows",
    match = { float = true },

    border_size = 1,
    rounding    = 10,
})

-- Special workspaces
hl.window_rule({ match = { class = "com.github.th_ch.youtube_music" }, workspace = "special:music silent" })
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
