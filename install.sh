#!/bin/bash

# install.sh - Main entry point for dotfiles installation

set -e

SCRIPTS_DIR="$(dirname "$(realpath "$0")")/scripts"
DOTFILES_DIR="$(dirname "$(realpath "$0")")"

# Ensure scripts are executable
chmod +x "$SCRIPTS_DIR"/*.sh

echo "=========================================="
echo "   Arch Linux Dotfiles Installation System    "
echo "=========================================="
echo ""
echo "Please select an installation mode:"
echo "1) Full Install (Packages, Services, Stow)"
echo "2) Update Only (Packages, Stow)"
echo "3) System Only (Sudo-level Services)"
echo "4) GPU Driver Setup (Optional)"
echo "5) Audio Setup (Set default output)"
echo "6) Timezone Setup (Set system timezone)"
echo "7) Repair (Restore missing/modified dotfiles)"
echo "8) Exit"
echo ""
read -p "Selection [1-8]: " choice

case $choice in
    1|2)
        # Say up front if this session's Hyprland already cannot load plugins
        # (its binary was replaced by an earlier package upgrade), and check
        # again right after install_packages.sh, which is what actually
        # performs the upgrade. See scripts/hyprland_restart_check.sh.
        HYPRLAND_RESTART_NEEDED=0
        if [ -x "$SCRIPTS_DIR/hyprland_restart_check.sh" ]; then
            "$SCRIPTS_DIR/hyprland_restart_check.sh" || HYPRLAND_RESTART_NEEDED=1
        fi

        # Safety check: If any key directory is empty, trigger a repair first
        if [[ ! -f "$SCRIPTS_DIR/install_packages.sh" ]] || [[ -z "$(ls -A "$DOTFILES_DIR/hypr" 2>/dev/null)" ]]; then
            echo "Warning: Repository looks incomplete. Running auto-repair..."
            git -C "$DOTFILES_DIR" restore .
            git -C "$DOTFILES_DIR" checkout .
        fi

        if [[ $choice -eq 1 ]]; then
            echo "Starting Full Installation..."
            sudo -v # Early sudo elevation
            # Keep-alive sudo
            while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

            echo "[1/9] Installing packages..."
            "$SCRIPTS_DIR/install_packages.sh"
            # This step may have just upgraded hyprland; report the restart
            # requirement as soon as it becomes true (once is enough).
            if [ "$HYPRLAND_RESTART_NEEDED" = 0 ] && [ -x "$SCRIPTS_DIR/hyprland_restart_check.sh" ]; then
                "$SCRIPTS_DIR/hyprland_restart_check.sh" || HYPRLAND_RESTART_NEEDED=1
            fi
            # Before stowing: the packages and services this removes were replaced
            # by hayami-shell, and stow cannot unlink a package that no longer
            # exists in the repo, so this clears its symlinks out of $HOME first.
            # A no-op on a machine that has already migrated.
            echo "[2/9] Retiring the pre-Quickshell stack (if present)..."
            "$SCRIPTS_DIR/retire_legacy_stack.sh" || echo "WARNING: legacy stack retirement reported a problem, continuing..."
            echo "[3/9] Stowing dotfile configs..."
            "$SCRIPTS_DIR/stow_configs.sh"
            echo "[4/9] Setting default file type handlers..."
            "$SCRIPTS_DIR/setup_mime_defaults.sh" || echo "WARNING: file type defaults reported a problem, continuing..."
            echo "[5/9] Setting up GPU drivers..."
            "$SCRIPTS_DIR/setup_gpu.sh" || echo "WARNING: GPU driver setup failed, continuing with remaining steps..."
            echo "[6/9] Configuring system services..."
            "$SCRIPTS_DIR/setup_services.sh"
            echo "[7/9] Setting up timezone..."
            "$SCRIPTS_DIR/setup_timezone.sh"
            echo "[8/9] Restarting the launcher and shell..."
            "$SCRIPTS_DIR/restart_launcher.sh"
            echo "[9/9] Enabling Hyprland plugins..."
            "$SCRIPTS_DIR/setup_plugins.sh"
        else
            echo "Starting Update..."
            echo "[1/6] Installing/updating packages..."
            "$SCRIPTS_DIR/install_packages.sh"
            # install_packages.sh may upgrade hyprland mid-session; if so, its
            # plugins cannot load until the compositor restarts.
            if [ "$HYPRLAND_RESTART_NEEDED" = 0 ] && [ -x "$SCRIPTS_DIR/hyprland_restart_check.sh" ]; then
                "$SCRIPTS_DIR/hyprland_restart_check.sh" || HYPRLAND_RESTART_NEEDED=1
            fi
            # See the note in the full install: this is what converts a machine
            # still running waybar/swaync/swayosd/walker to hayami-shell alone.
            echo "[2/6] Retiring the pre-Quickshell stack (if present)..."
            "$SCRIPTS_DIR/retire_legacy_stack.sh" || echo "WARNING: legacy stack retirement reported a problem, continuing..."
            echo "[3/6] Stowing dotfile configs..."
            "$SCRIPTS_DIR/stow_configs.sh"
            echo "[4/6] Setting default file type handlers..."
            "$SCRIPTS_DIR/setup_mime_defaults.sh" || echo "WARNING: file type defaults reported a problem, continuing..."
            echo "[5/6] Restarting the launcher and shell..."
            "$SCRIPTS_DIR/restart_launcher.sh"
            echo "[6/6] Enabling Hyprland plugins..."
            "$SCRIPTS_DIR/setup_plugins.sh"
        fi
        ;;
    3)
        echo "Starting System Configuration..."
        sudo -v
        "$SCRIPTS_DIR/setup_services.sh"
        ;;
    4)
        echo "Starting GPU Driver Setup..."
        "$SCRIPTS_DIR/setup_gpu.sh"
        ;;
    5)
        "$SCRIPTS_DIR/setup_audio.sh"
        ;;
    6)
        "$SCRIPTS_DIR/setup_timezone.sh"
        ;;
    7)
        echo "Repairing dotfiles repository (Hard Reset)..."
        # Force restore even if changes are staged
        git -C "$DOTFILES_DIR" fetch origin main
        git -C "$DOTFILES_DIR" reset --hard origin/main
        git -C "$DOTFILES_DIR" clean -fd
        echo "Repair complete. Source files have been restored to match GitHub."
        ;;
    8)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid selection. Exiting."
        exit 1
        ;;
esac

echo ""
if [ "${HYPRLAND_RESTART_NEEDED:-0}" = 1 ]; then
    echo "Hyprland plugins are not loaded yet: log out or reboot to load them."
    echo ""
fi
echo "=========================================="
echo "   Installation Complete"
echo "=========================================="
echo ""
echo "If system hooks or bootloaders were changed, please reboot."
