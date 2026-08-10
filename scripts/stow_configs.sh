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
    if [[ " ${EXCLUDE[*]} " == *" $dir "* ]]; then
        continue
    fi

    echo "Processing $dir..."

    # Robust Conflict Handling Logic:
    # We only look for potential conflicts in the HOME directory.
    # We NEVER modify files inside the $DOTFILES_DIR itself.
    # Include both files and symlinks — stow packages may contain symlinks
    # (e.g., systemd .wants/ entries) that need conflict resolution too.
    find "$dir" \( -type f -o -type l \) | while read -r file; do
        rel_path="${file#$dir/}"
        target="$HOME/$rel_path"
        
        # 1. Identity Guard: If target IS the source file (via symlink or same path), 
        # then there is no conflict to resolve.
        if [[ -e "$target" ]] && [[ "$file" -ef "$target" ]]; then
            # Already correctly linked, skip to next file
            continue
        fi

        # 2. Link Guard: If it's a symlink in HOME, remove it so stow can manage it.
        # This handles broken links or links to older/other locations.
        if [[ -L "$target" ]]; then
            echo "  Removing existing symlink in HOME: $rel_path"
            rm "$target"
        # 3. Conflict Guard: If it's a REAL file in HOME, back it up.
        elif [[ -f "$target" ]]; then
            echo "  Backing up existing file in HOME: $rel_path"
            mkdir -p "$(dirname "$BACKUP_DIR/$rel_path")"
            mv "$target" "$BACKUP_DIR/$rel_path"
        fi
    done

    # Run stow with restow and verbose flags
    stow -v -R -t "$HOME" "$dir"
done

echo "Stowing complete."

# Enable Waybar systemd user service
if command -v waybar &> /dev/null && systemctl --user enable --now waybar.service 2>/dev/null; then
    echo "Waybar service enabled and started."
else
    echo "Note: Could not enable waybar.service (may need to run after login)."
fi

# Enable Voxtype systemd user service
if command -v voxtype &> /dev/null && systemctl --user enable --now voxtype.service 2>/dev/null; then
    echo "Voxtype service enabled and started."
elif command -v voxtype &> /dev/null; then
    echo "Note: Could not enable voxtype.service (may need to run after login)."
fi

# Re-enable Sunshine systemd user service (its .wants symlink gets cleaned
# up by conflict handling since it's excluded from stow via .stow-local-ignore)
if command -v sunshine &> /dev/null && systemctl --user enable --now app-dev.lizardbyte.app.Sunshine.service 2>/dev/null; then
    echo "Sunshine service enabled and started."
elif command -v sunshine &> /dev/null; then
    echo "Note: Could not enable Sunshine service (may need to run after login)."
fi
