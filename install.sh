#!/bin/bash

INSTALL_OPTION=$1
SKIP_SHELL_CHECK=$2
DOTFILES_CLONE_DIRECTORY=$HOME/.dotfiles

case "$INSTALL_OPTION" in
  headless) ;;
  desktop) ;;
  *) >&2 echo "Installation option '$INSTALL_OPTION' is not valid. Please provide one of [headless|desktop]"; exit 1 ;;
esac

if [ ! $(which git) ]; then
  echo 'Before running this script, you must install git using your favourite package manager'
fi

if [ ! $(which curl) ]; then
  echo 'Before running this script, you must install curl using your favourite package manager'
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

post_install_steps() {
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  fi

  bat cache --build
}

set_default_shell() {
  echo -n '
-----------------------------------------------------------------------------------------------------------------------

Trying to set your default shell to ZSH (assuming your default login shell is Bash and was not changed using the chsh command).

This process will use a little hack to automatically start ZSH every time you want to start Bash.
Changing the default shell using chsh is not possible with Home-Manager, as NixOS is required to automatically set the default login shell.
Thus, the generated .bashrc file should not be deleted, although using ZSH.

This step will copy your existing '\$HOME/.bashrc' file to '\$HOME/.bashrc.backup' and bootstrap ZSH from bashrc in the future.
If '\$HOME/.bashrc.backup' already exists, this step will be automatically skipped.
You may run this script again if you want to set ZSH as your default shell or in case the .bashrc.backup already exists. 

'
  while true; do
    echo -n 'Skip? [y/n] '
    read -n 1 option
    echo ''

    case "$option" in
      y|Y) return ;;
      n|N) break ;;
      *) ;;
    esac
  done

  if [ -f "$HOME/.bashrc.backup" ]; then
    echo "$HOME/.bashrc.backup already exists. Please move this file to a safe place and restart this installation script."
    return
  fi

  if [ -f "$HOME/.bashrc" ]; then
    mv "$HOME/.bashrc" "$HOME/.bashrc.backup"
  fi

  echo -n '
PATH=$PATH:$HOME/.nix-profile/bin
exec zsh
' > "$HOME/.bashrc"
  echo 'Made ZSH the default shell. Please restart your terminal session.'
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
post_install_steps

if [ -n "$SKIP_SHELL_CHECK" ]; then
  set_default_shell
fi

# vim: ts=2 sts=2 sw=2 et
