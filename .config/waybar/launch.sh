#!/bin/bash
# Run Waybar with WAYBAR_PRIMARY set to the primary output (see config.jsonc, where the system
# stats only show on that output), and restart it when the primary changes, e.g. when the laptop
# is docked. Waybar can't re-read an environment variable at runtime, so a restart it is.
#
# Also keeps Waybar running: when it exits (`killall waybar` on a sway reload), it is started
# again, so a second launcher would only duplicate it. Hence the lock.
#
# Prefers the newer self-built Waybar in ~/.local/opt/waybar (tray ignore-list and icon
# wildcards; build script in ~/.local/src/waybar), else the system one.

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/waybar-launch.lock"
flock -n 9 || exit 0

# Whether the compositor this was started from is still running. The systemd user session
# outlives a login, so without this a launcher left from a Sway session would keep the lock and
# start Waybar on the next session (Hyprland, say) with the old session's environment.
# Hyprland is checked first: SWAYSOCK can linger in its environment.
session_alive() {
    if [[ -n $HYPRLAND_INSTANCE_SIGNATURE ]]; then
        local lock=$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.lock
        [[ -f $lock ]] && kill -0 "$(head -n1 "$lock")" 2>/dev/null
    else
        [[ -z $SWAYSOCK || -S $SWAYSOCK ]]
    fi
}

# Hyprland writes its lock file a moment after it runs the autostart, so give it a few seconds
# before deciding the session is gone (else Waybar never starts at login)
for _ in {1..20}; do
    session_alive && break
    sleep 0.5
done

PRIMARY_OUTPUT=${WAYBAR_PRIMARY_CMD:-~/.config/kanshi/primary_output.sh}   # the override is for testing
POLL=3   # seconds between checks of the primary output

pid=
trap '[[ -n $pid ]] && kill "$pid" 2>/dev/null; exit 0' TERM INT HUP

while session_alive; do
    # Picked on every start, so a fresh build is used after the next restart
    if [[ -x ~/.local/opt/waybar/bin/waybar ]]; then
        waybar=~/.local/opt/waybar/bin/waybar
    else
        waybar=$(command -v waybar) || exit 1
    fi
    export WAYBAR_PRIMARY
    WAYBAR_PRIMARY=$("$PRIMARY_OUTPUT")
    "$waybar" 9>&- &
    pid=$!
    # Wait for Waybar to exit, or for another output to become the primary
    while kill -0 "$pid" 2>/dev/null; do
        sleep "$POLL"
        session_alive || { kill "$pid" 2>/dev/null; break; }
        [[ $("$PRIMARY_OUTPUT") == "$WAYBAR_PRIMARY" ]] && continue
        sleep 2   # outputs change in several steps; let them settle before restarting
        [[ $("$PRIMARY_OUTPUT") == "$WAYBAR_PRIMARY" ]] || { kill "$pid" 2>/dev/null; break; }
    done
    wait "$pid" 2>/dev/null
    sleep 1
done
