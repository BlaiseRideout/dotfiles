#!/bin/sh
# Keep the screen awake during video calls, so hypridle neither locks nor turns
# the monitors off mid-call. Counts as a call when either:
#   - the Zoom app has its meeting window open (class "zoom" or "Zoom"), or
#   - a browser is capturing the microphone (Zoom's web client, and any other call).
# It does what pressing Noctalia's caffeine button does: on when a call starts,
# off again once it has been over for a while. (hypridle ignores systemd's idle
# inhibitors, and D-Bus ones are off in hypridle.conf, so Noctalia's Wayland
# inhibitor is the way in.) Turning caffeine on by hand during a call is undone
# when the call ends.

# Only one copy, so a second `exec` can't fight the first
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/call-inhibit.lock"
flock -n 9 || exit 0

INTERVAL=10
BROWSERS='firefox|chromium|chrome|brave|zen|librewolf|vivaldi'

# Same compositor-still-running check as tv-autotoggle.sh
session_alive() {
  lock=$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.lock
  [ -f "$lock" ] && kill -0 "$(head -n1 "$lock")" 2>/dev/null
}
for _ in $(seq 20); do
  session_alive && break
  sleep 0.5
done

in_call() {
  hyprctl clients -j | jq -e 'any(.[]; (.class | test("^zoom$"; "i")) and (.title | test("^(Zoom )?Meeting")))' >/dev/null && return 0
  # A browser capturing the mic (a muted call still holds its stream open)
  pactl -f json list source-outputs 2>/dev/null |
    jq -e --arg re "($BROWSERS)" 'any(.[]; ((.properties["application.process.binary"] // "") + " " + (.properties["application.name"] // "")) | test($re; "i"))' >/dev/null
}

GRACE=3   # quiet ticks before a call counts as over
awake=0 quiet=0
while session_alive; do
  if in_call; then
    quiet=0
    if [ "$awake" = 0 ]; then
      noctalia msg caffeine-enable >/dev/null 2>&1 && awake=1
    fi
  elif [ "$awake" = 1 ]; then
    quiet=$((quiet + 1))
    if [ "$quiet" -ge "$GRACE" ]; then
      noctalia msg caffeine-disable >/dev/null 2>&1
      awake=0 quiet=0
    fi
  fi
  sleep "$INTERVAL"
done
[ "$awake" = 0 ] || noctalia msg caffeine-disable >/dev/null 2>&1
