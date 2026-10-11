# Personal dotfiles

> [!WARNING]  
> *Heavily vibecoded with Claude Code Opus 5.5*
>
> Why vibecoding? Because I am lazy and it is way more effective: I can just tell Claude what I want from my desktop and dotfiles.

My Arch Linux setup: a [Hyprland](https://hyprland.org) desktop whose bar, menus, launcher, notifications and
screenshot tool are all written in [Quickshell](https://quickshell.org), plus Zsh, tmux and Neovim for the terminal.
Packages and configuration come from Nix with [Home Manager](https://github.com/nix-community/home-manager), and
everything wears [Catppuccin Macchiato](https://catppuccin.com).

![Desktop: Neovim, a file tree and git log in kitty, with a notification](resources/desktop.webp)

## What's inside

| | |
|---|---|
| **OS** | Arch Linux, packages via Nix + Home Manager |
| **Compositor** | Hyprland, configured in Lua |
| **Shell UI** | Quickshell: bar, menus, launcher, clipboard history, notifications, on-screen display, screenshot editor |
| **Wallpaper / lock** | hyprpaper (rotating through `config/hypr/wallpapers`) / hyprlock |
| **Terminal** | kitty, Zsh with Powerlevel10k, tmux |
| **Editor** | Neovim with lazy.nvim, Treesitter, Telescope, Neo-tree and blink.cmp; language servers come from Nix |
| **Browser** | Zen |
| **Theme** | Catppuccin Macchiato for everything, including GTK, the cursor, btop and bat |

## The Quickshell desktop

One resident Quickshell process holds the bar on every monitor, the launcher, the clipboard history, the notification
daemon and the on-screen display, so they open instantly. The bigger menus are started on demand and quit when they close.

| | |
|:---:|:---:|
| ![App launcher](resources/launcher.webp) | ![Screenshot editor](resources/screenshot-editor.webp) |
| **Launcher:** type to filter, apps you use often come first, or run the text as a command | **Screenshot editor:** select, adjust, draw, scale, then copy or save |
| ![Power menu](resources/power-menu.webp) | |
| **Power menu:** lock, log out, suspend, reboot or shut down, by mouse or key | |

- **Bar:** workspaces, window title, clock, tray (with themed menus), microphone and screen-sharing indicators, volume,
  battery, network and a notification bell. Clicking a module opens its menu.
- **Sound:** output and input devices and their volumes, per-app volume.
- **Network:** wired and Wi-Fi connections, plus VPNs (import OpenVPN or WireGuard files).
- **Calendar:** a month view with Nextcloud calendars (CalDAV: create, edit and delete appointments, with reminders) and
  read-only ICS subscriptions, a weather forecast per day and by the hour, and the current weather from the nearest
  airport's METAR report.
- **Notifications:** popups with a countdown bar, a notification centre with history and do not disturb. They replace dunst.
- **On-screen display:** volume, microphone, brightness, Caps Lock and Num Lock. It replaces SwayOSD.
- **Clipboard history:** cliphist with image thumbnails; the chosen entry is pasted right away, in Wayland and X11 apps.
- **Screenshots:** the screen freezes, you pick a region or window (or the whole monitor) and can still resize the box,
  draw on it (pen, line, arrow, boxes, highlighter, text, pixelate), scale it to 75, 50 or 25 %, then copy it or save
  it to `~/Pictures/Screenshots`.

## Keybindings

`SUPER` is the main modifier.

| Keys | Action |
|---|---|
| `SUPER + T` / `B` | kitty / Zen |
| `SUPER + E` | Files, floating (`SHIFT`: tiled) |
| `SUPER + D` | App launcher |
| `SUPER + V` | Clipboard history |
| `SUPER + SHIFT + S` | Screenshot: region or window |
| `SUPER + CTRL + SHIFT + S` / `Print` | Screenshot of the active window / the whole monitor |
| `SUPER + SHIFT + C` | Colour picker |
| `SUPER + 1`…`0` | Go to workspace 1–10 (`SHIFT`: move the window there) |
| `SUPER + S` / `C` / `P` | Scratchpads for music, chat and passwords |
| `SUPER + H J K L` | Move the focus |
| `SUPER + arrows` / `SUPER + right mouse` | Resize the window |
| `SUPER + left mouse` | Move the window |
| `SUPER + F` / `M` / `SHIFT + M` | Float / maximise / fullscreen |
| `SUPER + SHIFT + Q`, `ALT + F4` | Close the window |
| `SUPER + ;` `'` `[` `-` | ö ä ü ß on a US layout (`SHIFT` for capitals), in Wayland and X11 apps |
| Power button | Power menu |

## Installation

The script installs Nix (with flakes) if needed, clones this repository to `~/dotfiles` and applies a Home Manager
configuration. It needs `git`, `curl` and `xz`.

<details open>
  <summary><b>Headless</b>: command line only, for servers or a TTY</summary>

  ```sh
  curl -L https://raw.githubusercontent.com/nimueller/dotfiles/main/install.sh | bash -s headless
  ```
</details>

<details open>
  <summary><b>Desktop</b>: headless plus the Hyprland desktop and its applications</summary>

  ```sh
  curl -L https://raw.githubusercontent.com/nimueller/dotfiles/main/install.sh | bash -s desktop
  ```
</details>

Good to know:

- The configurations are made for my user name. To use them yourself, fork the repository and change `username` in
  `flake.nix` (and the clone URL in `install.sh`).
- Hyprland and the system services the desktop relies on (PipeWire, NetworkManager, UPower, the portals, the polkit
  agent, the keyring) come from pacman. On Arch, the script offers to install them, and to let the power button open the
  power menu instead of shutting down.
- Start the desktop by running `Hyprland` after logging in on a TTY.
- Settings that belong to one machine (monitors, driver variables, programs with private paths) go into
  `config/hypr/local.lua`, which git ignores. `config/hypr/local.example.lua` shows how; without it, every monitor runs
  at its preferred mode.
- Zsh becomes the login shell through a small hook in `~/.profile`, since Home Manager can't run `chsh`. The script asks
  before doing that.

## Repository layout

| Path | What it holds |
|---|---|
| `flake.nix` | The Home Manager configurations: `headless`, `headless_aarch64`, `desktop` and `runner` (CI) |
| `home-manager/headless` | Command line tools, Zsh, git, btop, and what Neovim's plugins need |
| `home-manager/desktop` | Fonts, Wayland tools, desktop apps, the Quickshell services and MangoHud |
| `home-manager/dev` | Language servers, formatters and toolchains (desktop only; several GB) |
| `home-manager/theme` | Catppuccin for btop and bat, GTK and the cursor |
| `options` | The `dotfiles` option: where this repository is checked out (`~/dotfiles`) |
| `pkgs` | Small scripts (`recorder`, `init-tex`, `edit-tex`) and the Python for the calendar helper |
| `config` | The configuration files themselves: Hyprland, Quickshell, kitty, Neovim, tmux, Zsh |

The files in `config` are linked into `~/.config` with `mkOutOfStoreSymlink`, so `~/.config/<app>` points straight at
`~/dotfiles/config/<app>`: edits take effect without rebuilding. The Quickshell daemon is the one exception; restart it
with `~/.config/quickshell/menus/toggle.sh daemon --restart`.

Hyprland's config starts at `config/hypr/hyprland.lua`, and the desktop shell lives in `config/quickshell/menus`.

## Maintenance

- Apply changes to the Nix side with `home-manager switch --flake ~/dotfiles#desktop` (or `#headless`).
- On every push, CI formats and lints the Nix files (nixfmt, statix, deadnix), checks the shell scripts (shellcheck) and
  evaluates every configuration.
- Every week, CI updates `flake.lock` in a pull request, builds the configurations with it and merges it when they
  build; otherwise it closes the pull request.
- Home Manager removes generations older than a week by itself.
