#!/bin/bash

# install_packages.sh - Installs official and AUR packages

set -e

DOTFILES_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
PKGLIST="$DOTFILES_DIR/pkglist.txt"
AUR_PKGLIST="$DOTFILES_DIR/aur_pkglist.txt"

echo "Checking for AUR helper (yay)..."
if ! command -v yay &> /dev/null; then
    echo "Installing yay..."
    sudo pacman -S --needed base-devel git
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd -
fi

echo "Updating system..."
sudo pacman -Syu --noconfirm

echo "Installing official packages..."
if [[ -f "$PKGLIST" ]]; then
    sudo pacman -S --needed --noconfirm - < "$PKGLIST"
else
    echo "Error: $PKGLIST not found."
fi

echo "Installing AUR packages..."
if [[ -f "$AUR_PKGLIST" ]]; then
    yay -S --needed --noconfirm - < "$AUR_PKGLIST"
else
    echo "Error: $AUR_PKGLIST not found."
fi

echo "Package installation complete."
