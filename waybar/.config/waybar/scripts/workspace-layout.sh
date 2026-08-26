#!/usr/bin/env bash
# Output the active workspace's tiling layout for the waybar module.

info="$(hyprctl activeworkspace -j 2>/dev/null)"
layout="$(printf '%s' "$info" | jq -r '.tiledLayout')"

if [ -z "$layout" ] || [ "$layout" = "null" ]; then
  printf '{"text": "", "class": "empty", "tooltip": "No active workspace"}'
  exit 0
fi

case "$layout" in
dwindle) icon="󰕮" ;;
scrolling) icon="" ;;
*) icon="" ;;
esac

printf '{"text": "%s", "class": "%s", "tooltip": "Layout: %s"}' \
  "$icon" "$layout" "$layout"
