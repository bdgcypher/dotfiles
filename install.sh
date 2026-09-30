#!/bin/bash

# install.sh - Main entry point for dotfiles installation

set -e

SCRIPTS_DIR="$(dirname "$(realpath "$0")")/scripts"
DOTFILES_DIR="$(dirname "$(realpath "$0")")"

# Ensure scripts are executable
chmod +x "$SCRIPTS_DIR"/*.sh

# ── Parallel step runner ────────────────────────────────────────────────
# Runs several steps concurrently, buffering each one's output and replaying it
# in the declared order once they finish, so the transcript still reads
# top-to-bottom instead of interleaving.
#
# Only steps that provably do not share mutable state belong in a group:
#   * anything touching the pacman database must be serialized with anything
#     else that does, because pacman takes a global db lock and the loser dies;
#   * anything that reads a config file another step creates must run after it.
PARALLEL_TMP="$(mktemp -d)"
trap 'rm -rf "$PARALLEL_TMP"' EXIT

# run_parallel "Label:function" ...
# A step whose function returns non-zero fails the group; callers that want a
# step to be best-effort make that step's own function swallow the error.
run_parallel() {
    local -a labels=() pids=() statuses=()
    local spec label logfile i rc=0

    for spec in "$@"; do
        label="${spec%%:*}"
        logfile="$PARALLEL_TMP/${label// /_}.log"
        printf '  %s ... started\n' "$label"
        { "${spec#*:}" ; } > "$logfile" 2>&1 &
        pids+=($!)
        labels+=("$label")
    done

    for i in "${!pids[@]}"; do
        if wait "${pids[$i]}"; then statuses+=(0); else statuses+=($?); fi
        echo ""
        echo "───── ${labels[$i]} ─────"
        cat "$PARALLEL_TMP/${labels[$i]// /_}.log"
        echo "───── end ${labels[$i]} ─────"
    done

    for i in "${!pids[@]}"; do
        if [ "${statuses[$i]}" -ne 0 ]; then
            echo "ERROR: step '${labels[$i]}' failed (exit ${statuses[$i]})."
            rc=1
        fi
    done
    echo ""
    return $rc
}

echo "=========================================="
echo "   Arch Linux Dotfiles Installation System    "
echo "=========================================="
echo ""
echo "Please select an installation mode:"
echo "1) Full Install (Packages, Services, Stow)"
echo "2) Update Only (Packages, Stow)"
echo "3) System Only (Sudo-level Services)"
echo "4) GPU Driver Setup (Optional)"
echo "5) Audio Setup (Set default output)"
echo "6) Timezone Setup (Set system timezone)"
echo "7) Repair (Restore missing/modified dotfiles)"
echo "8) Exit"
echo ""
read -p "Selection [1-8]: " choice

case $choice in
    1|2)
        # Say up front if this session's Hyprland already cannot load plugins
        # (its binary was replaced by an earlier package upgrade), and check
        # again right after install_packages.sh, which is what actually
        # performs the upgrade. See scripts/hyprland_restart_check.sh.
        HYPRLAND_RESTART_NEEDED=0
        if [ -x "$SCRIPTS_DIR/hyprland_restart_check.sh" ]; then
            "$SCRIPTS_DIR/hyprland_restart_check.sh" || HYPRLAND_RESTART_NEEDED=1
        fi

        # Safety check: If any key directory is empty, trigger a repair first
        if [[ ! -f "$SCRIPTS_DIR/install_packages.sh" ]] || [[ -z "$(ls -A "$DOTFILES_DIR/hypr" 2>/dev/null)" ]]; then
            echo "Warning: Repository looks incomplete. Running auto-repair..."
            git -C "$DOTFILES_DIR" restore .
            git -C "$DOTFILES_DIR" checkout .
        fi

        if [[ $choice -eq 1 ]]; then
            echo "Starting Full Installation..."
            sudo -v # Early sudo elevation
            # Keep-alive sudo
            while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

            echo "[1/7] Installing packages..."
            "$SCRIPTS_DIR/install_packages.sh"
            # This step may have just upgraded hyprland; report the restart
            # requirement as soon as it becomes true (once is enough).
            if [ "$HYPRLAND_RESTART_NEEDED" = 0 ] && [ -x "$SCRIPTS_DIR/hyprland_restart_check.sh" ]; then
                "$SCRIPTS_DIR/hyprland_restart_check.sh" || HYPRLAND_RESTART_NEEDED=1
            fi

            # Step 2 runs concurrently with step 3.
            #   * stow_configs.sh only rewrites symlinks under $HOME, so it is
            #     safe to overlap with the driver work.
            #   * setup_services.sh is deliberately NOT in the group, for two
            #     reasons. Both it and stow_configs.sh run `voxtype` commands
            #     that write ~/.config/voxtype, and overlapping those loses
            #     settings; and it can invoke pacman, whose database lock would
            #     collide with setup_gpu.sh running at the same time.
            #   * setup_mime_defaults.sh is likewise not in the group: it
            #     rewrites ~/.config/mimeapps.list, which stow_configs.sh is
            #     responsible for linking into place first.
            # Stow is all that is left here: every machine is on the quickshell
            # stack, so there are no pre-quickshell symlinks in $HOME for stow's
            # conflict handling to trip over, and nothing to retire first.
            step_stow_configs() { "$SCRIPTS_DIR/stow_configs.sh"; }
            step_gpu_drivers() {
                "$SCRIPTS_DIR/setup_gpu.sh" ||
                    echo "WARNING: GPU driver setup failed, continuing with remaining steps..."
            }

            echo "[2/7] Stowing dotfile configs and setting up GPU drivers (concurrently)..."
            run_parallel \
                "Stowing dotfile configs:step_stow_configs" \
                "GPU drivers:step_gpu_drivers"

            echo "[3/7] Configuring system services..."
            "$SCRIPTS_DIR/setup_services.sh"
            echo "[4/7] Setting default file type handlers..."
            "$SCRIPTS_DIR/setup_mime_defaults.sh" || echo "WARNING: file type defaults reported a problem, continuing..."
            echo "[5/7] Setting up timezone..."
            "$SCRIPTS_DIR/setup_timezone.sh"
            echo "[6/7] Restarting the launcher and shell..."
            "$SCRIPTS_DIR/restart_launcher.sh"
            echo "[7/7] Enabling Hyprland plugins..."
            "$SCRIPTS_DIR/setup_plugins.sh"
        else
            echo "Starting Update..."
            echo "[1/5] Installing/updating packages..."
            "$SCRIPTS_DIR/install_packages.sh"
            # install_packages.sh may upgrade hyprland mid-session; if so, its
            # plugins cannot load until the compositor restarts.
            if [ "$HYPRLAND_RESTART_NEEDED" = 0 ] && [ -x "$SCRIPTS_DIR/hyprland_restart_check.sh" ]; then
                "$SCRIPTS_DIR/hyprland_restart_check.sh" || HYPRLAND_RESTART_NEEDED=1
            fi
            # Stow is all that is left here: every machine is on the quickshell
            # stack, so there is no pre-quickshell stack left to retire.
            echo "[2/5] Stowing dotfile configs..."
            "$SCRIPTS_DIR/stow_configs.sh"
            echo "[3/5] Setting default file type handlers..."
            "$SCRIPTS_DIR/setup_mime_defaults.sh" || echo "WARNING: file type defaults reported a problem, continuing..."
            echo "[4/5] Restarting the launcher and shell..."
            "$SCRIPTS_DIR/restart_launcher.sh"
            echo "[5/5] Enabling Hyprland plugins..."
            "$SCRIPTS_DIR/setup_plugins.sh"
        fi
        ;;
    3)
        echo "Starting System Configuration..."
        sudo -v
        "$SCRIPTS_DIR/setup_services.sh"
        ;;
    4)
        echo "Starting GPU Driver Setup..."
        "$SCRIPTS_DIR/setup_gpu.sh"
        ;;
    5)
        "$SCRIPTS_DIR/setup_audio.sh"
        ;;
    6)
        "$SCRIPTS_DIR/setup_timezone.sh"
        ;;
    7)
        echo "Repairing dotfiles repository (Hard Reset)..."
        # Force restore even if changes are staged
        git -C "$DOTFILES_DIR" fetch origin main
        git -C "$DOTFILES_DIR" reset --hard origin/main
        git -C "$DOTFILES_DIR" clean -fd
        echo "Repair complete. Source files have been restored to match GitHub."
        ;;
    8)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid selection. Exiting."
        exit 1
        ;;
esac

echo ""
if [ "${HYPRLAND_RESTART_NEEDED:-0}" = 1 ]; then
    echo "Hyprland plugins are not loaded yet: log out or reboot to load them."
    echo ""
fi
echo "=========================================="
echo "   Installation Complete"
echo "=========================================="
echo ""
echo "If system hooks or bootloaders were changed, please reboot."
