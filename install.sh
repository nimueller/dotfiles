#!/bin/bash

INSTALL_OPTION=$1
DOTFILES_CLONE_DIRECTORY=$HOME/dotfiles

case "$INSTALL_OPTION" in
  headless) ;;
  desktop) ;;
  runner) ;;
  *) >&2 echo "Installation option '$INSTALL_OPTION' is not valid. Use one of [headless|desktop|runner]"; exit 1 ;;
esac

if ! command -v git >/dev/null 2>&1; then
  echo 'Before running this script, install git with your package manager'
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo 'Before running this script, install curl with your package manager'
  exit 1
fi

if ! command -v xz >/dev/null 2>&1; then
  echo 'Before running this script, install xz with your package manager'
  exit 1
fi

install_nix () {
  curl -L 'https://nixos.org/nix/install' | sh
  mkdir -p "$HOME/.config/nix/"
  if ! grep -qs 'experimental-features' "$HOME/.config/nix/nix.conf"; then
    echo 'experimental-features = nix-command flakes' >> "$HOME/.config/nix/nix.conf"
  fi
  # shellcheck source=/dev/null
  source "$HOME/.nix-profile/etc/profile.d/nix.sh"
}

install_home_manager() {
  nix run 'home-manager/master' -- init --switch 
}

install_repo() {
  if [ -d "$DOTFILES_CLONE_DIRECTORY" ]; then
    cd "$DOTFILES_CLONE_DIRECTORY" || exit 1
    git pull
  else
    git clone 'https://github.com/nimueller/dotfiles' "$DOTFILES_CLONE_DIRECTORY"
    cd "$DOTFILES_CLONE_DIRECTORY" || exit 1
  fi

  home-manager switch --flake ".#$INSTALL_OPTION"
}

post_install_steps() {
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
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
  while [ -z "$SET_DEFAULT_SHELL" ]; do
    echo -n 'Skip? [y/n] '
    read -r -n 1 option
    echo ''

    case "$option" in
      y|Y) return ;;
      n|N) break ;;
      *) ;;
    esac
  done

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
' >> "$HOME/.profile"
  echo 'Zsh is now the default shell. Restart your terminal session.'
}

if ! command -v nix >/dev/null 2>&1; then
  install_nix
else 
  echo 'Nix is already installed, skipping'
fi

if ! command -v home-manager >/dev/null 2>&1; then
  install_home_manager
else 
  echo 'Home Manager is already installed, skipping'
fi

install_repo
post_install_steps
set_default_shell

# vim: ts=2 sts=2 sw=2 et
