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
    # No upgrade here: the unconditional `pacman -Syu` below runs seconds later
    # and picks up the freshly enabled repository. Running it twice meant a
    # fresh machine downloaded and resolved the whole graph an extra time.
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

# ── the package lists ─────────────────────────────────────────────────────────
# Comments and blank lines are dropped so these files can be annotated without
# turning a note into a "package not found" warning.
WANTED=$(cat "$PKGLIST" "$AUR_PKGLIST" |
    grep -vE '^[[:space:]]*(#|$)' | sort -u)

if [ -z "$WANTED" ]; then
    echo "ERROR: no packages found in $PKGLIST / $AUR_PKGLIST" >&2
    exit 1
fi

# Split the list into "in a repository" and "AUR only" with one call.
#
# pacman -Slq lists every package the sync databases know about; comm against
# the wanted list splits it. This is the whole reason the two groups can be
# installed separately, and it costs a single ~0.5s query rather than a
# `pacman -Si` per package (~22ms each, which would be ~5s for 223 of them).
#
# Splitting matters because the two groups fail for completely different
# reasons. Repository packages are downloaded and unpacked, and essentially
# never fail. AUR packages are built from source against a rolling set of
# dependencies, and a single one of them failing (a deleted upstream repo, a
# new required dependency) is routine. Keeping them in one transaction meant
# that one routine AUR failure took all 194 repository packages down with it
# and triggered the fallback below.
REPO_SET=$(pacman -Slq 2>/dev/null | sort -u)
mapfile -t REPO_PKGS < <(comm -12 <(printf '%s\n' "$REPO_SET") <(printf '%s\n' "$WANTED"))
mapfile -t AUR_PKGS  < <(comm -13 <(printf '%s\n' "$REPO_SET") <(printf '%s\n' "$WANTED"))

# ── installing them ───────────────────────────────────────────────────────────
# One transaction per group, and on failure a retry that is bounded by the size
# of the group that actually failed.
#
# The fallback used to re-run every package in the combined list, one `yay -S`
# each, which turned any single failure into a very long install: 223 separate
# invocations, each re-syncing the databases and re-resolving the graph, nearly
# all of them for packages that were already installed. Now the worst case is
# one retry loop over the 29 AUR packages, and the repository group is not
# retried at all unless the repository group is what failed.
#
# A group that cannot be fully installed is reported and the install continues,
# exactly as before: an optional AUR package failing to build must not abort
# the whole run.
INSTALL_FAILURES=()

install_group() {
    local -n _pkgs=$1
    local label=$2
    local pkg
    local -a failed=()

    [ "${#_pkgs[@]}" -eq 0 ] && return 0

    echo "Installing ${#_pkgs[@]} ${label} packages..."

    # The bulk attempt is an `if` condition rather than a `&&` chain so that a
    # failure here is an ordinary false, never a `set -e` exit: this script runs
    # with `set -e` and a failed package must fall through to the retry below.
    if [ "$label" = "repository" ]; then
        # pacman, not yay: every one of these is in the sync databases, so yay's
        # AUR machinery is pure overhead on the largest group.
        if sudo pacman -S --needed --noconfirm "${_pkgs[@]}"; then
            return 0
        fi
    else
        if yay -S --needed --noconfirm "${_pkgs[@]}"; then
            return 0
        fi
    fi

    echo "  Bulk install of ${label} packages failed; retrying them one at a time..."
    for pkg in "${_pkgs[@]}"; do
        echo "    $pkg"
        if [ "$label" = "repository" ]; then
            if sudo pacman -S --needed --noconfirm "$pkg"; then
                echo "      ok"
            else
                echo "      FAILED"
                failed+=("$pkg")
            fi
        else
            if yay -S --needed --noconfirm "$pkg"; then
                echo "      ok"
            else
                echo "      FAILED"
                failed+=("$pkg")
            fi
        fi
    done

    if [ "${#failed[@]}" -gt 0 ]; then
        INSTALL_FAILURES+=("${label}: ${failed[*]}")
    fi
    return 0
}

install_group REPO_PKGS repository
install_group AUR_PKGS AUR

if [ "${#INSTALL_FAILURES[@]}" -gt 0 ]; then
    echo ""
    echo "Warning: some packages could not be installed:"
    for line in "${INSTALL_FAILURES[@]}"; do
        echo "  - $line"
    done
    echo "  Re-run 'yay -S <package>' for any of these to retry."
    echo ""
fi

echo "Package installation complete."

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
