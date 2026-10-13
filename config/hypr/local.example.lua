-- Template for local.lua: this machine's own settings, which git ignores.
-- Copy it to local.lua next to it and adapt it. hyprland.lua loads local.lua
-- last, so anything here overrides the shared config. Without a local.lua,
-- every monitor runs at its preferred mode, placed and scaled automatically.

-- Monitors: `hyprctl monitors all` lists names and descriptions. Match by
-- description so the rule follows the monitor to any port.
hl.monitor({
    output   = "desc:Vendor Model Serial",
    mode     = "2560x1440@144",
    position = "0x0",
    scale    = 1.25,
})

-- Driver variables, e.g. for NVIDIA
-- hl.env("LIBVA_DRIVER_NAME", "nvidia")
-- hl.env("GBM_BACKEND", "nvidia-drm")
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")

-- Programs only this machine starts, or that need private paths; after-unlock
-- starts them once the lock screen at login is unlocked (and the keyring with it)
-- hl.on("hyprland.start", function()
--     hl.exec_cmd("after-unlock 'keepassxc " .. os.getenv("HOME") .. "/path/to/database.kdbx'")
-- end)
