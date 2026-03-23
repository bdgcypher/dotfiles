#!/bin/bash

# Omarchy to Custom Arch Installation Script
# This script installs all necessary packages and stows configurations.

set -e

SCRIPTS_DIR="$(dirname "$(realpath "$0")")/scripts"

echo "Starting installation..."

# Make scripts executable
chmod +x "$SCRIPTS_DIR"/*.sh

# Run package installation
echo "--- Installing Packages ---"
"$SCRIPTS_DIR/install_packages.sh"

# Run services setup
echo "--- Setting Up Services ---"
"$SCRIPTS_DIR/setup_services.sh"

# Run configuration stowing
echo "--- Stowing Configurations ---"
"$SCRIPTS_DIR/stow_configs.sh"

echo "Installation finished! Please reboot to apply all changes."
