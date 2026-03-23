#!/bin/bash

# Install yay if not present
if ! command -v yay &> /dev/null; then
    echo "Installing yay..."
    sudo pacman -S --needed base-devel git
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    pushd /tmp/yay
    makepkg -si --noconfirm
    popd
fi

# Install packages from list
echo "Installing packages from list..."
# Pre-remove 'rust' to avoid conflicts with 'rustup' if it's in the list
if grep -q "^rustup$" "$(dirname "$0")/packages.list"; then
    sudo pacman -Rs --noconfirm rust || true
fi

yay -S --needed --noconfirm - < $(dirname "$0")/packages.list

# Initialize rustup if installed
if command -v rustup &> /dev/null; then
    echo "Initializing rustup with stable toolchain..."
    rustup default stable
fi
