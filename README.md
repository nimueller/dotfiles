# Personal dotfiles

> [!WARNING]  
> *Heavily vibecoded with Claude Code Opus 5.5*
>
> Why vibecoding? Because I am lazy and it is way more effective: I can just tell Claude what I want from my desktop and
> dotfiles. Every change is still reviewed by hand before it lands.

My Arch Linux setup: a [Hyprland](https://hyprland.org) desktop whose bar, menus, launcher, notifications and
screenshot tool are all written in [Quickshell](https://quickshell.org), plus Zsh and Neovim for the terminal.
Packages and configuration come from Nix with [Home Manager](https://github.com/nix-community/home-manager), and
everything wears [Catppuccin Macchiato](https://catppuccin.com).

![Desktop: Neovim, a file tree and git log in kitty, with a notification](resources/desktop.webp)

## What's inside

| | |
|---|---|
| **OS** | Arch Linux, packages via Nix + Home Manager (the session itself from pacman) |
| **Compositor** | Hyprland, configured in Lua |
| **Shell UI** | Quickshell: bar, menus (system, sound, network, Bluetooth, battery, calendar, …), launcher, clipboard history, notifications, on-screen display, screenshot editor, a settings app for the machine |
| **Lock / idle** | hyprlock and hypridle, hyprpaper for the wallpapers |
| **Terminal** | kitty, Zsh with Powerlevel10k |
| **Editor** | Neovim with lazy.nvim; language servers come from Nix |
| **Browser** | Brave from Flathub |
| **Laptop / touch** | Modes that turn on by themselves on laptops and with touch screens |

| | |
|:---:|:---:|
| ![App launcher](resources/launcher.webp) | ![Screenshot editor](resources/screenshot-editor.webp) |
| **Launcher:** apps, open windows, commands, sums and emoji | **Screenshot editor:** select, draw, scale, copy or save |

## Installation

The script installs Nix (with flakes) if needed, clones this repository to `~/dotfiles` and applies a Home Manager
configuration. It needs `git`, `curl` and `xz`.

```sh
# command line only (servers, TTY)
curl -L https://raw.githubusercontent.com/nimueller/dotfiles/main/install.sh | bash -s headless

# headless plus the Hyprland desktop
curl -L https://raw.githubusercontent.com/nimueller/dotfiles/main/install.sh | bash -s desktop
```

- The configurations are made for my user name. To use them yourself, fork the repository and change `username` in
  `flake.nix` (and the clone URL in `install.sh`).
- On ARM (`aarch64`) the script picks `headless_aarch64` or `desktop_aarch64`.
- For the desktop it also runs `system/setup.sh`, which needs root and asks before every step: the session packages
  from pacman, PAM (the login unlocks the keyring), LightDM auto-login, logind, firewall, Docker and Bluetooth.
- Settings that belong to one machine (monitors, driver variables, private autostarts) go into the untracked
  `config/hypr/local.lua`. The **Machine Settings** app in the launcher edits it.

## Usage

- `config/` holds the actual configuration files. They are linked into `~/.config`, so edits take effect without a
  rebuild. Only the Quickshell daemon needs a restart: `~/.config/quickshell/menus/toggle.sh daemon --restart`.
- Packages and everything else on the Nix side live in `home-manager/` and `flake.nix`. Apply changes with
  `home-manager switch --flake ~/dotfiles#desktop` (or `#headless`, `#desktop_aarch64`, `#headless_aarch64`).
- `pkg-sync` compares the installed packages and Flatpaks with the declared lists and can adopt, prune or install them.
- `./check.sh` runs the linters (Nix, shell, Python, QML) that CI also runs; `nix fmt` formats the Nix files.
  `git config core.hooksPath .githooks` runs it before every commit.
- CI updates `flake.lock` every week and merges the update when everything still builds.

| Path | What it holds |
|---|---|
| `flake.nix` | The Home Manager configurations |
| `home-manager/` | Nix modules: `headless`, `desktop`, `dev` (toolchains), `theme` |
| `config/` | Configuration files: Hyprland (`hypr/hyprland.lua`), Quickshell (`quickshell/menus`), kitty, Neovim, Zsh, … |
| `system/` | The root side: pacman package lists and `setup.sh` |
| `pkgs/` | Small helper scripts |

## Keybindings

`SUPER` is the main modifier. The full list is in `config/hypr/keybinds.lua`.

| Keys | Action |
|---|---|
| `SUPER + T` / `B` / `E` | kitty / Brave / Files |
| `SUPER + D` | App launcher |
| `SUPER + V` | Clipboard history |
| `SUPER + SHIFT + S` | Screenshot |
| `SUPER + Escape` | Lock the screen |
| `SUPER + 1`…`0` | Go to workspace (`SHIFT`: move the window there) |
| `SUPER + H J K L` | Move the focus |
| `SUPER + F` / `M` / `SHIFT + M` | Float / maximise / fullscreen |
| `SUPER + SHIFT + Q` | Close the window |
| Power button | Power menu |

## TODO

- [ ] Drop `--disable-gpu-memory-buffer-video-frames` from `config/brave-flags.conf` once Brave no longer needs it
- [ ] A toggle that keeps the screen awake
- [ ] Laptop and touch mode on real hardware (lid switch, squeekboard in Brave, Wi-Fi)
- [ ] Turning the screen with the device (iio-sensor-proxy)
- [ ] Night light with `hyprsunset`
- [ ] Waiting updates at a glance on the bar, including AUR updates
