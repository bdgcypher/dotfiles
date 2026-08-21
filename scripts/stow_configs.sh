#!/bin/bash

# stow_configs.sh - Symlinks dotfiles using GNU Stow with robust conflict handling

set -e

DOTFILES_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
BACKUP_DIR="$HOME/.dotfiles.bak/$(date +%Y%m%d_%H%M%S)"

# List of folders to exclude from stowing
# 'mouseless' is excluded because its files are copied into the flatpak app's
# data dir by install_packages.sh, not symlinked into $HOME.
EXCLUDE=("scripts" ".git" "system" "yay" "gh" "bitwarden" "mozilla" "mouseless")

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

# Post-stow: Create absolute symlinks for pywal cache themes, GTK theme, and wallpaper.
# These MUST be absolute because stow creates directory symlinks (e.g.,
# ~/.config/btop -> ~/.dotfiles/btop/.config/btop) which changes the physical
# path depth, causing relative symlinks (../../../.cache/wal/...) to resolve
# incorrectly through the .dotfiles tree instead of from $HOME.
echo "Creating pywal/theme absolute symlinks..."

PYWAL="$HOME/.cache/wal"

# btop
mkdir -p "$(dirname "$HOME/.config/btop/themes/current.theme")"
ln -sfn "$PYWAL/btop.theme"             "$HOME/.config/btop/themes/current.theme"
# cava
mkdir -p "$(dirname "$HOME/.config/cava/themes/pywal")"
ln -sfn "$PYWAL/colors-cava.conf"       "$HOME/.config/cava/themes/pywal"
# gazelle
mkdir -p "$(dirname "$HOME/.config/gazelle/theme.toml")"
ln -sfn "$PYWAL/colors-gazelle.toml"    "$HOME/.config/gazelle/theme.toml"
# kvantum
mkdir -p "$(dirname "$HOME/.config/Kvantum/pywal/pywal.kvconfig")"
ln -sfn "$PYWAL/pywal.kvconfig"         "$HOME/.config/Kvantum/pywal/pywal.kvconfig"
ln -sfn "$PYWAL/pywal.svg"              "$HOME/.config/Kvantum/pywal/pywal.svg"
# ghostty theme (loaded via `theme = pywal` in ghostty/config)
mkdir -p "$HOME/.config/ghostty/themes"
ln -sfn "$PYWAL/colors-ghostty.conf"    "$HOME/.config/ghostty/themes/pywal"
# wallpaper
mkdir -p "$(dirname "$HOME/.config/theme/current_wallpaper")"
ln -sfn "$HOME/Wallpapers/TN1.png"      "$HOME/.config/theme/current_wallpaper"
# GTK pywal theme. GTK3 gets a per-wallpaper theme with a color-hash suffix
# (adw-gtk3-pywal-<hash>) so running GTK3 apps hot-reload when the name
# changes; GTK4/libadwaita uses user gtk.css overrides. Build both now from the
# wal output so a fresh install is pywal-themed immediately; fall back to the
# repo template before the first wallpaper apply.
GTK_CSS_SRC="$PYWAL/colors-gtk.css"
if [ ! -f "$GTK_CSS_SRC" ]; then
    GTK_CSS_SRC="$DOTFILES_DIR/wal/.config/wal/templates/colors-gtk.css"
fi

# GTK3: adw-gtk3-pywal-<hash> theme (copy adw-gtk3-dark + append pywal colors)
GTK3_SRC_THEME="/usr/share/themes/adw-gtk3-dark"
GTK3_HASH=$(md5sum "$GTK_CSS_SRC" | cut -c1-8)
GTK3_THEME_DIR="$HOME/.themes/adw-gtk3-pywal-$GTK3_HASH"
if [ -d "$GTK3_SRC_THEME" ]; then
    rm -rf "$GTK3_THEME_DIR"
    cp -r "$GTK3_SRC_THEME" "$GTK3_THEME_DIR"
    cat "$GTK_CSS_SRC" >> "$GTK3_THEME_DIR/gtk-3.0/gtk.css"
    cat "$GTK_CSS_SRC" >> "$GTK3_THEME_DIR/gtk-3.0/gtk-dark.css"
    # Nemo: dim the sidebar places-treeview (icons + labels) to a secondary
    # tone. Added to BOTH files (dark mode loads gtk-dark.css).
    NEMO_CSS='.nemo-window .sidebar treeview.view.places-treeview { color: alpha(@sidebar_fg_color, 0.7); }'
    printf '%s\n' "$NEMO_CSS" >> "$GTK3_THEME_DIR/gtk-3.0/gtk.css"
    printf '%s\n' "$NEMO_CSS" >> "$GTK3_THEME_DIR/gtk-3.0/gtk-dark.css"
    # Nemo: mute the list-view text (name + detail columns) to match the
    # sidebar treatment. font-size cannot be set here — nemo pins a
    # zoom-scaled pango font on the cell renderers — but color is
    # CSS-reachable (verified live).
    NEMO_LIST_CSS='.nemo-window scrolledwindow.view treeview { color: alpha(@view_fg_color, 0.7); }'
    printf '%s\n' "$NEMO_LIST_CSS" >> "$GTK3_THEME_DIR/gtk-3.0/gtk.css"
    printf '%s\n' "$NEMO_LIST_CSS" >> "$GTK3_THEME_DIR/gtk-3.0/gtk-dark.css"
    # Nemo: column headers use adw-gtk3's 'font-size: smaller', which does not
    # scale with the list-view zoom level, so they look tiny next to the rows.
    NEMO_HEADER_CSS='.nemo-window treeview.view header button { font-size: 9pt; }'
    printf '%s\n' "$NEMO_HEADER_CSS" >> "$GTK3_THEME_DIR/gtk-3.0/gtk.css"
    printf '%s\n' "$NEMO_HEADER_CSS" >> "$GTK3_THEME_DIR/gtk-3.0/gtk-dark.css"
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-pywal-$GTK3_HASH"
    fi
fi

# GTK4: user css overrides
mkdir -p "$HOME/.config/gtk-4.0"
cp -f "$GTK_CSS_SRC" "$HOME/.config/gtk-4.0/gtk.css"
cp -f "$GTK_CSS_SRC" "$HOME/.config/gtk-4.0/gtk-dark.css"

# Nemo: list view at 'standard' zoom (32px thumbnails, normal text) and show
# the current path as a text entry instead of breadcrumb buttons.
if gsettings list-schemas 2>/dev/null | grep -qx 'org.nemo.list-view'; then
    gsettings set org.nemo.list-view default-zoom-level "smaller"
    gsettings set org.nemo.preferences show-location-entry true
fi

echo "Theme symlinks created."

# Enable Waybar systemd user service
if command -v waybar &> /dev/null && systemctl --user enable --now waybar.service 2>/dev/null; then
    echo "Waybar service enabled and started."
else
    echo "Note: Could not enable waybar.service (may need to run after login)."
fi

# Enable Syncthing systemd user service (preferred over Hyprland exec-once —
# starts at login, survives compositor restarts, and has built-in restart logic)
if command -v syncthing &> /dev/null && systemctl --user enable --now syncthing.service 2>/dev/null; then
    echo "Syncthing service enabled and started."
elif command -v syncthing &> /dev/null; then
    echo "Note: Could not enable syncthing.service (may need to run after login)."
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
