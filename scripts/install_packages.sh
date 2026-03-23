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
yay -S --needed --noconfirm - < $(dirname "$0")/packages.list
