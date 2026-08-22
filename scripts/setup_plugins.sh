#!/bin/bash

# setup_plugins.sh - Install and enable Hyprland plugins via hyprpm

echo "Setting up Hyprland plugins (hyprpm)..."

if ! command -v hyprpm &> /dev/null; then
    echo "  hyprpm not found. Skipping plugin setup."
    exit 0
fi

REPO_URL="https://github.com/yayuuu/hyprland-scroll-overview.git"
PLUGIN_NAME="scrolloverview"

# Headers must be compiled before `add` (hyprpm rejects add with outdated headers)
echo "  Updating hyprpm headers..."
hyprpm update || echo "  WARNING: hyprpm update failed."

# Add the plugin repo if not already present
if ! hyprpm list 2>/dev/null | grep -qi "$PLUGIN_NAME"; then
    echo "  Adding $PLUGIN_NAME plugin..."
    hyprpm add "$REPO_URL" || echo "  WARNING: hyprpm add failed."
fi

# Compile the plugin against the current Hyprland
echo "  Building plugins..."
hyprpm update || echo "  WARNING: hyprpm update failed."

# Enable it
echo "  Enabling $PLUGIN_NAME..."
hyprpm enable "$PLUGIN_NAME" || echo "  WARNING: hyprpm enable failed."

echo "Hyprland plugin setup complete."
