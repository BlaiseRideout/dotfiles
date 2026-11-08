#!/usr/bin/env bash
# The laptop's own battery: prints "<percent>\t<status>" for the first BAT* in
# /sys/class/power_supply (status as the kernel reports it: Charging, Discharging,
# Full, Not charging, Unknown). Prints nothing on a machine without one.
for b in /sys/class/power_supply/BAT*; do
  [ -r "$b/capacity" ] || continue
  printf '%s\t%s\n' "$(cat "$b/capacity")" "$(cat "$b/status" 2>/dev/null)"
  exit 0
done
