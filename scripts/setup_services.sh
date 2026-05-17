#!/bin/bash

# setup_services.sh - Configures system-level services, hardware-aware swap, and NVIDIA

set -e

DOTFILES_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
SYSTEM_DIR="$DOTFILES_DIR/system"
REBUILD_NEEDED=false

echo "Setting up system services..."

# 0. Hardware-Aware Swap File (Btrfs)
if swapon --show | grep -q "/swapfile"; then
    echo "Swap file already exists."
else
    echo "Creating hardware-aware swap file for hibernation..."
    RAM_MB=$(free -m | grep Mem | awk '{print $2}')
    SWAP_SIZE_MB=$((RAM_MB + 1024))
    echo "Detected ${RAM_MB}MB RAM. Creating ${SWAP_SIZE_MB}MB swap file..."
    sudo truncate -s 0 /swapfile
    sudo chattr +C /swapfile
    sudo dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB status=progress
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile none swap defaults 0 0" | sudo tee -a /etc/fstab
    fi
fi

# 0.1 GPU Specific Configuration (NVIDIA)
if lspci | grep -i "nvidia" &> /dev/null; then
    echo "NVIDIA GPU detected. Configuring KMS..."
    # Packages are handled in setup_gpu.sh
    
    # Add NVIDIA modules to mkinitcpio for Early KMS
    # We add them individually to avoid matching issues if the order is different
    for mod in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
        if ! grep -qE "^MODULES=.*\b$mod\b" /etc/mkinitcpio.conf; then
            echo "Adding $mod to /etc/mkinitcpio.conf..."
            sudo sed -i "s/^MODULES=(/MODULES=($mod /" /etc/mkinitcpio.conf
            REBUILD_NEEDED=true
        fi
    done
fi

# 1. SDDM Autologin
echo "Configuring SDDM Autologin..."
sudo mkdir -p /etc/sddm.conf.d
sudo cp "$SYSTEM_DIR/etc/sddm.conf.d/autologin.conf" /etc/sddm.conf.d/autologin.conf
sudo systemctl enable --now sddm.service

# 2. Plymouth Hooks & Theme
echo "Configuring Plymouth..."
if ! grep -q "plymouth" /etc/mkinitcpio.conf; then
    echo "Adding plymouth hook to /etc/mkinitcpio.conf..."
    sudo sed -i 's/HOOKS=(\(base udev\)/HOOKS=(\1 plymouth/' /etc/mkinitcpio.conf
    REBUILD_NEEDED=true
fi

if ! grep -q "resume" /etc/mkinitcpio.conf; then
    echo "Adding resume hook to /etc/mkinitcpio.conf..."
    sudo sed -i 's/filesystems/resume filesystems/' /etc/mkinitcpio.conf
    REBUILD_NEEDED=true
fi

echo "Setting Plymouth theme to arch-charge..."
sudo plymouth-set-default-theme -R arch-charge

# 3. Systemd Sleep (Hibernate Delay)
echo "Configuring Suspend-then-Hibernate delay..."
sudo mkdir -p /etc/systemd/sleep.conf.d
sudo cp "$SYSTEM_DIR/etc/systemd/sleep.conf.d/hibernate.conf" /etc/systemd/sleep.conf.d/hibernate.conf

# 4. Limine Bootloader
if [[ -f "$SYSTEM_DIR/boot/limine.conf" ]]; then
    echo "Updating Limine configuration..."
    
    # Detect Hardware Identifiers
    ROOT_UUID=$(findmnt / -n -o UUID)
    ROOT_PARTUUID=$(findmnt / -n -o PARTUUID)
    
    if [ -f /swapfile ]; then
        RESUME_OFFSET=$(sudo btrfs inspect-internal map-swapfile -r /swapfile)
    else
        RESUME_OFFSET=0
    fi

    echo "Detected Root UUID: $ROOT_UUID"
    echo "Detected Root PARTUUID: $ROOT_PARTUUID"
    echo "Detected Resume Offset: $RESUME_OFFSET"

    # Create temporary config from template
    sed "s/@ROOT_UUID@/$ROOT_UUID/g; s/@ROOT_PARTUUID@/$ROOT_PARTUUID/g; s/@RESUME_OFFSET@/$RESUME_OFFSET/g" \
        "$SYSTEM_DIR/boot/limine.conf" | sudo tee /boot/limine.conf > /dev/null
else
    echo "Warning: Limine master config not found in $SYSTEM_DIR/boot/"
fi

# Final Rebuild if needed
if [ "$REBUILD_NEEDED" = true ]; then
    echo "Changes detected in mkinitcpio.conf. Rebuilding initramfs..."
    sudo mkinitcpio -P
fi

echo "System services configuration complete."
