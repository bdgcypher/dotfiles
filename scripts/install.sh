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

            echo "[1/7] Installing packages..."
            "$SCRIPTS_DIR/install_packages.sh"
            echo "[2/7] Stowing dotfile configs..."
            "$SCRIPTS_DIR/stow_configs.sh"
            echo "[3/7] Setting up GPU drivers..."
            "$SCRIPTS_DIR/setup_gpu.sh" || echo "WARNING: GPU driver setup failed, continuing with remaining steps..."
            echo "[4/7] Configuring system services..."
            "$SCRIPTS_DIR/setup_services.sh"
            echo "[5/7] Setting up timezone..."
            "$SCRIPTS_DIR/setup_timezone.sh"
            echo "[6/7] Restarting launcher services..."
            "$SCRIPTS_DIR/restart_launcher.sh"
            echo "[7/7] Enabling Hyprland plugins..."
            "$SCRIPTS_DIR/setup_plugins.sh"
        else
            echo "Starting Update..."
            echo "[1/4] Installing/updating packages..."
            "$SCRIPTS_DIR/install_packages.sh"
            echo "[2/4] Stowing dotfile configs..."
            "$SCRIPTS_DIR/stow_configs.sh"
            echo "[3/4] Restarting launcher services..."
            "$SCRIPTS_DIR/restart_launcher.sh"
            echo "[4/4] Enabling Hyprland plugins..."
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
echo "=========================================="
echo "   Installation Complete"
echo "=========================================="
echo ""
echo "If system hooks or bootloaders were changed, please reboot."
