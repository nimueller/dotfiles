#!/bin/bash
# Installs Nix and these dotfiles with Home Manager.
#   install.sh headless   command line tools, Zsh, Neovim
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

if [ "$INSTALL_OPTION" != runner ] && [ "$(uname -m)" = aarch64 ]; then
  FLAKE_OUTPUT=${INSTALL_OPTION}_aarch64
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

# Packages, PAM and logind for the desktop, from system/setup.sh (needs root;
# every step asks first)
install_desktop_system() {
  echo ''
  "$DOTFILES_CLONE_DIRECTORY/system/setup.sh"
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
[ "$INSTALL_OPTION" = desktop ] && install_desktop_system
[ "$INSTALL_OPTION" = runner ] || set_default_shell

# vim: ts=2 sts=2 sw=2 et
