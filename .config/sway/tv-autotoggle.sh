#!/bin/sh
# Turn the Samsung TV's output off when the TV is off, and back on when it's on.
# The TV stays "connected" over HDMI while off, so kanshi can't see it; instead
# watch its network API, which goes away within ~15s of the TV turning off.
# Sway keeps the mode/position/scale kanshi set, so enable restores them.
# Under Hyprland it calls tv_set() in hypr/hyprland.lua, which keeps the TV's
# mode and moves the workspaces itself.

# Only one copy, so a second `exec` can't fight the first
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/tv-autotoggle.lock"
flock -n 9 || exit 0

# Whether the compositor this was started from is still running, so a copy left
# from an earlier login quits (and frees the lock) instead of acting on the next
# session with the old one's environment. Same check as waybar/launch.sh.
session_alive() {
  if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    lock=$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.lock
    [ -f "$lock" ] && kill -0 "$(head -n1 "$lock")" 2>/dev/null
  else
    [ -z "$SWAYSOCK" ] || [ -S "$SWAYSOCK" ]
  fi
}

# Hyprland writes its lock file a moment after it runs the autostart, so give it a few seconds
# before deciding the session is gone (else this never starts at login)
for _ in $(seq 20); do
  session_alive && break
  sleep 0.5
done

TV_URL=http://192.168.0.114:8001/api/v2/
INTERVAL=3

# The sway config is shared with the laptop, so only act on the TV's output.
# Prints "<name> <active>", or nothing if the TV isn't connected.
tv_output() {
  if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    # A TV that was off at login has no EDID, so no model: an HDMI port without one (see tv_set)
    hyprctl monitors all -j | jq -r '.[] | select(.model == "SAMSUNG" or (.model == "" and (.name | startswith("HDMI-A-"))))
      | "\(.name) \(.disabled | not)"' | head -1
  else
    swaymsg -t get_outputs -r | jq -r '.[] | select(.model == "SAMSUNG") | "\(.name) \(.active)"' | head -1
  fi
}

tv_state() {
  if curl -s -m 2 -o /dev/null "$TV_URL"; then echo true; else echo false; fi
}

# Compare against sway's actual output state rather than the last change, so
# something else re-enabling the output (e.g. re-running kanshi) gets corrected.
last=
while session_alive; do
  want=$(tv_state)
  # Require two matching reads in a row so one dropped request doesn't toggle it.
  if [ "$want" = "$last" ]; then
    set -- $(tv_output)
    if [ -n "$1" ] && [ "$2" != "$want" ] && [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
      hyprctl -q eval "tv_set($want)"
    elif [ -n "$1" ] && [ "$2" != "$want" ]; then
      if [ "$want" = true ]; then
        swaymsg output "$1" enable >/dev/null
      else
        swaymsg output "$1" disable >/dev/null
      fi
      # Put workspace 10 back on the TV, or on the secondary while it's off
      ~/.config/kanshi/move_workspaces.sh --keep-view >/dev/null 2>&1
    fi
  fi
  last=$want
  sleep "$INTERVAL"
done
