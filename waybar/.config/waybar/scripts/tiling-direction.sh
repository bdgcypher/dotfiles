#!/usr/bin/env bash
# Output the next tiled window's spawn direction for the waybar module.
# Scrolling layout: shows when the next window will be consumed into the active
# column (armed) vs. opened in a new column (default).
# Dwindle layout: shows the manual preselect when armed, else the automatic
# prediction based on the focused window's aspect ratio.

ws_info="$(hyprctl activeworkspace -j 2>/dev/null)"
ws_id="$(printf '%s' "$ws_info" | jq -r '.id')"
layout="$(printf '%s' "$ws_info" | jq -r '.tiledLayout')"

if [ "$layout" = "scrolling" ]; then
    if [ -f /tmp/scrolling-consume ] && grep -qx "$ws_id" /tmp/scrolling-consume 2>/dev/null; then
        # Consume armed: next window joins the active column (below).
        printf '{"text": "󰓢", "class": "d armed", "tooltip": "Next window: consume (below)"}'
    else
        # Default: next window opens in a new column (right).
        printf '{"text": "󰓡", "class": "r auto", "tooltip": "Next window: new column (right)"}'
    fi
    exit 0
fi

# Dwindle: manual preselect (state file exists and not yet consumed)
state_file="/tmp/tiling-direction"
armed=""
dir=""

if [ -f "$state_file" ]; then
    read -r armed_ws dir armed_count consumed < "$state_file" || true
    if [ -n "$armed_ws" ] && [ -n "$dir" ] && [ "$consumed" != "consumed" ]; then
        current_count="$(hyprctl clients -j | jq '[.[] | select(.floating == false and .workspace.id == '"$armed_ws"')] | length')"
        if [ "$ws_id" = "$armed_ws" ] && [ -n "$current_count" ]; then
            if [ "$current_count" -gt "$armed_count" ]; then
                # A new window opened — preselect consumed. Mark it so it stays
                # consumed even if that window is later closed.
                printf '%s %s %s consumed\n' "$armed_ws" "$dir" "$armed_count" > "$state_file"
            else
                armed="1"
            fi
        fi
    fi
fi

# Automatic: predict from the focused tiled window's aspect ratio
if [ -z "$armed" ]; then
    win="$(hyprctl activewindow -j 2>/dev/null)"
    if [ "$(printf '%s' "$win" | jq -r '.class')" = "null" ] || [ "$(printf '%s' "$win" | jq -r '.floating')" = "true" ]; then
        printf '{"text": "", "class": "none"}'
        exit 0
    fi
    w="$(printf '%s' "$win" | jq -r '.size[0]')"
    h="$(printf '%s' "$win" | jq -r '.size[1]')"
    if [ "$w" -gt "$h" ]; then dir="r"; else dir="d"; fi
fi

case "$dir" in
    r)
        icon="󰓡"
        label="horizontal"
        ;;
    d)
        icon="󰓢"
        label="vertical"
        ;;
    *)
        icon=""
        label=""
        ;;
esac

if [ -n "$armed" ]; then cls="$dir armed"; else cls="$dir auto"; fi
printf '{"text": "%s", "class": "%s", "tooltip": "Tiling direction: %s"}' "$icon" "$cls" "$label"
