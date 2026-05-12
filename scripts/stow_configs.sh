#!/bin/bash

# stow_configs.sh - Symlinks dotfiles using GNU Stow with automated backup logic

set -e

DOTFILES_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
BACKUP_DIR="$HOME/.dotfiles.bak/$(date +%Y%m%d_%H%M%S)"

# List of folders to exclude from stowing
EXCLUDE=("scripts" ".git" "system" "yay")

echo "Starting configuration stowing..."
echo "Backups (if any) will be stored in: $BACKUP_DIR"

cd "$DOTFILES_DIR"

for dir in */; do
    dir=${dir%/} # Remove trailing slash
    
    # Check if directory is in exclude list
    if [[ " ${EXCLUDE[@]} " =~ " ${dir} " ]]; then
        continue
    fi

    echo "Processing $dir..."

    # Proactive Backup Logic:
    # Find all files in the dotfile directory and check if they exist in $HOME
    # If a file exists and is NOT a symlink, move it to the backup directory.
    find "$dir" -type f | while read -r file; do
        # Calculate target path: remove the top-level directory name and prepend $HOME
        rel_path="${file#$dir/}"
        target="$HOME/$rel_path"
        
        if [[ -f "$target" || -L "$target" ]]; then
            if [[ ! -L "$target" ]]; then
                echo "  Backing up existing file: $rel_path"
                mkdir -p "$(dirname "$BACKUP_DIR/$rel_path")"
                mv "$target" "$BACKUP_DIR/$rel_path"
            fi
            # If it IS a symlink, stow -R will handle it by replacing it.
        fi
    done

    # Run stow
    stow -v -R -t "$HOME" "$dir"
done

echo "Stowing complete."
