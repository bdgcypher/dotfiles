#!/usr/bin/env bash
# Link data for the Quickshell top bar's network tooltip.
#
# waybar's network module fills its tooltip from two things NetworkManager does
# not hand out over the bus: the link's frequency and its bandwidth in each
# direction. Both are read here the same way waybar reads them -- /proc/net/dev
# for the byte counters, differenced against the previous sample so the figure is
# a rate rather than a total since boot -- with one deliberate swap: waybar gets
# the frequency from `iw`, which is not installed on this machine (so waybar
# itself reports no frequency here), and nmcli is asked instead.
#
# Output, one line, tab separated: <frequency GHz>\t<down bytes/s>\t<up bytes/s>
# The frequency is empty on a wired link.
#
#   net-tooltip.sh wlp45s0  ->  "5.56\t12345\t678"
#
# The sample lives in the runtime directory rather than /tmp so a reboot cannot
# feed it a stale counter and produce a nonsense rate.

set -u

iface="${1:-}"
if [ -z "$iface" ]; then
	printf '\t0\t0\n'
	exit 0
fi

# ── frequency ────────────────────────────────────────────────────────────────
# nmcli reports the active access point's frequency in MHz; waybar's {frequency}
# is GHz, which is what the tooltip format appends " GHz" to.
freq=""
if [ -d "/sys/class/net/$iface/wireless" ]; then
	probe=$(nmcli -t -f IN-USE,FREQ dev wifi 2>/dev/null | awk -F: '$1=="*" {print $2; exit}')
	if [ -n "${probe:-}" ]; then
		freq=$(printf '%s' "$probe" | awk '{ printf "%.6g", $1 / 1000 }')
	fi
fi

# ── bandwidth ────────────────────────────────────────────────────────────────
# Fields 2..9 of a /proc/net/dev row are the receive counters and 10..17 the
# transmit ones, so the byte totals are $2 and $10 once the interface name is $1.
counters=$(awk -v i="$iface:" '$1 == i { print $2, $10; exit }' /proc/net/dev)
if [ -z "$counters" ]; then
	printf '%s\t0\t0\n' "$freq"
	exit 0
fi
read -r rx tx <<<"$counters"

# /proc/uptime, so the elapsed time cannot be skewed by a clock jump.
now=$(awk '{ print $1 }' /proc/uptime)

state="${XDG_RUNTIME_DIR:-/tmp}/quickshell-hayami-shell-net"
down=0
up=0

if [ -r "$state" ]; then
	read -r prev_iface prev_time prev_rx prev_tx <"$state" || true
	if [ "${prev_iface:-}" = "$iface" ]; then
		elapsed=$(awk -v now="$now" -v before="${prev_time:-0}" 'BEGIN { printf "%.3f", now - before }')
		# A counter can only go backwards if the interface was reset; treat that
		# and a zero gap as "no rate yet" rather than reporting a spike.
		if awk -v e="$elapsed" -v a="$rx" -v b="${prev_rx:-0}" -v c="$tx" -v d="${prev_tx:-0}" \
			'BEGIN { exit !(e > 0 && a >= b && c >= d) }'; then
			read -r down up <<<"$(awk -v e="$elapsed" -v a="$rx" -v b="$prev_rx" -v c="$tx" -v d="$prev_tx" \
				'BEGIN { printf "%d %d", (a - b) / e, (c - d) / e }')"
		fi
	fi
fi

printf '%s %s %s %s\n' "$iface" "$now" "$rx" "$tx" >"$state"

printf '%s\t%s\t%s\n' "$freq" "$down" "$up"
