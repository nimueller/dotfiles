local colors = require("colors")

-- Monitor setup using fractional scaling on main monitor
hl.monitor({
    output              = "desc:BNQ BenQ EL2870U WBL02007SL0",
    mode                = "3840x2160@60",
    -- mode             = "1920x1080@60",
    position            = "0x0",
    scale               = 1.5,
    supports_wide_color = 1,
    supports_hdr        = 1,
})

hl.monitor({
    output   = "desc:BNQ BenQ RL2455 P4E03178SL0",
    mode     = "1920x1080@60",
    position = "2560x0",
    scale    = 1.0,
})

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
    },

    animations = {
        enabled = true,
    },

    input = {
        kb_layout          = "us",
        kb_options         = "compose:ralt",
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

    misc = {
        enable_swallow             = true,
        allow_session_lock_restore = true,
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

-- Session variables for Nvidia
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("VDPAU_DRIVER", "nvidia")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")

hl.env("JAVA_HOME", "/usr/lib/jvm/default/")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
