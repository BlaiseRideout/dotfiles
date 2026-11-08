#!/bin/bash
# Brightness keys: brightness.sh up|down. Steps every backlight in
# /sys/class/backlight by 5% (the Yoga Book has one per panel, intel_backlight
# and card1-eDP-2-backlight; brightnessctl alone only drives the first), then
# shows Noctalia's OSD with the result. Does nothing on machines without one.
# The 2% floor keeps the OLEDs from being turned fully off with the key.
step=5
case $1 in
    up)   delta="+${step}%" ;;
    down) delta="${step}%-" ;;
    *)    echo "usage: ${0##*/} up|down" >&2; exit 2 ;;
esac

shown=
while IFS=, read -r dev _ _ pct _; do
    [ -n "$dev" ] || continue
    brightnessctl -q -d "$dev" --min-value=8 set "$delta" >/dev/null
    [ -n "$shown" ] || shown=$(brightnessctl -m -d "$dev" | cut -d, -f4)
done < <(brightnessctl -l -m -c backlight 2>/dev/null)

[ -n "$shown" ] && noctalia msg brightness-osd "$shown" >/dev/null 2>&1
exit 0
