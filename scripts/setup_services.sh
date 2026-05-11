#!/bin/bash

# setup_services.sh - Configures system-level services and hardware-aware swap

set -e

DOTFILES_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
SYSTEM_DIR="$DOTFILES_DIR/system"

echo "Setting up system services..."

# 0. Hardware-Aware Swap File (Btrfs)
if swapon --show | grep -q "/swapfile"; then
    echo "Swap file already exists."
else
    echo "Creating hardware-aware swap file for hibernation..."
    # Calculate RAM in MB and add 1GB buffer
    RAM_MB=$(free -m | grep Mem | awk '{print $2}')
    SWAP_SIZE_MB=$((RAM_MB + 1024))
    
    echo "Detected ${RAM_MB}MB RAM. Creating ${SWAP_SIZE_MB}MB swap file..."
    
    sudo truncate -s 0 /swapfile
    sudo chattr +C /swapfile # Disable CoW for Btrfs
    sudo btrfs property set /swapfile compression none
    sudo dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB status=progress
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    
    # Add to fstab if not present
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile none swap defaults 0 0" | sudo tee -a /etc/fstab
    fi
    
    echo "Note: You will need to manually update your 'resume_offset' in Limine."
    echo "To get the offset, run: sudo btrfs inspect-internal map-swapfile -r /swapfile"
fi

# 1. SDDM Autologin
echo "Configuring SDDM Autologin..."
sudo mkdir -p /etc/sddm.conf.d
sudo cp "$SYSTEM_DIR/etc/sddm.conf.d/autologin.conf" /etc/sddm.conf.d/autologin.conf

# 2. Plymouth Hooks & Theme
echo "Configuring Plymouth..."
if grep -q "plymouth" /etc/mkinitcpio.conf; then
    echo "Plymouth hook already present."
else
    echo "Adding plymouth hook to /etc/mkinitcpio.conf..."
    sudo sed -i 's/HOOKS=(\(base udev\)/HOOKS=(\1 plymouth/' /etc/mkinitcpio.conf
fi

if grep -q "resume" /etc/mkinitcpio.conf; then
    echo "Resume hook already present."
else
    echo "Adding resume hook to /etc/mkinitcpio.conf..."
    sudo sed -i 's/filesystems/resume filesystems/' /etc/mkinitcpio.conf
fi

sudo plymouth-set-default-theme -R arch-charge

# 3. Systemd Sleep (Hibernate Delay)
echo "Configuring Suspend-then-Hibernate delay..."
sudo mkdir -p /etc/systemd/sleep.conf.d
sudo cp "$SYSTEM_DIR/etc/systemd/sleep.conf.d/hibernate.conf" /etc/systemd/sleep.conf.d/hibernate.conf

# 4. Limine Bootloader
if [[ -f "$SYSTEM_DIR/boot/limine.conf" ]]; then
    echo "Updating Limine configuration..."
    sudo cp "$SYSTEM_DIR/boot/limine.conf" /boot/limine.conf
else
    echo "Warning: Limine master config not found in $SYSTEM_DIR/boot/"
fi

echo "System services configuration complete."
