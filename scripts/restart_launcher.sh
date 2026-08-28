#!/bin/bash

# restart_launcher.sh - Restart elephant and walker so menu/config changes are live.

set -e

# Elephant serves all walker menus — restart so new/changed menus load.
if systemctl --user restart elephant.service 2>/dev/null; then
    echo "Elephant service restarted."
else
    echo "Note: Could not restart elephant.service (may need to run after login)."
fi

# Walker must run with --gapplication-service so it stays resident and menus
# load instantly. Kill any running instance first, then relaunch.
if command -v walker &> /dev/null; then
    pkill -x walker 2>/dev/null || true
    # Wait for the old instance to fully exit so it releases its D-Bus
    # service name — otherwise the new instance exits immediately.
    for _ in $(seq 1 20); do
        pgrep -x walker >/dev/null || break
        sleep 0.1
    done
    walker --gapplication-service >/dev/null 2>&1 &
    disown
    echo "Walker relaunched with --gapplication-service."
else
    echo "Note: walker not found, skipping launch."
fi
