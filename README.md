# Arch Linux Dotfiles

Automated Arch Linux configuration and personalization system using GNU Stow.

## Installation (Fresh Arch)

After installing a minimal Arch Linux base (via `archinstall`) with `git`, `base-devel`, and `stow` pre-installed:

```bash
git clone https://github.com/benjamingoddard/dotfiles.git ~/dotfiles && cd ~/dotfiles && ./install.sh
```

## Features
- **Idempotent Installation:** Safe to run multiple times on any machine.
- **Hardware-Aware Swap:** Automatically creates a Btrfs swap file sized to your machine's RAM for hibernation support.
- **System-Level Tweak Automation:**
    - SDDM Autologin (Hyprland-uwsm)
    - Plymouth Splash Screen (`arch-charge`)
    - Suspend-then-Hibernate (15min delay)
    - Limine Bootloader management
- **Conflict Management:** Backs up existing configs before stowing.

## Repository Structure
- `scripts/`: Implementation logic.
- `system/`: Master templates for `/etc` and `/boot` files.
- `pkglist.txt` / `aur_pkglist.txt`: Snapshots of current software stack.
- Folders (`hypr`, `kitty`, etc.): Stowable user configurations.
