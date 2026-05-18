#!/bin/bash

# stow_configs.sh - Symlinks dotfiles using GNU Stow with robust conflict handling

set -e

DOTFILES_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
BACKUP_DIR="$HOME/.dotfiles.bak/$(date +%Y%m%d_%H%M%S)"

# List of folders to exclude from stowing
EXCLUDE=("scripts" ".git" "system" "yay" "gh" "bitwarden" "mozilla")

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

    # Robust Conflict Handling Logic:
    # We only look for potential conflicts in the HOME directory.
    # We NEVER modify files inside the $DOTFILES_DIR itself.
    find "$dir" -type f | while read -r file; do
        rel_path="${file#$dir/}"
        target="$HOME/$rel_path"
        
        # Security Guard: Ensure we never try to "backup" the source file itself
        if [[ "$(realpath "$file")" == "$(realpath "$target")" ]]; then
            echo "  Skipping: Source and target are the same ($rel_path)"
            continue
        fi

        if [[ -L "$target" ]]; then
            # If it's a symlink (broken or working), remove it to let stow recreate it
            echo "  Removing existing symlink in HOME: $rel_path"
            rm "$target"
        elif [[ -f "$target" ]]; then
            # If it's a real file in HOME, back it up
            echo "  Backing up existing file in HOME: $rel_path"
            mkdir -p "$(dirname "$BACKUP_DIR/$rel_path")"
            mv "$target" "$BACKUP_DIR/$rel_path"
        fi
    done

    # Run stow with restow and verbose flags
    stow -v -R -t "$HOME" "$dir"
done

echo "Stowing complete."
