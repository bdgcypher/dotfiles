#!/usr/bin/env bash
# CPU usage percentage for the Quickshell top bar's cpu module.
#
# Reads /proc/stat and diffs it against the previous read, which is the only way
# to get a figure that actually moves on a 5s refresh (the raw totals are an
# average since boot). State is kept in a runtime file, not in /tmp, so a reboot
# cannot feed it a stale comparison.

state="${XDG_RUNTIME_DIR:-/tmp}/quickshell-cypher-shell-cpu"

read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat

total=$((user + nice + system + idle + iowait + irq + softirq + steal))
prev_total=""
prev_idle=""

if [ -r "$state" ]; then
	read -r prev_total prev_idle <"$state"
fi

# Write the new sample before reporting, so the module only ever sees one line.
printf '%s %s\n' "$total" "$idle" >"$state"

if [ -n "$prev_total" ]; then
	delta_total=$((total - prev_total))
	delta_idle=$((idle - prev_idle))
	if [ "$delta_total" -gt 0 ]; then
		printf '%d\n' $(((delta_total - delta_idle) * 100 / delta_total))
		exit 0
	fi
fi

printf '0\n'
