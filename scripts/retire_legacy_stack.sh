#!/bin/bash

# retire_legacy_stack.sh - Remove the pre-Quickshell desktop stack from a machine
# that is still running it, so an existing install ends up where a fresh one
# starts.
#
# What "the legacy stack" means here:
#
#   packages   waybar, swaync, swayosd, walker, elephant-all-git
#   stow pkgs  waybar/ walker/ swaync/ swayosd/ elephant/  (deleted from the repo)
#   services   waybar.service, elephant.service, swaync.service (user units)
#
# The bar, the launcher, the notifications and the OSD are all hayami-shell's now,
# so none of the above has anything left to do.
#
# Two things make this more than an `stow -D`:
#
#   1. stow cannot unlink a package that no longer exists. `stow -D waybar` needs
#      the waybar/ directory to compute what to remove, and that directory is gone
#      from the repo by the time this script runs on another machine. So the
#      symlinks it left in $HOME are found and removed by reading their targets
#      instead -- every link pointing at a now-missing file inside the repo.
#   2. The packages have to be uninstalled as well as unstowed, or the machine
#      keeps a dead bar and a dead notification daemon on disk (and `notify-send`
#      could still activate swaync through D-Bus, since systemd owns its bus
#      name; that is why the service is stopped before the package is removed).
#
# Idempotent: on an already-migrated machine every step finds nothing to do and
# says so. Safe to run from install.sh on every update.
#
#   retire_legacy_stack.sh [--dry-run] [--keep-packages]

set -uo pipefail

DOTFILES_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
[ -d "$DOTFILES_DIR/hypr" ] || DOTFILES_DIR="$HOME/.dotfiles"

DRY_RUN=0
KEEP_PACKAGES=0

usage() {
	cat >&2 <<'EOF'
usage: retire_legacy_stack.sh [options]

  --dry-run, -n     report what would be removed; change nothing
  --keep-packages   stop and unstow the old stack but leave the packages installed

Removes waybar, swaync, swayosd, walker and elephant (and the stow packages and
user services that go with them), which hayami-shell replaced. Idempotent.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	--dry-run | -n) DRY_RUN=1; shift ;;
	--keep-packages) KEEP_PACKAGES=1; shift ;;
	-h | --help) usage; exit 0 ;;
	*)
		echo "retire_legacy_stack.sh: unknown option $1" >&2
		usage
		exit 2
		;;
	esac
done

# Every echo of an action goes through run(), so --dry-run is one flag and not a
# second copy of the script.
run() {
	if [ "$DRY_RUN" = 1 ]; then
		echo "  would: $*"
	else
		"$@" >/dev/null 2>&1
	fi
}

# Package removal needs root. install.sh mode 1 caches sudo before calling this,
# but "update only" does not, so prompt when there is a terminal to prompt on and
# fall through to a warning when there is not -- a migration that cannot remove
# the packages is still a migration.
ensure_sudo() {
	sudo -n true 2>/dev/null && return 0
	[ -t 0 ] || return 1
	echo "Please enter your sudo password (needed to remove the old packages):" >&2
	sudo -v 2>/dev/null
}

PACKAGES=(waybar swaync swayosd walker elephant-all-git)
SERVICES=(waybar.service elephant.service swaync.service)
# The stow packages this script exists to clean up after. Kept as a list so the
# symlink sweep has a second, positive test besides "the target is missing".
STOW_PACKAGES=(waybar walker swaync swayosd elephant)

# Packages the old stack pulled in as its own dependencies that hayami-shell still
# uses: playerctl is how `hayami-osd --playerctl` drives the XF86AudioPlay and
# XF86AudioNext keys, and wtype is how clipboard-paste types multi-line text into
# ghostty. `pacman -Rns` removes dependencies nothing else requires, and on a
# machine where these arrived with waybar or elephant nothing else requires them,
# so they have to be explicitly installed *before* the removal or the media keys
# and multi-line pastes quietly stop working. Installing them explicitly is also
# what makes pacman keep them: -s only prunes packages that were installed as
# dependencies. (Both are in pkglist.txt for the same reason.)
KEEP_PACKAGES_FROM_LEGACY=(playerctl wtype)
# bar-switch remembered which stack was live. There is only one now.
LEGACY_STATE="$([ -n "${XDG_STATE_HOME:-}" ] && echo "$XDG_STATE_HOME" || echo "$HOME/.local/state")/hayami-shell/bar"

DIRTY=0

echo "Retiring the legacy desktop stack..."

# ── 1. stop the old services ─────────────────────────────────────────────────

echo
echo "Services:"
for svc in "${SERVICES[@]}"; do
	if systemctl --user is-enabled "$svc" >/dev/null 2>&1 ||
		systemctl --user is-active "$svc" >/dev/null 2>&1 ||
		[ -e "$HOME/.config/systemd/user/$svc" ] ||
		[ -e "$HOME/.config/systemd/user/graphical-session.target.wants/$svc" ]; then
		DIRTY=1
		echo "  $svc: disabling and stopping"
		run systemctl --user disable --now "$svc"
	fi
done

for proc in waybar walker elephant swaync swayosd-server; do
	if pgrep -x "$proc" >/dev/null 2>&1; then
		DIRTY=1
		echo "  $proc: killing"
		run pkill -x "$proc"
	fi
done

# ── 2. prune the symlinks stow left behind ───────────────────────────────────

# A link is removed when it resolves into the repo and either points at one of the
# deleted packages or at a file that is no longer there. Both tests are needed:
# the first catches links whose target still exists somewhere (a package directory
# that was renamed rather than deleted), the second catches everything else --
# including ~/.local/bin/bar-switch, whose source this migration deletes.
#
# Links *inside* the repo are skipped: stow_configs.sh keeps its promise never to
# write to the repository, and this does not get to break it.echo
echo "Stale symlinks:"
pruned=0
# Collected first: the loop below deletes entries, and walking the tree while
# changing it can make find skip siblings.
mapfile -t links < <(find "$HOME" -xdev -type l 2>/dev/null)
for link in "${links[@]}"; do
	case "$link" in
	"$DOTFILES_DIR"/*) continue ;;
	esac

	# -m canonicalises even when the target does not exist, which is the whole
	# point here: these links are mostly dangling by now.
	resolved=$(readlink -m -- "$link" 2>/dev/null) || continue
	case "$resolved" in
	"$DOTFILES_DIR"/*) ;;
	*) continue ;;
	esac

	remove=0
	for pkg in "${STOW_PACKAGES[@]}"; do
		case "$resolved" in
		"$DOTFILES_DIR/$pkg"/*) remove=1 ;;
		esac
	done
	# Deleted unit files, including the enablement links that point at them.
	case "$resolved" in
	*"/systemd/.config/systemd/user/waybar.service" | *"/systemd/.config/systemd/user/elephant.service") remove=1 ;;
	esac
	# Anything else in the repo that is simply not there any more.
	[ -e "$resolved" ] || remove=1

	[ "$remove" = 1 ] || continue
	echo "  ${link/#$HOME/\~} -> ${resolved/#$DOTFILES_DIR/<repo>}"
	run rm -f -- "$link"
	pruned=$((pruned + 1))
done

if [ "$pruned" = 0 ]; then
	echo "  none"
else
	DIRTY=1
	echo "  $pruned removed"
fi

if [ -e "$LEGACY_STATE" ]; then
	DIRTY=1
	echo "  $LEGACY_STATE: removing (bar-switch's memory of which bar was live)"
	run rm -f -- "$LEGACY_STATE"
fi

# The units are gone from disk now, so tell systemd to forget them -- otherwise a
# `systemctl --user status waybar` keeps answering from its cached unit.
run systemctl --user daemon-reload
# Scoped to the units that were just removed, so a real failure elsewhere is not
# quietly cleared.
run systemctl --user reset-failed "${SERVICES[@]}"

# ── 3. uninstall the packages ────────────────────────────────────────────────

echo
echo "Packages:"
if [ "$KEEP_PACKAGES" = 1 ]; then
	echo "  skipped (--keep-packages)"
else
	installed=()
	for pkg in "${PACKAGES[@]}"; do
		pacman -Qq "$pkg" >/dev/null 2>&1 && installed+=("$pkg")
	done

	if [ ${#installed[@]} -eq 0 ]; then
		echo "  none installed"
	else
		# Pin the keeps first, so the -Rns below cannot take them along.
		if ensure_sudo; then
			echo "  keeping (installed explicitly): ${KEEP_PACKAGES_FROM_LEGACY[*]}"
			run sudo pacman -S --needed --noconfirm "${KEEP_PACKAGES_FROM_LEGACY[@]}"
		fi

		echo "  removing: ${installed[*]}"
		if [ "$DRY_RUN" = 1 ]; then
			# -Rs --print lists the whole cascade, so the log shows exactly what
			# goes (waybar's gtkmm/pangomm tree, swaync's granite, and so on).
			# --noconfirm cannot be used with --print, hence the shorter flags.
			echo "  cascade (-Rns), not counting the keeps above:"
			keep_re=$(printf '%s|' "${KEEP_PACKAGES_FROM_LEGACY[@]}")
			pacman -Rs --print "${installed[@]}" 2>/dev/null |
				grep -Ev "^(${keep_re%|})-" | sed 's/^/    /' || true
		elif ensure_sudo; then
			DIRTY=1
			# -Rns: their dependencies go too, but only the ones nothing else
			# wants. waybar, swaync and swayosd exist for this stack alone.
			if ! sudo pacman -Rns --noconfirm "${installed[@]}"; then
				echo "  warning: pacman could not remove some of them; they are unused either way" >&2
			fi
		else
			echo "  warning: no passwordless sudo, so the packages were NOT removed."
			echo "           Run this to finish:" >&2
			echo "             sudo pacman -Rns ${installed[*]}" >&2
		fi
	fi
fi

# ── 4. hand the session over ─────────────────────────────────────────────────

# The shell replaces all four pieces, so it should be the thing running now. The
# command may not be stowed into ~/.local/bin yet when install.sh calls this
# (the migration runs before the restow), so fall back to the repo copy.
shell_cmd=""
if command -v hayami-shell >/dev/null 2>&1; then
	shell_cmd=hayami-shell
elif [ -x "$DOTFILES_DIR/bin/.local/bin/hayami-shell" ]; then
	shell_cmd="$DOTFILES_DIR/bin/.local/bin/hayami-shell"
fi

if [ -n "$shell_cmd" ]; then
	echo
	echo "Shell:"
	if [ "$DRY_RUN" = 1 ]; then
		echo "  would: start it if it is not already running"
	else
		# Starting it outside a graphical session is pointless but harmless: qs
		# exits on its own when it cannot reach a compositor, and the next login
		# starts it through hypr/autostart.lua either way.
		if "$shell_cmd" start; then
			true
		else
			echo "  not started (no graphical session yet?) -- it starts at login" >&2
		fi
	fi
fi

if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
	# autostart.lua no longer starts elephant or walker, so this drops the evicted
	# app rules and the old exec-once entries from the running config.
	run hyprctl reload
	[ "$DRY_RUN" = 1 ] || echo "Hyprland config reloaded."
fi

echo
if [ "$DIRTY" = 0 ]; then
	echo "Nothing to retire: this machine is already on hayami-shell alone."
elif [ "$DRY_RUN" = 1 ]; then
	echo "Dry run: nothing was changed. Re-run without --dry-run to retire the stack."
else
	echo "Legacy stack retired. hayami-shell now owns the bar, launcher,"
	echo "notifications and OSD."
fi
