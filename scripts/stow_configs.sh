#!/bin/bash

DOTFILES_DIR=$(dirname "$(dirname "$(realpath "$0")")")
cd "$DOTFILES_DIR"

echo "Stowing configurations from $DOTFILES_DIR..."

# List of directories to stow
PACKAGES=$(find . -maxdepth 1 -type d -not -name "." -not -name ".git" -not -name "scripts" -printf "%f\n")

for pkg in $PACKAGES; do
    echo "Stowing $pkg..."
    stow -R "$pkg"
done

echo "Stow complete."
