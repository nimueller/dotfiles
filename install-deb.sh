#!/usr/bin/env bash
set -eu

cd "$(dirname "$(readlink -f "$0")")"

echo "###################################"
echo "# Desktop Setup (Debian + Hyprland)"
echo "###################################"
echo

# ----------------------------
# System packages
# ----------------------------
echo "[1/4] Installing system packages..."

sudo apt update

sudo apt install -y \
  hyprland \
  waybar \
  flatpak \
  hyprpicker \
  hyprpaper \
  hyprlock

# NOTE: some Hyprland tools may be missing from the Debian repos. Because of
# `set -e`, a missing package makes apt fail and aborts the whole script.

echo "[2/4] Setting up Flatpak..."

# Ensure Flathub exists
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

flatpak install -y flathub \
  app.zen_browser.zen \
  org.keepassxc.KeePassXC \
  org.mozilla.thunderbird

flatpak override --user --env=QT_QPA_PLATFORM=xcb org.keepassxc.KeePassXC
flatpak override --user --filesystem=xdg-run/app/org.keepassxc.KeePassXC:create app.zen_browser.zen

# ----------------------------
# Nix installation
# ----------------------------
echo
echo "###################################"
echo "# Setting up Nix"
echo "###################################"
echo

if ! command -v nix >/dev/null 2>&1; then
  echo "[Nix] Not found, installing..."

  sh <(curl -L https://nixos.org/nix/install) --daemon

  # IMPORTANT: activate nix in current shell session
  if [ -f /etc/profile.d/nix.sh ]; then
    . /etc/profile.d/nix.sh
  fi

  # fallback for some installs
  if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
fi

echo "[Nix] Checking installation..."

if ! nix --version >/dev/null 2>&1; then
  echo "[ERROR] Nix is not working properly."
  exit 1
fi

echo "[Nix] OK: $(nix --version)"

# ----------------------------
# Home Manager
# ----------------------------
echo
echo "###################################"
echo "# Installing Home Manager"
echo "###################################"
echo

echo "[Home Manager] Running flake..."

# IMPORTANT: assumes flakes enabled in your config
nix run github:nix-community/home-manager -- switch --flake .#desktop

echo
echo "DONE ✔"

