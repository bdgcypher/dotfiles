#!/bin/bash
# setup_sunshine.sh - Point Sunshine at a Hyprland headless output that matches
# the resolution of the Moonlight client that connects.
#
# Writes three settings into Sunshine's config:
#   output_name     - the virtual display Sunshine streams. It is created on
#                     demand by bin/.local/bin/sunshine-display, which Sunshine
#                     runs through global_prep_cmd on every connection.
#   capture         - wlr, the only Sunshine backend that can capture a virtual
#                     display on Hyprland (kms cannot see headless outputs).
#   global_prep_cmd - runs sunshine-display start/stop around every stream, so
#                     the virtual output exists at exactly the client's
#                     resolution before capture begins.
#
# The config file is deliberately NOT tracked by git: Sunshine's web UI rewrites
# it whenever a setting changes and it holds machine-specific paths. The file as
# it was before the first run is kept at sunshine.conf.bak, so undoing this is
# a single copy.

set -uo pipefail

CONF="${SUNSHINE_CONFIG:-$HOME/.config/sunshine/sunshine.conf}"
VIRTUAL_DISPLAY="${SUNSHINE_DISPLAY_OUTPUT:-SUNSHINE-1}"
SUNSHINE_UNIT="app-dev.lizardbyte.app.Sunshine.service"
LAUNCHER="$HOME/.local/bin/sunshine-display"

if ! command -v sunshine >/dev/null 2>&1; then
    echo "Sunshine is not installed - skipping virtual display setup."
    exit 0
fi

# Sunshine's global_prep_cmd value. Single quotes keep $HOME literal so the
# inner sh -c resolves it, and there are no JSON escapes to get wrong.
PREP_CMD="[{\"do\":\"sh -c '\$HOME/.local/bin/sunshine-display start'\",\"undo\":\"sh -c '\$HOME/.local/bin/sunshine-display stop'\"}]"

mkdir -p "$(dirname "$CONF")"
[ -f "$CONF" ] || : >"$CONF"

if [ ! -f "$CONF.bak" ]; then
    cp "$CONF" "$CONF.bak"
    echo "Backed up the current Sunshine config to $CONF.bak"
fi

# Replace the first occurrence of a key (commented or not) and drop duplicates,
# or append it when it is not present yet.
set_key() {
    local key="$1" value="$2" tmp
    tmp="$(mktemp)" || return 1
    awk -v k="$key" -v v="$value" '
        BEGIN { found = 0 }
        {
            if ($0 ~ "^[[:space:]]*#?[[:space:]]*" k "[[:space:]]*=") {
                if (!found) { printf "%s = %s\n", k, v; found = 1 }
                next
            }
            print
        }
        END { if (!found) printf "%s = %s\n", k, v }
    ' "$CONF" >"$tmp" && mv "$tmp" "$CONF" || {
        rm -f "$tmp"
        echo "ERROR: could not update $CONF" >&2
        return 1
    }
}

echo "Configuring Sunshine virtual display ($VIRTUAL_DISPLAY)..."
set_key output_name "$VIRTUAL_DISPLAY"
set_key capture wlr
set_key global_prep_cmd "$PREP_CMD"

if [ ! -x "$LAUNCHER" ]; then
    echo "WARNING: $LAUNCHER is missing - run stow_configs.sh (stow 'bin') before streaming." >&2
fi

echo "Sunshine config updated:"
grep -E "^[[:space:]]*(output_name|capture|global_prep_cmd)[[:space:]]*=" "$CONF" | sed 's/^/  /'

# Sunshine reads its config at startup, so a running instance must be restarted.
if systemctl --user is-active --quiet "$SUNSHINE_UNIT" 2>/dev/null; then
    systemctl --user restart "$SUNSHINE_UNIT" 2>/dev/null \
        && echo "Restarted $SUNSHINE_UNIT."
else
    echo "NOTE: Sunshine was not running under systemd. Restart it (or log back in)"
    echo "      for the new settings to take effect."
fi
