#!/bin/bash

echo "Enabling and starting system services..."

# Networking
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now ufw

# Display Manager
sudo systemctl enable --now sddm

# Docker
sudo systemctl enable --now docker

# Bluetooth
sudo systemctl enable --now bluetooth

# Printing
sudo systemctl enable --now cups
sudo systemctl enable --now cups-browsed

# Syncing
sudo systemctl enable --now syncthing@$USER

# ZRAM
sudo systemctl enable --now zram-generator

# Power management
sudo systemctl enable --now power-profiles-daemon

# Device monitoring/control
sudo systemctl enable --now bolt

echo "Services setup complete."
