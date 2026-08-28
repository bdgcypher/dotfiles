#!/usr/bin/env bash
# waybar updates module - pending pacman/AUR update count.

CACHE=/tmp/waybar-updates
STALE_MIN=60

refresh() {
  # Refresh in the background so waybar never blocks, then re-trigger this module.
  (
    yay -Qu 2>/dev/null | awk '{print $1}' >"$CACHE.tmp" 2>/dev/null
    mv "$CACHE.tmp" "$CACHE" 2>/dev/null
    pkill -RTMIN+12 waybar
  ) &>/dev/null &
}

needs_refresh=0
if [ ! -f "$CACHE" ]; then
  needs_refresh=1
elif find "$CACHE" -mmin +$STALE_MIN 2>/dev/null | grep -q .; then
  needs_refresh=1
fi
[ "$needs_refresh" = 1 ] && refresh

if [ -f "$CACHE" ]; then
  count=$(wc -l <"$CACHE" 2>/dev/null || echo 0)
  if [ "$count" -gt 0 ]; then
    pkgs=$(head -15 "$CACHE" | tr '\n' ' ')
    [ "$count" -gt 15 ] && pkgs="$pkgs..."
    printf '{"text": " %s", "class": "updates", "tooltip": "%s update(s):\\n%s"}' "$count" "$count" "$pkgs"
  else
    printf '{"text": "", "class": "uptodate", "tooltip": "System up to date"}'
  fi
else
  printf '{"text": "", "class": "checking", "tooltip": "Checking for updates..."}'
fi
