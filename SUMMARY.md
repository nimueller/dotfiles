# Dotfiles overview

## Layout

| Path | Purpose |
|---|---|
| `flake.nix` | Home-Manager configs: `headless`, `headless_aarch64`, `desktop` (headless + desktop), `runner` (CI) |
| `options/` | Defines the `dotfiles` option, which is where this repo is checked out (default `~/dotfiles`) |
| `home-manager/headless/` | CLI packages, zsh (oh-my-zsh + powerlevel10k), git (SSH signing), btop, Neovim LSP/tool packages |
| `home-manager/desktop/` | Fonts, Wayland tools, GNOME apps, mangohud, kdeconnect, symlinks for the desktop configs |
| `home-manager/theme/` | Catppuccin Macchiato for btop/bat (headless) and GTK/cursor (desktop) |
| `pkgs/` | `hyprshot` plus the scripts `recorder`, `applauncher`, `init-tex`, `edit-tex` |
| `config/` | Raw config files that are symlinked out of the store, so edits apply without a rebuild |
| `install.sh` / `install-deb.sh` | Bootstrap Nix + Home-Manager (generic / Debian with Hyprland and Flatpaks) |

`config/` is linked with `mkOutOfStoreSymlink`, so `~/.config/<app>` points directly at
`~/dotfiles/config/<app>`. Editing the checkout changes the live system right away.

## Stack

- **Compositor:** Hyprland, with monitorv2 for a 4K@1.5 BenQ plus a 1080p BenQ and NVIDIA env vars. It's split into
  `general`, `autostart`, `keybinds`, `windowrules` and `workspacerules`.
- **Bar / wallpaper / lock:** Waybar, hyprpaper (rotates through `hypr/wallpapers/`), hyprlock
- **Launcher / clipboard:** rofi (`applauncher`), cliphist
- **Terminal / shell:** kitty, zsh with p10k, tmux (prefix `C-a`, tpm, catppuccin)
- **Editor:** Neovim with lazy.nvim, treesitter, telescope, neo-tree, blink.cmp, none-ls. All LSPs come from Nix.
- **Theme:** Catppuccin Macchiato throughout
- **CI:** flake check plus evaluation of every HM config on push, and a weekly `flake.lock` update
