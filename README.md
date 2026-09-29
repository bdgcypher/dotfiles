# Arch Linux Dotfiles

My personal Arch Linux setup, kept as a set of configs managed by GNU Stow. Hyprland window management, a Quickshell bar and menus, wallpaper-driven theming, and an install script that takes a fresh Arch install to a fully custom working environment.

## Features

- **Quickshell** — the whole desktop chrome in one process: bar, launcher, notifications and OSD. The bar can be dragged to any screen edge, every module can be toggled on/off, and the bar itself is keyboard-navigable.
- **Hyprland** — tiling compositor configured in Lua, with scrolling layout and the `hyprland-scroll-overview` plugin for a workspace overview.
- **Dynamic theming** — colours are generated from the current wallpaper with pywal and applied across GTK apps, terminals, and the rest of the shell. Switch wallpapers or light/dark mode from the launcher.
- **Local dictation** — Voxtype runs Whisper on the GPU (Vulkan) with voice-activity detection, toggled with `SUPER + D`.
- **Automated, idempotent install** — every config is symlinked with GNU Stow and existing files are backed up first. Safe to run again on any machine.
- **Hibernation-ready** — creates a Btrfs swap file sized to your RAM and wires up suspend-then-hibernate (on battery, hibernates after 15 min; on AC, suspends only).
- **Polished boot** — Limine bootloader, Plymouth splash, and SDDM autologin straight into a custom hyprlock lockscreen.

## Installation

### 1. Base install

Start from the Arch Linux ISO and launch `archinstall`, using the following settings:

| Setting | Value |
| --- | --- |
| Disk | Btrfs (default subvolume layout) |
| Bootloader | Limine |
| Snapshots | Snapper |
| Hostname | your choice |
| Swap on zram | Yes |
| Auth | set root password and a user with sudo |
| Network | NetworkManager (default backend) |
| Applications | Bluetooth: yes, Audio: PipeWire, Print service: yes |
| Mirrors | US |
| Additional repositories | multilib |
| Additional packages | `git base-devel stow btrfs-progs` |

Finish the install and reboot into the base system.

### 2. Install the dotfiles

Log in as your user and run:

```bash
git clone https://github.com/bdgcypher/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
chmod +x ./install.sh
./install.sh
```

Choose **Full Install** and follow the prompts. The script installs packages, stows the configs, sets up GPU drivers and system services, applies the timezone, and starts the shell. Reboot when it finishes.

## Install script options

Running `./install.sh` again later gives you these modes:

| Option | What it does |
| --- | --- |
| Full Install | Everything: packages, services, configs |
| Update Only | Update packages and re-stow configs |
| System Only | Re-apply the sudo-level system services |
| GPU Driver Setup | Detect and configure Intel/AMD/NVIDIA drivers |
| Audio Setup | Set the default audio output |
| Timezone Setup | Set the system timezone |
| Repair | Restore dotfiles to match the repo |
