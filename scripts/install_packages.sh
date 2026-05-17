#!/bin/bash

# install_packages.sh - Robustly installs official and AUR packages

set -e

DOTFILES_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
PKGLIST="$DOTFILES_DIR/pkglist.txt"
AUR_PKGLIST="$DOTFILES_DIR/aur_pkglist.txt"

echo "Checking for AUR helper (yay)..."
if ! command -v yay &> /dev/null; then
    echo "Installing yay..."
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd -
fi

# Ensure headers for all installed kernels are present before update
# This prevents DKMS build failures during yay -Syu
echo "Ensuring kernel headers are installed..."
INSTALLED_KERNELS=$(pacman -Qq | grep -E "^linux(-lts|-zen|-hardened)?$" || true)
if [ -n "$INSTALLED_KERNELS" ]; then
    for k in $INSTALLED_KERNELS; do
        echo "Installing headers for $k..."
        sudo pacman -S --needed --noconfirm "${k}-headers" || echo "Note: Could not install headers for $k."
    done
fi

echo "Updating official repositories..."
sudo pacman -Syu --noconfirm

echo "Updating AUR packages..."
# We allow AUR update to fail without stopping the whole script
# as it often contains non-critical build failures.
yay -Sua --noconfirm || echo "Warning: AUR update encountered some errors. Continuing..."

# Combine lists and remove duplicates
echo "Consolidating package lists..."
COMBINED_LIST=$(cat "$PKGLIST" "$AUR_PKGLIST" | sort -u)

echo "Installing packages..."
# We use yay for everything because it handles repo vs aur automatically.
# We try to install in one go first for speed.
# If it fails, we fall back to a loop to ensure we install as much as possible.

if echo "$COMBINED_LIST" | yay -S --needed --noconfirm -; then
    echo "All packages installed successfully."
else
    echo "Bulk installation failed. Retrying packages individually to skip errors..."
    for pkg in $COMBINED_LIST; do
        echo "Installing $pkg..."
        yay -S --needed --noconfirm "$pkg" || echo "Warning: Failed to install $pkg, skipping..."
    done
fi

echo "Package installation complete."
