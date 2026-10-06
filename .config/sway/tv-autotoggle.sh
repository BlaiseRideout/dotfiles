#!/bin/sh
# Turn the Samsung TV's output off when the TV is off, and back on when it's on.
# The TV stays "connected" over HDMI while off, so kanshi can't see it; instead
# watch its network API, which goes away within ~15s of the TV turning off.
# Sway keeps the mode/position/scale kanshi set, so enable restores them.

TV_URL=http://192.168.0.114:8001/api/v2/
INTERVAL=3

# The sway config is shared with the laptop, so only act on the TV's output
tv_output() {
  swaymsg -t get_outputs -r | jq -r '.[] | select(.model == "SAMSUNG") | .name' | head -1
}

tv_state() {
  if curl -s -m 2 -o /dev/null "$TV_URL"; then echo on; else echo off; fi
}

prev=
pending=
while :; do
  state=$(tv_state)
  # Require two matching reads in a row so one dropped request doesn't toggle it.
  if [ "$state" != "$prev" ]; then
    if [ "$state" = "$pending" ]; then
      output=$(tv_output)
      if [ -z "$output" ]; then
        :
      elif [ "$state" = on ]; then
        swaymsg output "$output" enable >/dev/null
      else
        swaymsg output "$output" disable >/dev/null
      fi
      prev=$state
      pending=
    else
      pending=$state
    fi
  else
    pending=
  fi
  sleep "$INTERVAL"
done
