#!/bin/bash

# setup_audio.sh - Interactively set the default Pipewire audio output

echo "=========================================="
echo "      Audio Output Configuration         "
echo "=========================================="

# Check if wpctl is available
if ! command -v wpctl &> /dev/null; then
    echo "Error: wpctl (wireplumber) not found. Please ensure pipewire and wireplumber are installed."
    exit 1
fi

echo "Scanning for audio output devices..."
echo ""

# Extract sinks from wpctl status
# We look for the "Audio -> Sinks" section
sinks=$(wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -E '^[[:space:]]*[0-9]+\.')

if [[ -z "$sinks" ]]; then
    echo "No audio output devices found."
    exit 1
fi

echo "Available Audio Outputs:"
echo "$sinks" | sed 's/^[[:space:]]*//'
echo ""

read -p "Enter the ID of the device you want as default: " sink_id

if [[ ! "$sink_id" =~ ^[0-9]+$ ]]; then
    echo "Invalid ID. Please enter a numeric ID."
    exit 1
fi

echo "Setting device $sink_id as default..."
if wpctl set-default "$sink_id"; then
    echo "Success! Default audio output updated."
else
    echo "Failed to set default audio output."
    exit 1
fi
