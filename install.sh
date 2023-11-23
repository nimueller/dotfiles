#!/bin/sh

INSTALL_OPTION=$1
DOTFILES_CLONE_DIRECTORY=$HOME/.dotfiles

case "$INSTALL_OPTION" in
  headless) ;;
  desktop) ;;
  *) >&2 echo "Installation option '$INSTALL_OPTION' is not valid. Please provide one of [headless|desktop]"; exit 1 ;;
esac

if [ ! $(which git) ]; then
  echo 'Please install git before executing this script using your favourite package manager'
fi


install_nix () {
  curl -L 'https://nixos.org/nix/install' | sh
  mkdir -p "$HOME/.config/nix/"
  echo 'experimental-features = nix-command flakes' >> "$HOME/.config/nix/nix.conf"
  source "$HOME/.nix-profile/etc/profile.d/nix.sh"
}

install_home_manager() {
  nix run 'home-manager/master' -- init --switch 
}

install_repo() {
  if [ -d "$DOTFILES_CLONE_DIRECTORY" ]; then
    cd "$DOTFILES_CLONE_DIRECTORY"
    git pull
  else
    mkdir -p "$DOTFILES_CLONE_DIRECTORY"
    git clone 'https://github.com/LegendSalocin/dotfiles' "$DOTFILES_CLONE_DIRECTORY"
    cd "$DOTFILES_CLONE_DIRECTORY"
  fi

  home-manager switch --flake ".#$INSTALL_OPTION"
}

if [ ! $(which nix) ]; then
  install_nix
else 
  echo 'Nix is already installed, skipping'
fi

if [ ! $(which home-manager) ]; then
  install_home_manager
else 
  echo 'Home-Manager is already installed, skipping'
fi

install_repo

# vim: ts=2 sts=2 sw=2 et
