#!/bin/bash

# Check Tailscale
if tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null 2>&1; then
  echo '{"text": "󱆢 ", "alt": "tailscale", "tooltip": "Tailscale Connected", "class": "connected"}'
  exit 0
fi

# Check OpenConnect (GlobalProtect)
if pgrep -x openconnect >/dev/null 2>&1; then
  echo '{"text": "󱆢 ", "alt": "openconnect", "tooltip": "GP VPN Connected", "class": "connected"}'
  exit 0
fi

# No VPN
echo '{"text": "", "alt": "none", "tooltip": "No VPN", "class": "disconnected"}'
