#!/bin/bash

# setup_gpu.sh - Detects GPU and installs appropriate drivers for Arch Linux

set -e

echo "Detecting GPU..."

# Detect GPU type
if lspci | grep -qi "nvidia"; then
    GPU_TYPE="nvidia"
    echo "NVIDIA GPU detected."
    
    # Check if any NVIDIA driver package is already installed (standard, dkms, lts, or open variants)
    # We check for packages starting with 'nvidia' but exclude utilities and libraries
    if pacman -Qq | grep -E "^nvidia(-[0-9]+xx)?(-(dkms|lts|open|zen|hardened))?(-dkms)?$" | grep -qvE "-(utils|settings|xconfig|prime|lib32|vulkan|vaapi)" | grep -q .; then
        echo "An NVIDIA driver package is already installed. Skipping driver installation to avoid conflicts."
        # We still ensure common utilities are present if not already
        DRIVERS=("nvidia-settings" "lib32-nvidia-utils")
    else
        echo "No NVIDIA drivers detected. Preparing installation..."
        # If the user has only the standard 'linux' kernel, 'nvidia' is a safe pre-built choice.
        # Otherwise, 'nvidia-dkms' is more robust for multiple/custom kernels.
        if pacman -Qq | grep -E "^linux$" > /dev/null && ! pacman -Qq | grep -E "^linux-(lts|zen|hardened)$" > /dev/null; then
            echo "Standard 'linux' kernel detected. Using 'nvidia' pre-built drivers."
            DRIVERS=("nvidia" "nvidia-utils" "nvidia-settings" "lib32-nvidia-utils")
        else
            echo "Multiple or custom kernels detected. Using 'nvidia-dkms' for maximum compatibility."
            DRIVERS=("nvidia-dkms" "nvidia-utils" "nvidia-settings" "lib32-nvidia-utils")
        fi
    fi
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
