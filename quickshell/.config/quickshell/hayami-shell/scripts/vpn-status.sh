#!/bin/bash

# What the bar's VPN indicator reads, and what its popout shows: which tunnel is
# up, what to call it, and the one detail worth having -- the address you are
# reachable at.
#
# The shape is text/alt/tooltip/class, with the four fields the
# panel needs added on: kind, name, state, detail. The glyph is written as an
# escape rather than pasted in, so it cannot drift from Icons.js (U+F11A2,
# nf-md-vpn) the way two copies of the same character can.
glyph=$(printf '\U000F11A2 ')

# Check Tailscale
ts=$(tailscale status --json 2>/dev/null)
if [ -n "$ts" ] && jq -e '.BackendState == "Running"' >/dev/null 2>&1 <<<"$ts"; then
  # -c and not -cn: this one reads the status it was given on stdin, and -n would
  # leave every `.Self` below null.
  jq -c --arg glyph "$glyph" '{
    text: $glyph, alt: "tailscale", tooltip: "Tailscale Connected",
    class: "connected", kind: "tailscale", name: "Tailscale", state: "Connected",
    detail: (.Self.TailscaleIPs[0] // "")
  }' <<<"$ts"
  exit 0
fi

# Check OpenConnect (GlobalProtect)
if pgrep -x openconnect >/dev/null 2>&1; then
  # There is no globalprotect CLI on this machine to ask, so the server is read
  # off the process's own command line -- --server=host or --server host.
  server=$(ps -ww -o args= -C openconnect 2>/dev/null \
    | grep -oE '\-\-(server|host)[= ][^ ]+' | head -1 | sed -E 's/.*[= ]//')
  jq -cn --arg glyph "$glyph" --arg detail "$server" '{
    text: $glyph, alt: "openconnect", tooltip: "GP VPN Connected",
    class: "connected", kind: "openconnect", name: "GlobalProtect",
    state: "Connected", detail: $detail
  }'
  exit 0
fi

# No VPN
jq -cn '{
  text: "", alt: "none", tooltip: "No VPN", class: "disconnected",
  kind: "none", name: "", state: "", detail: ""
}'
