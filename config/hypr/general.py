# Monitor setup using fractional scaling on main monitor
hl.monitors = [
    {
        "output": "desc:BNQ BenQ EL2870U WBL02007SL0",
        "mode": "3840x2160@60",
        "position": "0x0",
        "scale": 1.5,
        "supports_wide_color": 1,
        "supports_hdr": 1,
    },
    {
        "output": "desc:BNQ BenQ RL2455 P4E03178SL0",
        "mode": "1920x1080@60",
        "position": "2560x0",
        "scale": 1.0,
    },
]

# Fix blurry XWayland applications for fractional scaling on main monitor
xwayland = {
    "force_zero_scaling": True,
}

# General config changes, disable cursor warps, etc.
general = {
    "border_size": 0,
    "gaps_in": 0,
    "gaps_out": 0,
    "col.active_border": "$lavender",
    "col.inactive_border": "$overlay0",
}

# Visual decoration and animations
decoration = {
    "rounding": 0,
    "active_opacity": 1,
    "inactive_opacity": 1,
    "fullscreen_opacity": 1,
}

animations = {
    "enabled": True,
    "bezier": [
        "myBezier, 0.05, 0.9, 0.1, 1.05",
    ],
    "animation": [
        "windows, 1, 7, myBezier",
        "windowsOut, 1, 7, default, popin 80%",
        "border, 1, 10, default",
        "borderangle, 1, 8, default",
        "fade, 1, 7, default",
        "workspaces, 1, 6, default",
    ],
}

# Input configuration
input_config = {
    "kb_layout": "us",
    "kb_options": "compose:ralt",
    "numlock_by_default": True,
    "follow_mouse": 1,
    "touchpad": {
        "natural_scroll": False,
    },
}

# Environment variables
env = {
    "XCURSOR_SIZE": "24",
    # Session variables for Nvidia
    "LIBVA_DRIVER_NAME": "nvidia",
    "VDPAU_DRIVER": "nvidia",
    "XDG_SESSION_TYPE": "wayland",
    "GBM_BACKEND": "nvidia-drm",
    "__GLX_VENDOR_LIBRARY_NAME": "nvidia",
    "NVD_BACKEND": "direct",
    "JAVA_HOME": "/usr/lib/jvm/default/",
    "ELECTRON_OZONE_PLATFORM_HINT": "auto",
    "QS_DISABLE_DMABUF": "1",
}

cursor = {
    "no_hardware_cursors": True,
}

dwindle = {
    "preserve_split": True,
}

misc = {
    "enable_swallow": True,
    "allow_session_lock_restore": True,
}
