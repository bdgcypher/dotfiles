#!/bin/bash

# setup_gpu.sh - Detects GPU and installs appropriate drivers for Arch Linux

set -e

echo "Detecting GPU..."

# Detect GPU type
if lspci | grep -qi "nvidia"; then
    GPU_TYPE="nvidia"
    DRIVERS=("nvidia" "nvidia-utils" "nvidia-settings" "lib32-nvidia-utils")
elif lspci | grep -qi "amd"; then
    GPU_TYPE="amd"
    DRIVERS=("xf86-video-amdgpu" "vulkan-radeon" "lib32-vulkan-radeon" "lib32-mesa")
elif lspci | grep -qi "intel"; then
    GPU_TYPE="intel"
    DRIVERS=("mesa" "vulkan-intel" "lib32-mesa" "lib32-vulkan-intel" "intel-media-driver")
else
    GPU_TYPE="unknown"
fi

echo "GPU detected: $GPU_TYPE"

if [ "$GPU_TYPE" != "unknown" ]; then
    echo "Installing drivers for $GPU_TYPE: ${DRIVERS[*]}"
    # Use yay as it is already assumed to be installed by install_packages.sh
    yay -S --needed --noconfirm "${DRIVERS[@]}"
else
    echo "No matching GPU found or GPU type is unknown. Skipping driver installation."
fi
