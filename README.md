# Personal dotfiles

> [!WARNING]  
> *Still heavily WIP*

<b>OS</b>: Arch Linux

<b>Desktop Environment</b>: Hyprland

<b>Shell</b>: ZSH

<b>Editor</b>: Neovim

<b>Status Bar</b>: Waybar

<b>Notification Daemon</b>: dunst

<b>Application Launcher</b>: rofi

<b>Browser</b>: Brave


| ![Images](resources/2023-11-29-213212_hyprshot.png) | ![Images](resources/2023-11-29-203138_hyprshot.png) |
|:---:|:---:|
| ![Images](resources/2023-11-29-203408_hyprshot.png) | ![Images](resources/2023-11-29-203439_hyprshot.png) |

## Installation

### Home-Manager configuration (any OS)
Prerequisites before running the install.sh script
* `curl`
* `git`

<details open>
  <summary><b>Headless mode</b></summary>
  For command line only (useful on servers or TTY)
  
  ```sh 
  curl -L https://raw.githubusercontent.com/LegendSalocin/dotfiles/main/install.sh | sh -s headless
  ```
</details>

<details open>
  <summary><b>Desktop mode</b></summary>
  Activating my desktop environment, applications, and stuff, in addition to headless mode
  
  ```sh
  curl -L https://raw.githubusercontent.com/LegendSalocin/dotfiles/main/install.sh | sh -s desktop
  ```
</details>

