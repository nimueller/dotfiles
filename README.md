# Personal dotfiles

> [!WARNING]  
> *Still heavily WIP*

## Home-Manager configuration (any OS)
### Installation
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


## NixOS configuration (NixOS required)
To (re-)build entire NixOS system:
```sh
sudo nixos-rebuild switch --flake .#desktop
```
