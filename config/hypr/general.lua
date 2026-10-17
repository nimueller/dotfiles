local colors = require("colors")

-- Any monitor: preferred mode, placed and scaled automatically. The real
-- layout of a machine goes into local.lua (see local.example.lua).
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

hl.config({
    -- Fix blurry XWayland applications for fractional scaling on main monitor
    xwayland = {
        force_zero_scaling = true,
    },

    general = {
        border_size = 0,
        gaps_in     = 0,
        gaps_out    = 0,
        col = {
            active_border   = colors.lavender,
            inactive_border = colors.overlay0,
        },
    },

    decoration = {
        rounding           = 0,
        active_opacity     = 1.0,
        inactive_opacity   = 1.0,
        fullscreen_opacity = 1.0,
        dim_modal          = false, -- the app behind a file chooser stays as it is
    },

    animations = {
        enabled = true,
    },

    input = {
        kb_layout          = "us",
        -- US with Compose on Right Alt, plus ä ö ü ß on F13-F16 for the SUPER binds
        kb_file            = os.getenv("HOME") .. "/.config/hypr/keymap.xkb",
        numlock_by_default = true,
        follow_mouse       = 1,
        touchpad = {
            natural_scroll = false,
        },
    },

    cursor = {
        no_hardware_cursors = true,
    },

    dwindle = {
        preserve_split = true,
    },

    -- Window groups (tabs, SUPER + G): new windows on the workspace join the
    -- focused group, SUPER + H/L go through its tabs before leaving it
    binds = {
        movefocus_cycles_groupfirst = true,
    },
    group = {
        col = {
            border_active   = colors.lavender,
            border_inactive = colors.overlay0,
        },
        groupbar = {
            font_family          = "NotoSans Nerd Font",
            font_size            = 11,
            height               = 18,
            gradients            = true,
            indicator_height     = 0,
            text_color           = colors.base,
            text_color_inactive  = colors.text,
            col = {
                active   = colors.lavender,
                inactive = colors.surface0,
            },
        },
    },

    misc = {
        enable_swallow             = true,
        allow_session_lock_restore = true,
        -- No splash text or logo where no wallpaper covers the background
        disable_splash_rendering   = true,
        disable_hyprland_logo      = true,
        -- A window that asks for focus gets it: a link clicked in kitty
        -- shows Brave on its workspace instead of a tab opening out of sight
        focus_on_activate          = true,
    },
})

hl.curve("myBezier", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })

hl.animation({ leaf = "windows",     enabled = true, speed = 7,  bezier = "myBezier" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 7,  bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border",      enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 8,  bezier = "default" })
hl.animation({ leaf = "fade",        enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 6,  bezier = "default" })

hl.env("XCURSOR_SIZE", "24")
hl.env("XDG_SESSION_TYPE", "wayland")

hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
