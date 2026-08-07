#!/bin/bash

# install.sh - Main entry point for dotfiles installation

set -e

SCRIPTS_DIR="$(dirname "$(realpath "$0")")/scripts"

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
            
            "$SCRIPTS_DIR/install_packages.sh"
            "$SCRIPTS_DIR/setup_gpu.sh"
            "$SCRIPTS_DIR/setup_services.sh"
            "$SCRIPTS_DIR/setup_timezone.sh"
            "$SCRIPTS_DIR/stow_configs.sh"
        else
            echo "Starting Update..."
            "$SCRIPTS_DIR/install_packages.sh"
            "$SCRIPTS_DIR/stow_configs.sh"
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
echo "Done! If system hooks or bootloaders were changed, please reboot."
