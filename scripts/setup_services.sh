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
    echo "Note: Update 'resume_offset' in Limine. Get offset with: sudo btrfs inspect-internal map-swapfile -r /swapfile"
fi

# 0.1 GPU Specific Configuration (NVIDIA)
if lspci | grep -i "nvidia" &> /dev/null; then
    echo "NVIDIA GPU detected. Configuring drivers and KMS..."
    yay -S --needed --noconfirm nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings
    
    if ! grep -q "nvidia nvidia_modeset nvidia_uvm nvidia_drm" /etc/mkinitcpio.conf; then
        echo "Adding NVIDIA modules to /etc/mkinitcpio.conf..."
        sudo sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
        REBUILD_NEEDED=true
    fi
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
    sudo cp "$SYSTEM_DIR/boot/limine.conf" /boot/limine.conf
else
    echo "Warning: Limine master config not found in $SYSTEM_DIR/boot/"
fi

# Final Rebuild if needed
if [ "$REBUILD_NEEDED" = true ]; then
    echo "Changes detected in mkinitcpio.conf. Rebuilding initramfs..."
    sudo mkinitcpio -P
fi

echo "System services configuration complete."
