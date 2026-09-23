#!/bin/bash

# setup_plugins.sh - Install and enable Hyprland plugins via hyprpm

echo "Setting up Hyprland plugins (hyprpm)..."

# Cache sudo once to avoid multiple password prompts during hyprpm builds
if sudo -n true 2>/dev/null; then
    echo "  sudo already cached."
else
    echo "  Please enter sudo password (will be cached for plugin setup):"
    sudo -v
fi

# hyprpm used to ship inside the 'hyprland' package, but as of the 0.56
# split it is its own package and 'hyprland' only lists it as an optional
# dependency. Without it, plugin setup silently did nothing, so make sure
# it is actually present before continuing.
if ! command -v hyprpm &> /dev/null; then
    echo "  hyprpm not found. Installing the 'hyprpm' package..."
    if ! sudo pacman -S --needed --noconfirm hyprpm; then
        echo "  WARNING: Failed to install hyprpm. Skipping plugin setup."
        exit 0
    fi
fi

REPO_URL="https://github.com/yayuuu/hyprland-scroll-overview.git"
REPO_NAME="hyprland-scroll-overview"
PLUGIN_NAME="scrolloverview"
PLUGIN_SO="/var/cache/hyprpm/$(id -un)/$REPO_NAME/$PLUGIN_NAME.so"

# Is the plugin actually loaded in the running compositor?
#
# `hyprpm` prints "Loaded <plugin>" whenever it *asks* Hyprland to load it, so
# its output cannot be trusted as proof - ask Hyprland itself instead.
plugin_loaded() {
    hyprctl plugin list 2>/dev/null | grep -qi "$PLUGIN_NAME"
}

# A running Hyprland whose own binary has been replaced cannot load plugins at
# all. Upgrading hyprland while a session is live (which install.sh does, since
# install_packages.sh runs before this script) leaves the process pointing at a
# deleted file, and every load then fails with:
#
#   plugin crashed/threw in main: filesystem error: cannot make canonical path:
#   No such file or directory [/proc/self/exe]
#
# Nothing in this script can work around that - the session has to restart.
# hyprland_restart_check.sh (same directory) owns that diagnosis so install.sh
# and this script report it identically.
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Make sure the freshly built plugin ends up loaded, and explain clearly when it
# cannot be. Never returns non-zero in a way that aborts install.sh (`set -e`).
ensure_loaded() {
    hyprpm reload 2>&1 | sed 's/^/    /' || true

    if plugin_loaded; then
        echo "  $PLUGIN_NAME is loaded in the running session."
        return 0
    fi

    # hyprpm claimed success but Hyprland disagrees - surface Hyprland's reason.
    echo "  WARNING: $PLUGIN_NAME is NOT loaded in the running session."
    if [ -f "$PLUGIN_SO" ]; then
        local err
        err="$(hyprctl plugin load "$PLUGIN_SO" 2>&1 | head -3)"
        [ -n "$err" ] && echo "           Hyprland says: $err"
    fi

    # The shared check prints a full explanation when this session needs a
    # Hyprland restart; otherwise fall back to the usual retry advice. Its
    # output is captured first so it can be indented to match this block.
    local restart_msg=""
    if [ -x "$SCRIPT_DIR/hyprland_restart_check.sh" ]; then
        restart_msg="$("$SCRIPT_DIR/hyprland_restart_check.sh" 2>&1)" || true
    fi
    if [ -n "$restart_msg" ]; then
        # pad to this block's 11-space indent
        printf '%s\n' "$restart_msg" | sed 's/^/     /'
    else
        echo "           Retry with 'hyprpm reload'; if it keeps failing, check"
        echo "           'hyprpm list' for a failed build."
    fi

    echo "           Until it loads, Hyprland reports each plugin.$PLUGIN_NAME.* key"
    echo "           in hypr/.config/hypr/plugins.lua as an unknown config key."
    return 1
}

# Everything below stays best-effort: a plugin problem must never fail an install.
if hyprpm list 2>/dev/null | grep -qi "$PLUGIN_NAME"; then
    if hyprpm list 2>/dev/null | grep -A1 "$PLUGIN_NAME" | grep -qi "enabled"; then
        echo "  $PLUGIN_NAME is already enabled. Checking for updates..."
    else
        echo "  Enabling $PLUGIN_NAME..."
        yes | hyprpm enable "$PLUGIN_NAME" || echo "  WARNING: hyprpm enable failed."
    fi

    # Deliberately no -f: hyprpm already compares the running Hyprland version
    # and the repository state and only rebuilds when something actually
    # changed. Forcing it rebuilt the plugin - and unloaded it from the running
    # session - on every single install run. --force is kept as a retry.
    if ! yes | hyprpm update; then
        echo "  Update failed, retrying with --force..."
        yes | hyprpm update -f || echo "  WARNING: hyprpm update failed."
    fi

    if ensure_loaded; then
        echo "Hyprland plugin setup complete."
    else
        echo "Hyprland plugin setup incomplete - see the warning above."
    fi
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
if ! yes | hyprpm update; then
    echo "  Build failed, retrying with --force..."
    yes | hyprpm update -f || echo "  WARNING: hyprpm update failed."
fi

# Enable it
echo "  Enabling $PLUGIN_NAME..."
yes | hyprpm enable "$PLUGIN_NAME" || echo "  WARNING: hyprpm enable failed."

if ensure_loaded; then
    echo "Hyprland plugin setup complete."
else
    echo "Hyprland plugin setup incomplete - see the warning above."
fi
