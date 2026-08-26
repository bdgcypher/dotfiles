#!/bin/bash

# setup_plugins.sh - Install and enable Hyprland plugins via hyprpm

echo "Setting up Hyprland plugins (hyprpm)..."

if ! command -v hyprpm &> /dev/null; then
    echo "  hyprpm not found. Skipping plugin setup."
    exit 0
fi

# Cache sudo once to avoid multiple password prompts during hyprpm builds
if sudo -n true 2>/dev/null; then
    echo "  sudo already cached."
else
    echo "  Please enter sudo password (will be cached for plugin setup):"
    sudo -v
fi

REPO_URL="https://github.com/yayuuu/hyprland-scroll-overview.git"
PLUGIN_NAME="scrolloverview"

# Check if plugin is already enabled
if hyprpm list 2>/dev/null | grep -qi "$PLUGIN_NAME" && hyprpm list 2>/dev/null | grep -A1 "$PLUGIN_NAME" | grep -qi "enabled"; then
    echo "  $PLUGIN_NAME is already enabled. Checking for updates..."
    yes | hyprpm update || echo "  WARNING: hyprpm update failed."
    echo "Hyprland plugin setup complete."
    exit 0
fi

# Headers must be compiled before `add` (hyprpm rejects add with outdated headers)
echo "  Updating hyprpm headers..."
yes | hyprpm update || echo "  WARNING: hyprpm update failed."

# Add the plugin repo if not already present
if ! hyprpm list 2>/dev/null | grep -qi "$PLUGIN_NAME"; then
    echo "  Adding $PLUGIN_NAME plugin..."
    yes | hyprpm add "$REPO_URL" || echo "  WARNING: hyprpm add failed."
fi

# Compile the plugin against the current Hyprland
echo "  Building plugins..."
yes | hyprpm update || echo "  WARNING: hyprpm update failed."

# Enable it
echo "  Enabling $PLUGIN_NAME..."
yes | hyprpm enable "$PLUGIN_NAME" || echo "  WARNING: hyprpm enable failed."

echo "Hyprland plugin setup complete."
