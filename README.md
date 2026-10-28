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
| **Shell UI** | Quickshell: bar, menus (system, sound, network, Bluetooth, battery, calendar, …), launcher, clipboard history, notifications, on-screen display, screenshot editor, scanner (PDF with OCR, both sides from the feeder), a settings app for the machine |
| **Lock / idle** | hyprlock and hypridle, hyprpaper for the wallpapers |
| **Terminal** | kitty, Zsh with Powerlevel10k, zoxide (`j`), direnv with nix-direnv |
| **Git** | Commits signed with SSH and verified locally, delta as pager, GitHub CLI |
| **SSH** | Client defaults from Home Manager (keep-alive, shared connections), gcr's agent on the desktop |
| **Editor** | Neovim with lazy.nvim; language servers come from Nix |
| **Browser** | Brave from Flathub |
| **Laptop / touch** | Modes that turn on by themselves on laptops and with touch screens |

| | |
|:---:|:---:|
| ![App launcher](resources/launcher.webp) | ![Screenshot editor](resources/screenshot-editor.webp) |
| **Launcher:** apps, open windows, commands, sums and emoji | **Screenshot editor:** select, draw, scale, copy or save, or copy the text or QR code in it |

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
  `flake.nix`, the Git identity and signing key in `home-manager/headless/default.nix` (and the clone URL in
  `install.sh`).
- On ARM (`aarch64`) the script picks `headless_aarch64` or `desktop_aarch64`.
- For the desktop it also runs `system/setup.sh`, which needs root and asks before every step: the session packages
  from pacman, PAM (the login unlocks the keyring), LightDM auto-login, logind, firewall, Docker and Bluetooth.
- Settings that belong to one machine stay out of the repository, in untracked files that the tracked configuration
  includes:

  | File | What goes there |
  |---|---|
  | `config/hypr/local.lua` | Monitors, driver variables, private autostarts; the **Machine Settings** app in the launcher edits it |
  | `~/.ssh/config.local` | The SSH hosts (host names, users, keys); `~/.ssh/config` itself comes from Home Manager |
  | `~/.config/git/config.local` | Further Git identities, e.g. `includeIf "gitdir:~/work/"` with another email and key |

- Home Manager doesn't overwrite files it doesn't own: `install.sh` renames them to `*.hm-backup`, a plain
  `home-manager switch` stops. An existing `~/.claude/settings.json` has to go first.

## Usage

- `config/` holds the actual configuration files. They are linked into `~/.config`, so edits take effect without a
  rebuild. Only the Quickshell daemon needs a restart: `~/.config/quickshell/menus/toggle.sh daemon --restart`.
- Claude Code's `CLAUDE.md` and `settings.json` are linked from `config/claude`: plugins enabled with
  `claude plugin enable` or settings changed in `/config` show up as changes in the repository.
- `j <part of a path>` jumps to the best match of the visited directories (zoxide); autojump's history comes along with
  `zoxide import autojump --merge`. A project's `.envrc` with `use flake` loads its toolchain on `cd` (direnv).
- Packages and everything else on the Nix side live in `home-manager/` and `flake.nix`. Apply changes with
  `home-manager switch --flake ~/dotfiles#desktop` (or `#headless`, `#desktop_aarch64`, `#headless_aarch64`).
- `pkg-sync` compares the installed packages and Flatpaks with the declared lists and can adopt, prune or install them.
- `./check.sh` runs the linters (Nix, shell, Python, QML), pyright and the Python tests, as CI does; `nix fmt` formats
  the Nix files, `ruff format .` the Python. `nix develop` opens a shell with these tools, and
  `git config core.hooksPath .githooks` runs the checks before every commit. `CLAUDE.md` has the conventions (when Shell,
  when Python, how to test).
- CI updates `flake.lock` every week and merges the update when everything still builds.

| Path | What it holds |
|---|---|
| `flake.nix` | The Home Manager configurations |
| `home-manager/` | Nix modules: `headless`, `desktop`, `dev` (toolchains), `theme` |
| `config/` | Configuration files: Hyprland (`hypr/hyprland.lua`), Quickshell (`quickshell/menus`), kitty, Neovim, Zsh, … |
| `system/` | The root side: pacman package lists and `setup.sh` |
| `pkgs/` | Small helper scripts |
| `tests/` | Unit tests of the Python scripts |

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
- [ ] One general location setting (e.g. in Machine Settings) for the weather and the night light, instead of the calendar's weather location
- [ ] Turning the screen with the device (iio-sensor-proxy)
- [ ] Night light with `hyprsunset`

Ideas:

- [ ] Media controls (MPRIS) on the bar or in the sound menu: cover, title, play/pause/skip, position
- [ ] Screen recording in the screenshot tool (area, window or screen), with an indicator on the bar
- [ ] An overview of all workspaces with window previews, by gesture in touch mode
- [ ] Launcher: SSH hosts (opens `kitten ssh`), KeePassXC entries through the Secret Service, unit and currency
  conversion, file search
- [ ] Backups of the data the dotfiles don't cover (SSH keys, password database, documents, projects), e.g. restic
  with a systemd timer and the last backup in the system menu
- [ ] KeePassXC's settings from Home Manager, without the database paths
- [ ] `nix-index` with `comma` (run a program without installing it), `nh` for switches with a diff of the packages
- [ ] lazygit in Catppuccin, atuin for a shell history synced across machines
- [ ] Verify GitHub's squash merges locally too (import GitHub's web-flow key)
