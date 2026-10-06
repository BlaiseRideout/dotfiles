#!/bin/sh
# Turn the Samsung TV's output off when the TV is off, and back on when it's on.
# The TV stays "connected" over HDMI while off, so kanshi can't see it; instead
# watch its network API, which goes away within ~15s of the TV turning off.
# Sway keeps the mode/position/scale kanshi set, so enable restores them.

TV_URL=http://192.168.0.114:8001/api/v2/
INTERVAL=3

# The sway config is shared with the laptop, so only act on the TV's output.
# Prints "<name> <active>", or nothing if the TV isn't connected.
tv_output() {
  swaymsg -t get_outputs -r | jq -r '.[] | select(.model == "SAMSUNG") | "\(.name) \(.active)"' | head -1
}

tv_state() {
  if curl -s -m 2 -o /dev/null "$TV_URL"; then echo true; else echo false; fi
}

# Compare against sway's actual output state rather than the last change, so
# something else re-enabling the output (e.g. re-running kanshi) gets corrected.
last=
while :; do
  want=$(tv_state)
  # Require two matching reads in a row so one dropped request doesn't toggle it.
  if [ "$want" = "$last" ]; then
    set -- $(tv_output)
    if [ -n "$1" ] && [ "$2" != "$want" ]; then
      if [ "$want" = true ]; then
        swaymsg output "$1" enable >/dev/null
      else
        swaymsg output "$1" disable >/dev/null
      fi
    fi
  fi
  last=$want
  sleep "$INTERVAL"
done
