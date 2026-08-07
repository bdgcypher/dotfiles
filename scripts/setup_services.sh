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

# 0.1 GPU Specific Configuration
GPU_CMDLINE=""

# Intel
if lspci | grep -iE "vga.*intel" &> /dev/null; then
    echo "Intel GPU detected. Adding i915 for early KMS..."
    if ! grep -qE "^MODULES=.*\bi915\b" /etc/mkinitcpio.conf; then
        sudo sed -i "s/^MODULES=(/MODULES=(i915 /" /etc/mkinitcpio.conf
        REBUILD_NEEDED=true
    fi
    GPU_CMDLINE="i915.modeset=1"
fi

# AMD
if lspci | grep -iE "vga.*(amd|radeon)" &> /dev/null; then
    echo "AMD GPU detected. Adding amdgpu for early KMS..."
    if ! grep -qE "^MODULES=.*\bamdgpu\b" /etc/mkinitcpio.conf; then
        sudo sed -i "s/^MODULES=(/MODULES=(amdgpu /" /etc/mkinitcpio.conf
        REBUILD_NEEDED=true
    fi
    GPU_CMDLINE="amdgpu.modeset=1"
fi

# NVIDIA
if lspci | grep -i "nvidia" &> /dev/null; then
    echo "NVIDIA GPU detected. Configuring KMS..."
    # Packages are handled in setup_gpu.sh
    
    # Add NVIDIA modules to mkinitcpio for Early KMS
    # Order matters: nvidia_drm must load AFTER nvidia, nvidia_modeset, nvidia_uvm
    NVIDIA_MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
    if grep -qE "^MODULES=.*\bnvidia\b" /etc/mkinitcpio.conf; then
        # Modules exist but order may be wrong - rebuild the MODULES line correctly
        echo "Ensuring correct NVIDIA module load order in mkinitcpio.conf..."
        # Extract existing modules, remove nvidia* ones, then prepend in correct order
        EXISTING_MODULES=$(sed -n 's/^MODULES=(\(.*\))$/\1/p' /etc/mkinitcpio.conf)
        CLEAN_MODULES=$(echo "$EXISTING_MODULES" | tr ' ' '\n' | grep -vE "^nvidia(_|$)" | tr '\n' ' ' | sed 's/ *$//')
        NEW_MODULES="${NVIDIA_MODULES[*]} $CLEAN_MODULES"
        NEW_MODULES=$(echo "$NEW_MODULES" | sed 's/ *$//')
        if [ "$EXISTING_MODULES" != "$NEW_MODULES" ]; then
            sudo sed -i "s/^MODULES=.*/MODULES=($NEW_MODULES)/" /etc/mkinitcpio.conf
            REBUILD_NEEDED=true
        fi
    else
        # No NVIDIA modules yet - add them all in correct order
        echo "Adding NVIDIA modules to /etc/mkinitcpio.conf..."
        sudo sed -i "s/^MODULES=(/MODULES=(${NVIDIA_MODULES[*]} /" /etc/mkinitcpio.conf
        REBUILD_NEEDED=true
    fi
    GPU_CMDLINE="nvidia_drm.modeset=1 nvidia_drm.fbdev=1"

    # Copy NVIDIA modprobe.d config for reliable DRM modesetting
    echo "Configuring NVIDIA modprobe.d..."
    sudo mkdir -p /etc/modprobe.d
    sudo cp "$SYSTEM_DIR/etc/modprobe.d/nvidia.conf" /etc/modprobe.d/nvidia.conf

    # Remove kms hook to prevent nouveau from loading (NVIDIA modules handle KMS)
    if grep -qE "^HOOKS=.*\bkms\b" /etc/mkinitcpio.conf; then
        echo "Removing 'kms' hook to prevent nouveau conflict with NVIDIA drivers..."
        sudo sed -i -E 's/\bkms\b ?//; s/  / /g' /etc/mkinitcpio.conf
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
sudo plymouth-set-default-theme -R arch-charge || echo "Plymouth theme setup skipped — will apply after reboot"

# Enable Plymouth boot services. The shutdown services (plymouth-halt/reboot/
# poweroff/kexec) are STATIC units without an [Install] section - they are
# pulled in automatically by halt.target/reboot.target/poweroff.target during
# shutdown, so they must not be (and cannot be) enabled directly.
echo "Enabling Plymouth boot services..."
for SVC in plymouth-start plymouth-read-write plymouth-quit plymouth-quit-wait; do
    if ! systemctl is-enabled "$SVC.service" >/dev/null 2>&1; then
        sudo systemctl enable "$SVC.service" 2>/dev/null || echo "Warning: could not enable $SVC.service"
    fi
done

# 3. Systemd Sleep (Hibernate Delay)
echo "Configuring Suspend-then-Hibernate delay..."
sudo mkdir -p /etc/systemd/sleep.conf.d
sudo cp "$SYSTEM_DIR/etc/systemd/sleep.conf.d/hibernate.conf" /etc/systemd/sleep.conf.d/hibernate.conf

# 3.1 Quiet Boot/Shutdown (Sysctl)
echo "Configuring quiet printk for silent shutdown..."
sudo mkdir -p /etc/sysctl.d
sudo cp "$SYSTEM_DIR/etc/sysctl.d/20-quiet-printk.conf" /etc/sysctl.d/20-quiet-printk.conf

# 3.2 Systemd Quiet Log Level
echo "Configuring systemd quiet log level..."
sudo mkdir -p /etc/systemd/system.conf.d
sudo cp "$SYSTEM_DIR/etc/systemd/system.conf.d/quiet.conf" /etc/systemd/system.conf.d/quiet.conf

# 4. Limine Bootloader
if [[ -f "$SYSTEM_DIR/boot/limine.conf" ]]; then
    echo "Updating Limine configuration..."
    
    # Detect Hardware Identifiers
    ROOT_UUID=$(findmnt / -n -o UUID)
    ROOT_PARTUUID=$(findmnt / -n -o PARTUUID)
    
    if [ -f /swapfile ]; then
        # Ensure swap is on for offset calculation
        sudo swapon /swapfile 2>/dev/null || true
        RESUME_OFFSET=$(sudo btrfs inspect-internal map-swapfile -r /swapfile)
    else
        RESUME_OFFSET=0
    fi

    echo "Detected Root UUID: $ROOT_UUID"
    echo "Detected Root PARTUUID: $ROOT_PARTUUID"
    echo "Detected Resume Offset: $RESUME_OFFSET"

    # Create temporary config from template
    # We use PARTUUID for both root and resume for maximum reliability
    GENERATED_CONF=$(sed "s/@ROOT_UUID@/$ROOT_UUID/g; s/@ROOT_PARTUUID@/$ROOT_PARTUUID/g; s/@RESUME_OFFSET@/$RESUME_OFFSET/g; s/@GPU_CMDLINE@/$GPU_CMDLINE/g" "$SYSTEM_DIR/boot/limine.conf")

    # Limine BIOS scans for limine.conf in this order:
    #   1. /boot/limine/limine.conf  (takes precedence!)
    #   2. /boot/limine.conf
    #   3. /limine/limine.conf
    #   4. /limine.conf
    # We write to all locations that exist (or may be used) so the updated
    # config is always the one Limine actually reads.
    if [ -d /boot/limine ]; then
        echo "Writing Limine config to /boot/limine/limine.conf..."
        printf '%s\n' "$GENERATED_CONF" | sudo tee /boot/limine/limine.conf > /dev/null
    fi
    echo "Writing Limine config to /boot/limine.conf..."
    printf '%s\n' "$GENERATED_CONF" | sudo tee /boot/limine.conf > /dev/null
else
    echo "Warning: Limine master config not found in $SYSTEM_DIR/boot/"
fi

# Final Rebuild if needed
if [ "$REBUILD_NEEDED" = true ]; then
    echo "Changes detected in mkinitcpio.conf. Rebuilding initramfs..."
    sudo mkinitcpio -P
fi

# 5. Hyprlock PAM Configuration (Keyring Unlocking)
echo "Configuring PAM for hyprlock..."
if [ -f /etc/pam.d/hyprlock ]; then
    if ! grep -q "pam_gnome_keyring.so" /etc/pam.d/hyprlock; then
        # Add keyring unlocking to hyprlock
        # We append it to ensure it doesn't break existing auth
        echo "auth     optional     pam_gnome_keyring.so" | sudo tee -a /etc/pam.d/hyprlock > /dev/null
        echo "session  optional     pam_gnome_keyring.so auto_start" | sudo tee -a /etc/pam.d/hyprlock > /dev/null
    fi
else
    # Create basic hyprlock PAM file if it doesn't exist (fallback)
    echo "Creating basic /etc/pam.d/hyprlock..."
    sudo tee /etc/pam.d/hyprlock > /dev/null <<EOF
auth        include     system-auth
auth        optional     pam_gnome_keyring.so
account     include     system-auth
session     include     system-auth
session     optional     pam_gnome_keyring.so auto_start
EOF
fi

# 6. Passwordless Sudo for VPN Scripts
echo "Configuring passwordless sudo for VPN scripts..."
CURRENT_USER=$(whoami)
USER_HOME=$(eval echo ~$CURRENT_USER)

SUDOERS_FILE="/etc/sudoers.d/vpn-scripts"
echo "%wheel ALL=(ALL) NOPASSWD: /usr/bin/openconnect, /usr/bin/pkill, /usr/bin/tailscale" | sudo tee "$SUDOERS_FILE" > /dev/null
sudo chmod 440 "$SUDOERS_FILE"

# 7. Sunshine udev rules
echo "Configuring Sunshine udev rules..."
sudo mkdir -p /etc/udev/rules.d
sudo cp "$SYSTEM_DIR/etc/udev/rules.d/85-sunshine.rules" /etc/udev/rules.d/85-sunshine.rules
sudo udevadm control --reload-rules && sudo udevadm trigger

# 8. Tailscale
echo "Enabling Tailscale service..."
sudo systemctl enable --now tailscaled.service

# 9. Mouseless Wayland Input Permissions
echo "Configuring Mouseless input permissions..."
# Create system group and add user
sudo groupadd --system mouseless 2>/dev/null || true
sudo usermod -aG input,mouseless "$CURRENT_USER"
# Copy udev rule
sudo cp "$SYSTEM_DIR/etc/udev/rules.d/99-mouseless-input.rules" /etc/udev/rules.d/99-mouseless-input.rules
# Ensure uinput module loads on boot
echo "uinput" | sudo tee /etc/modules-load.d/uinput.conf > /dev/null
sudo modprobe uinput 2>/dev/null || true
# Reload udev rules
sudo udevadm control --reload-rules && sudo udevadm trigger
echo "Mouseless permissions configured. Log out and back in for group changes to take effect."

# 10. Iriunwebcam: reload v4l2loopback module
echo "Reloading v4l2loopback for iriunwebcam..."
sudo rmmod v4l2loopback 2>/dev/null || true
sudo modprobe v4l2loopback 2>/dev/null || echo "v4l2loopback not available yet -- will load after reboot"
echo "Iriunwebcam v4l2loopback setup complete."

echo "System services configuration complete."
