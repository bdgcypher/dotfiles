#!/bin/bash

# setup_timezone.sh - Interactively set the system timezone

echo "=========================================="
echo "      Timezone Configuration             "
echo "=========================================="

# Cache sudo once so subsequent sudo calls don't prompt repeatedly.
if sudo -n true 2>/dev/null; then
    echo "sudo already cached."
else
    echo "Please enter sudo password (will be cached for timezone setup):"
    sudo -v
fi

# Check if timedatectl is available
if ! command -v timedatectl &> /dev/null; then
    echo "Error: timedatectl not found. This script requires systemd."
    exit 1
fi

CURRENT_TZ=$(timedatectl show --property=Timezone --value)
echo "Current timezone: $CURRENT_TZ"
echo ""

# Preferred zone for this setup, used whenever the prompt is not answered. A
# fresh install typically still sits on UTC, so falling back to the *system*
# value would quietly leave the clock hours off. Anything the user actually types
# always wins.
DEFAULT_TZ="America/Denver"
if [[ ! -e "/usr/share/zoneinfo/$DEFAULT_TZ" ]]; then
    echo "Warning: $DEFAULT_TZ not found in zoneinfo, using the system timezone as the fallback."
    DEFAULT_TZ="$CURRENT_TZ"
fi

# Suggest common timezones or let the user type one
echo "Timezone (e.g., America/Denver, UTC, etc.)"
echo "Type 'list' to see all available timezones or 'Enter' to accept default ($DEFAULT_TZ)."

# 10 second timeout: the prompt you have to sit through is a prompt that will
# eventually be answered with whatever key was nearest.
#
# It also makes this script safe to run without a terminal. `read` on a non-TTY
# hits EOF and returns immediately instead of blocking forever, so an unattended
# install no longer hangs here.
read -t 10 -p "> " user_tz
read_status=$?
if [ "$read_status" -ne 0 ]; then
    # 128+ means the timeout expired, 1 means EOF (no TTY). Either way there is
    # nothing usable to work with, so discard any partial input.
    if [ "$read_status" -gt 128 ]; then
        echo ""
        echo "No input within 10s - using $DEFAULT_TZ."
    else
        echo "No interactive input available - using $DEFAULT_TZ."
    fi
    user_tz=""
fi

# Empty input, a bare Enter, and a timeout all mean "no answer given".
if [[ -z "$user_tz" ]]; then
    user_tz=$DEFAULT_TZ
fi

if [[ "$user_tz" == "list" ]]; then
    timedatectl list-timezones | less
    read -t 10 -p "Enter the timezone from the list: " user_tz
    list_status=$?
    if [ "$list_status" -ne 0 ]; then
        echo ""
        user_tz=""
    fi
    if [[ -z "$user_tz" ]]; then
        user_tz=$DEFAULT_TZ
    fi
fi

echo "Setting timezone to $user_tz..."
if sudo timedatectl set-timezone "$user_tz"; then
    echo "Success! Timezone updated."
    # Also enable NTP
    sudo timedatectl set-ntp true
    echo "Network time synchronization (NTP) enabled."
else
    echo "Failed to set timezone. Please ensure you entered a valid timezone string."
    exit 1
fi
