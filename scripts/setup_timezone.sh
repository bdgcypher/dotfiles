#!/bin/bash

# setup_timezone.sh - Interactively set the system timezone

echo "=========================================="
echo "      Timezone Configuration             "
echo "=========================================="

# Check if timedatectl is available
if ! command -v timedatectl &> /dev/null; then
    echo "Error: timedatectl not found. This script requires systemd."
    exit 1
fi

CURRENT_TZ=$(timedatectl show --property=Timezone --value)
echo "Current timezone: $CURRENT_TZ"
echo ""

# Suggest common timezones or let the user type one
echo "Enter the timezone you want to set (e.g., America/Denver, UTC, etc.)"
echo "Type 'list' to see all available timezones."
read -p "Timezone [$CURRENT_TZ]: " user_tz

if [[ -z "$user_tz" ]]; then
    user_tz=$CURRENT_TZ
fi

if [[ "$user_tz" == "list" ]]; then
    timedatectl list-timezones | less
    read -p "Enter the timezone from the list: " user_tz
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
