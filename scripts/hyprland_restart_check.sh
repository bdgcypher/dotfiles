#!/bin/bash

# hyprland_restart_check.sh - Reports when the running Hyprland session cannot
# load plugins until it restarts.
#
# Why this exists: install.sh upgrades packages (install_packages.sh) and then
# configures Hyprland plugins (setup_plugins.sh) in the same live session.
# Hyprland resolves its own executable when it loads a plugin, so if the
# hyprland package was replaced while the session was running, every plugin
# load fails with:
#
#   plugin crashed/threw in main: filesystem error: cannot make canonical path:
#   No such file or directory [/proc/self/exe]
#
# `hyprpm` still prints "Loaded <plugin>", so the install looked successful
# while the plugin stayed absent and Hyprland reported every plugin.* key in
# the config as unknown. This check turns that confusing state into a clear
# "restart Hyprland" instruction.
#
# Exit codes: 0 = nothing to report, 1 = a Hyprland restart is required.

set -u

PID="$(pgrep -x Hyprland | head -1)"
[ -n "$PID" ] || exit 0

EXE="$(readlink "/proc/$PID/exe" 2>/dev/null || true)"
[ -n "$EXE" ] || exit 0

DELETED=0
case "$EXE" in
    *"(deleted)") DELETED=1 ;;
esac

# Package install time, from pacman's local database. The mtimes of the files
# in /usr/bin keep the *build* date, so they cannot be used for this.
PKG_DIR=""
for d in /var/lib/pacman/local/hyprland-[0-9]*/; do
    [ -d "$d" ] && PKG_DIR="$d"
done

PKG_VERSION=""
PKG_INSTALLED=0
if [ -n "$PKG_DIR" ]; then
    PKG_VERSION="$(basename "${PKG_DIR%/}")"
    PKG_INSTALLED="$(stat -c %Y "$PKG_DIR" 2>/dev/null || echo 0)"
fi

SESSION_START="$(stat -c %Y "/proc/$PID" 2>/dev/null || echo 0)"

UPGRADED_MID_SESSION=0
if [ "$SESSION_START" -gt 0 ] && [ "$PKG_INSTALLED" -gt "$SESSION_START" ]; then
    UPGRADED_MID_SESSION=1
fi

# Nothing to report: the compositor can load plugins normally.
[ "$DELETED" = 1 ] || [ "$UPGRADED_MID_SESSION" = 1 ] || exit 0

STARTED="$(ps -o lstart= -p "$PID" 2>/dev/null | sed 's/^ *//')"
[ -n "$STARTED" ] || STARTED="unknown"

echo "  ! A Hyprland restart is required before its plugins can load:"
if [ "$DELETED" = 1 ]; then
    echo "      the running compositor (pid ${PID}, started ${STARTED}) had its own"
    echo "      binary replaced by a package upgrade, so it cannot load plugins at all"
    echo "      this session - hyprpm reports success either way."
else
    echo "      ${PKG_VERSION:-hyprland} was installed after this session started"
    echo "      (pid ${PID}, started ${STARTED}), so plugins built for the version on"
    echo "      disk cannot load into the running compositor."
fi
if [ -n "$PKG_VERSION" ] && [ "$PKG_INSTALLED" -gt 0 ]; then
    echo "      installed: ${PKG_VERSION} at $(date -d "@$PKG_INSTALLED" '+%F %T' 2>/dev/null || echo 'unknown')"
fi
echo "      Log out or reboot to finish plugin setup; hyprpm reload then loads it,"
echo "      and 'hyprctl plugin list' / 'hyprctl configerrors' should come back clean."

exit 1
