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
    INSTALLED_DRIVER=$(pacman -Qq | grep -E -- "^nvidia(-[0-9]+xx)?(-(dkms|lts|open|zen|hardened))?(-dkms)?$" | grep -vE -- "-(utils|settings|xconfig|prime|lib32|vulkan|vaapi)" || true)

    if [ -n "$INSTALLED_DRIVER" ]; then
        # Detect if this is a legacy AUR driver (e.g. nvidia-525xx-dkms)
        if echo "$INSTALLED_DRIVER" | grep -qE "^nvidia-[0-9]+xx"; then
            echo "Legacy AUR NVIDIA driver detected: $INSTALLED_DRIVER"
            echo "Your GTX 1660 (Turing) supports the current official driver. Replacing..."

            # Remove all legacy NVIDIA AUR packages
            LEGACY_PACKAGES=$(pacman -Qq | grep -E "^nvidia-[0-9]+xx" || true)
            if [ -n "$LEGACY_PACKAGES" ]; then
                echo "Removing legacy packages: $LEGACY_PACKAGES"
                sudo pacman -Rdd --noconfirm $LEGACY_PACKAGES
            fi

            # Install current official driver
            if pacman -Qq | grep -E "^linux$" > /dev/null && ! pacman -Qq | grep -E "^linux-(lts|zen|hardened)$" > /dev/null; then
                echo "Standard 'linux' kernel detected. Using 'nvidia' pre-built drivers."
                DRIVERS=("nvidia" "nvidia-utils" "nvidia-settings" "lib32-nvidia-utils")
            else
                echo "Multiple or custom kernels detected. Using 'nvidia-dkms' for maximum compatibility."
                DRIVERS=("nvidia-dkms" "nvidia-utils" "nvidia-settings" "lib32-nvidia-utils")
            fi
        else
            echo "An NVIDIA driver package is already installed: $INSTALLED_DRIVER"
            echo "Skipping driver installation to avoid conflicts."
            # We still ensure common utilities are present if not already
            DRIVERS=("nvidia-settings" "lib32-nvidia-utils")
        fi
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
    # All NVIDIA driver packages are in official repos — use pacman directly
    # to avoid AUR rebuild issues with leftover legacy packages
    if [ "$GPU_TYPE" == "nvidia" ]; then
        # Sync package databases first — the 'nvidia' package can temporarily
        # disappear from mirrors when the kernel updates before it's rebuilt.
        echo "Syncing package databases..."
        sudo pacman -Sy --noconfirm

        # Check if the pre-built 'nvidia' package is available.
        # If not (e.g., kernel updated ahead of nvidia rebuild), fall back to nvidia-dkms.
        if [[ " ${DRIVERS[*]} " == *" nvidia "* ]] && ! pacman -Si nvidia &>/dev/null; then
            echo "Pre-built 'nvidia' package not available (likely kernel update in progress)."
            echo "Falling back to nvidia-dkms..."
            NEW_DRIVERS=()
            for drv in "${DRIVERS[@]}"; do
                if [ "$drv" == "nvidia" ]; then
                    NEW_DRIVERS+=("nvidia-dkms")
                else
                    NEW_DRIVERS+=("$drv")
                fi
            done
            DRIVERS=("${NEW_DRIVERS[@]}")
            echo "Adjusted driver list: ${DRIVERS[*]}"
        fi

        sudo pacman -S --noconfirm "${DRIVERS[@]}" || {
            echo ""
            echo "============================================"
            echo "  WARNING: GPU driver installation failed!"
            echo "  Your GPU may not work until drivers are"
            echo "  installed manually. Run option 4 later:"
            echo "    ./install.sh  (then select option 4)"
            echo "============================================"
            echo ""
            exit 1
        }
    else
        yay -S --needed --noconfirm "${DRIVERS[@]}"
    fi
else
    echo "No matching GPU found or GPU type is unknown. Skipping driver installation."
fi
