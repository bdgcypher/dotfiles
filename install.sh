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
echo "4) Audio Setup (Set default output)"
echo "5) Timezone Setup (Set system timezone)"
echo "6) Exit"
echo ""
read -p "Selection [1-6]: " choice

case $choice in
    1)
        echo "Starting Full Installation..."
        sudo -v # Early sudo elevation
        # Keep-alive sudo
        while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        
        "$SCRIPTS_DIR/install_packages.sh"
        "$SCRIPTS_DIR/setup_gpu.sh"
        "$SCRIPTS_DIR/setup_services.sh"
        "$SCRIPTS_DIR/setup_timezone.sh"
        "$SCRIPTS_DIR/stow_configs.sh"
        ;;
    2)
        echo "Starting Update..."
        "$SCRIPTS_DIR/install_packages.sh"
        "$SCRIPTS_DIR/setup_gpu.sh"
        "$SCRIPTS_DIR/stow_configs.sh"
        ;;
    3)
        echo "Starting System Configuration..."
        sudo -v
        "$SCRIPTS_DIR/setup_services.sh"
        ;;
    4)
        "$SCRIPTS_DIR/setup_audio.sh"
        ;;
    5)
        "$SCRIPTS_DIR/setup_timezone.sh"
        ;;
    6)
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
