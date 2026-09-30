#!/usr/bin/env bash
# Memory figures for the Quickshell top bar's memory module.
#
# Everything that is not available counts as used. Both figures the module needs
# come from one read of the same two lines -- the percentage for the bar, and the
# used amount in GiB for the tooltip, printed as "{:.1f}GiB used".
#
# One line: "<percent> <used GiB>".

awk '
  /^MemTotal:/     { total = $2 }
  /^MemAvailable:/ { available = $2 }
  END {
    if (total > 0)
      printf "%d %.1f\n", (total - available) * 100 / total, (total - available) / 1048576
  }
' /proc/meminfo
