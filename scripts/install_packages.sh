#!/bin/bash

# install_packages.sh - Robustly installs official and AUR packages

set -e

DOTFILES_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
PKGLIST="$DOTFILES_DIR/pkglist.txt"
AUR_PKGLIST="$DOTFILES_DIR/aur_pkglist.txt"

# Cache sudo once so subsequent sudo calls don't prompt repeatedly.
# Handles both install.sh (sudo already cached) and standalone runs.
if sudo -n true 2>/dev/null; then
    echo "sudo already cached."
else
    echo "Please enter sudo password (will be cached for package install):"
    sudo -v
fi

echo "Checking for AUR helper (yay)..."
if ! command -v yay &> /dev/null; then
    echo "Installing yay..."
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd -
fi

# Ensure multilib is enabled
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "Enabling multilib repository..."
    sudo sed -i '/#\[multilib\]/,/Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
    sudo pacman -Syu --noconfirm
fi

# Aesthetic and Performance enhancements for pacman
echo "Configuring pacman aesthetics (ILoveCandy)..."
# Enable Color
sudo sed -i 's/^#Color$/Color/' /etc/pacman.conf
# Add ILoveCandy if not present
if ! grep -q "^ILoveCandy" /etc/pacman.conf; then
    sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
fi
# Enable ParallelDownloads (default to 5 if not set)
sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
# Ignore debug packages to avoid build-id conflicts between packages like vesktop-debug and bitwarden-bin-debug
if ! grep -q '^IgnorePkg' /etc/pacman.conf; then
    sudo sed -i '/^Color/a IgnorePkg = *-debug' /etc/pacman.conf
fi

echo "Updating official repositories..."
sudo pacman -Syu --noconfirm

# Ensure headers for all installed kernels are present AFTER update
# This prevents DKMS build failures by ensuring headers match the updated kernel
echo "Ensuring matching kernel headers are installed..."
# Match linux, linux-lts, linux-zen, linux-hardened, linux-rt, etc.
# We exclude things like linux-firmware or linux-api-headers by checking for the existence of the -headers package.
INSTALLED_KERNELS=$(pacman -Qq | grep -E "^linux(-[a-z0-9]+)?$" | grep -vE "-(firmware|api-headers|docs|pts)" || true)
if [ -n "$INSTALLED_KERNELS" ]; then
    for k in $INSTALLED_KERNELS; do
        if pacman -Si "${k}-headers" &>/dev/null; then
            echo "Installing headers for $k..."
            sudo pacman -S --needed --noconfirm "${k}-headers"
        fi
    done
fi

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

# Aion: Google Calendar TUI (built from source, release binary is incomplete)
echo "Installing Aion (Google Calendar TUI)..."
if ! command -v aion &> /dev/null; then
    if command -v bun &> /dev/null; then
        echo "  Cloning and building Aion..."
        git clone --depth 1 https://github.com/semos-labs/aion.git /tmp/aion-build
        cd /tmp/aion-build && bun install && bun run build
        install -Dm755 /tmp/aion-build/dist/aion "$HOME/.local/bin/aion"
        cd /tmp && rm -rf aion-build
        echo "  Aion installed to ~/.local/bin/aion"
    else
        echo "  Warning: bun not found. Install bun first, then build Aion manually."
        echo "  See: https://github.com/semos-labs/aion"
    fi
else
    echo "  Aion already installed."
fi

# Voxtype: systemd daemon setup
echo "Setting up Voxtype systemd daemon..."
if command -v voxtype &> /dev/null; then
    voxtype setup systemd 2>/dev/null || echo "  Warning: voxtype setup systemd failed. Run manually: voxtype setup systemd"
else
    echo "  Voxtype not found, skipping systemd setup."
fi

# Flatpak: Mouseless
echo "Setting up Mouseless via Flatpak..."
if command -v flatpak &> /dev/null; then
    # Ensure flathub is available for GNOME runtime dependency
    flatpak remote-add --user --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    flatpak remote-add --user --if-not-exists sonuscape \
        https://dl.sonuscape.net/flatpak/sonuscape.flatpakrepo 2>/dev/null || true
    flatpak install --user -y net.sonuscape.mouseless || \
        echo "Warning: Mouseless flatpak install failed. Run manually: flatpak install --user net.sonuscape.mouseless"
    # Copy Mouseless config into flatpak app data
    CONFIG_SRC="$DOTFILES_DIR/mouseless/config.yaml"
    CONFIG_DST="$HOME/.var/app/net.sonuscape.mouseless/data/mouseless/configs/config.yaml"
    if [ -f "$CONFIG_SRC" ]; then
        mkdir -p "$(dirname "$CONFIG_DST")"
        cp "$CONFIG_SRC" "$CONFIG_DST"
        echo "Mouseless config installed."
    fi
    # Copy Mouseless presets into flatpak app data (presets live in a
    # sibling 'presets' directory, not 'configs')
    PRESETS_SRC="$DOTFILES_DIR/mouseless/presets.yaml"
    PRESETS_DST="$HOME/.var/app/net.sonuscape.mouseless/data/mouseless/presets/presets.yaml"
    if [ -f "$PRESETS_SRC" ]; then
        mkdir -p "$(dirname "$PRESETS_DST")"
        cp "$PRESETS_SRC" "$PRESETS_DST"
        echo "Mouseless presets installed."
    fi
else
    echo "Warning: flatpak not found. Skipping Mouseless install."
fi
