#!/bin/bash
# Installs Nix and these dotfiles with Home Manager.
#   install.sh headless   command line tools, Zsh, Neovim, tmux
#   install.sh desktop    headless plus Hyprland desktop (Arch Linux)
#   install.sh runner     headless for the CI runner
# Works when piped from curl (questions are read from the terminal).

INSTALL_OPTION=$1
DOTFILES_CLONE_DIRECTORY=$HOME/dotfiles
FLAKE_USER=nico # `username` in flake.nix

case "$INSTALL_OPTION" in
  headless | desktop) EXPECTED_USER=$FLAKE_USER ;;
  runner) EXPECTED_USER=runner ;;
  *) >&2 echo "Installation option '$INSTALL_OPTION' is not valid. Use one of [headless|desktop|runner]"; exit 1 ;;
esac

if [ "$INSTALL_OPTION" = headless ] && [ "$(uname -m)" = aarch64 ]; then
  FLAKE_OUTPUT=headless_aarch64
else
  FLAKE_OUTPUT=$INSTALL_OPTION
fi

if [ "$USER" != "$EXPECTED_USER" ]; then
  >&2 echo "These configurations are for the user '$EXPECTED_USER', not '$USER'."
  >&2 echo "Fork the repository and change 'username' in flake.nix first."
  exit 1
fi

for tool in git curl xz; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Before running this script, install $tool with your package manager"
    exit 1
  fi
done

# ask "question" -> true for yes
ask() {
  local option
  while true; do
    echo -n "$1 [y/n] "
    read -r -n 1 option </dev/tty
    echo ''
    case "$option" in
      y | Y) return 0 ;;
      n | N) return 1 ;;
    esac
  done
}

install_nix() {
  curl -L 'https://nixos.org/nix/install' | sh
  mkdir -p "$HOME/.config/nix/"
  if ! grep -qs 'experimental-features' "$HOME/.config/nix/nix.conf"; then
    echo 'experimental-features = nix-command flakes' >>"$HOME/.config/nix/nix.conf"
  fi
  # Single-user or multi-user (daemon) installation
  for profile in "$HOME/.nix-profile/etc/profile.d/nix.sh" /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh; do
    # shellcheck source=/dev/null
    [ -f "$profile" ] && . "$profile"
  done
}

install_repo() {
  if [ -d "$DOTFILES_CLONE_DIRECTORY" ]; then
    cd "$DOTFILES_CLONE_DIRECTORY" || exit 1
    git pull
  else
    git clone 'https://github.com/nimueller/dotfiles' "$DOTFILES_CLONE_DIRECTORY"
    cd "$DOTFILES_CLONE_DIRECTORY" || exit 1
  fi

  # The configuration installs Home Manager itself; files it would replace
  # are kept with the extension .hm-backup
  if command -v home-manager >/dev/null 2>&1; then
    home-manager switch -b hm-backup --flake ".#$FLAKE_OUTPUT"
  else
    nix run 'home-manager/master' -- switch -b hm-backup --flake ".#$FLAKE_OUTPUT"
  fi
}

post_install_steps() {
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  fi
}

# What the desktop needs from the system rather than from Nix: the
# compositor and its portal, session services and the polkit agent
ARCH_PACKAGES=(
  hyprland hyprpaper hyprlock xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  pipewire pipewire-pulse wireplumber networkmanager upower brightnessctl
  polkit-gnome gnome-keyring
)

install_desktop_system() {
  if ! command -v pacman >/dev/null 2>&1; then
    echo "Not on Arch Linux: install Hyprland and these (or your distribution's equivalents) yourself:"
    echo "  ${ARCH_PACKAGES[*]}"
    return
  fi

  echo ''
  echo "The desktop needs these packages from pacman: ${ARCH_PACKAGES[*]}"
  if ask 'Install the missing ones now (sudo)?'; then
    # shellcheck disable=SC2024 # only pacman's confirmation reads the terminal
    sudo pacman -S --needed "${ARCH_PACKAGES[@]}" </dev/tty
  fi

  local conf=/etc/systemd/logind.conf.d/power-key.conf
  if [ ! -f "$conf" ]; then
    echo ''
    echo "The power button can open the power menu instead of shutting down right away ($conf)."
    if ask 'Set that up now (sudo)?'; then
      sudo mkdir -p "$(dirname "$conf")"
      printf '[Login]\nHandlePowerKey=ignore\n' | sudo tee "$conf" >/dev/null
      echo 'Takes effect after the next reboot.'
    fi
  fi
}

set_default_shell() {
  echo -n '
-----------------------------------------------------------------------------------------------------------------------

Setting your default shell to Zsh (assuming your login shell is Bash and was not changed with chsh).

Home Manager cannot change the login shell with chsh; only NixOS can set it. Instead, a small hack in
.profile starts Zsh whenever Bash starts, so do not delete the generated .profile even though you use Zsh.

This step moves your existing '\$HOME/.profile' to '\$HOME/.profile.backup' and starts Zsh from .profile from now on.
If '\$HOME/.profile.backup' already exists, this step is skipped. Move that file away and run this script again
to set Zsh as your default shell later.

'
  if ask 'Skip?'; then
    return
  fi

  if [ -f "$HOME/.profile.backup" ]; then
    echo "$HOME/.profile.backup already exists. Move it to a safe place and run this script again."
    return
  fi

  if [ -f "$HOME/.profile" ]; then
    mv "$HOME/.profile" "$HOME/.profile.backup"
  fi

  # shellcheck disable=SC2016 # $BASH_VERSION belongs in .profile literally
  echo -n '
# execute zsh if it exists
if [ -n "$BASH_VERSION" ]; then
    if (which zsh >/dev/null 2>&1); then
        exec zsh
    fi
fi
' >>"$HOME/.profile"
  echo 'Zsh is now the default shell. Restart your terminal session.'
}

if ! command -v nix >/dev/null 2>&1; then
  install_nix
else
  echo 'Nix is already installed, skipping'
fi

install_repo
post_install_steps
[ "$INSTALL_OPTION" = desktop ] && install_desktop_system
[ "$INSTALL_OPTION" = runner ] || set_default_shell

# vim: ts=2 sts=2 sw=2 et
