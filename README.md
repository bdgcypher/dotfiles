# Arch Linux Dotfiles

Automated Arch Linux configuration and personalization system using GNU Stow.

## Installation (Arch)

Begin with a base Arch Linux ISO. Upon completion, run `archinstall` to begin basic configuration.

### Archinstall Configuration

Before installing dotfiles, configure `archinstall` with the following settings:

- Disk: Btrfs (Default Subvolume Layout)
- Bootloader: Limine
- Snapshots: Snapper
- Hostname: (custom)
- Swap on zram: Yes
- Auth: Set root password and default user (with sudo)
- Network: Network Manager (default backend)
- Applications: Bluetooth - yes, Audio - Pipewire, Print service - yes
- Mirrors: US
- Additional Repositories: multilib
- Additional Packages: git, base-devel, stow, btrfs-progs

Once configuration is complete, install and reboot.

### Dotfiles Installation

After installing a minimal Arch Linux base (via `archinstall`) with `git`, `base-devel`, and `stow` pre-installed:

```bash
git clone https://github.com/bdgcypher/dotfiles.git ~/.dotfiles && cd ~/.dotfiles

chmod +x ./install.sh

./install.sh
```

## Features
- **Idempotent Installation:** Safe to run multiple times on any machine.
- **Hardware-Aware Swap:** Automatically creates a Btrfs swap file sized to your machine's RAM for hibernation support.
- **System-Level Tweak Automation:**
    - SDDM Autologin (Hyprland-uwsm)
    - Plymouth Splash Screen (`arch-charge`)
    - Suspend-then-Hibernate (15min delay)
    - Limine Bootloader management
    - Tailscale Mesh VPN
- **Conflict Management:** Backs up existing configs before stowing.
