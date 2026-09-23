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
    - Suspend-then-Hibernate (battery: suspend, then hibernate after 15min; AC: suspend only, plus `HandleLidSwitch` wiring in `system/etc/systemd/logind.conf.d`)
    - Limine Bootloader management
    - Tailscale Mesh VPN
- **Sunshine/Moonlight Virtual Display:** Streams from a Hyprland headless output created to match the Moonlight client's resolution, so the physical screen is left alone. The output and an idle/sleep inhibitor are managed by `bin/.local/bin/sunshine-display` through Sunshine's `global_prep_cmd` (configured by `scripts/setup_sunshine.sh`).
- **Local Dictation (Voxtype):** Whisper `small.en` on the Vulkan/iGPU backend, toggled with `SUPER+D`. Silero VAD drops silent or mis-pressed recordings so Whisper cannot hallucinate text at your cursor. The whisper model, VAD model, and hotkey settings are ensured by `scripts/stow_configs.sh`.
- **Hyprland Plugin Guard:** Detects when the running Hyprland was upgraded mid-session - its binary is `(deleted)`, so it cannot load plugins at all and `hyprpm` still reports success - and says up front that a restart is required, instead of finishing an install whose plugin setup never took effect.
- **Conflict Management:** Backs up existing configs before stowing.
