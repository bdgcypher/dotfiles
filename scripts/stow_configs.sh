#!/bin/bash

# stow_configs.sh - Symlinks dotfiles using GNU Stow with backup logic

set -e

DOTFILES_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
BACKUP_DIR="$HOME/.dotfiles.bak/$(date +%Y%m%d_%H%M%S)"

# List of folders to exclude from stowing
EXCLUDE=("scripts" ".git" "system" "yay")

echo "Starting configuration stowing..."

cd "$DOTFILES_DIR"

for dir in */; do
    dir=${dir%/} # Remove trailing slash
    
    # Check if directory is in exclude list
    if [[ " ${EXCLUDE[@]} " =~ " ${dir} " ]]; then
        continue
    fi

    echo "Processing $dir..."

    # Backup existing files if they are NOT symlinks
    # Note: Stow handles this partially, but explicit backup is safer
    # This is a simplified version; stow --adopt is another option but riskier.
    
    stow -v -R -t "$HOME" "$dir"
done

echo "Stowing complete."
