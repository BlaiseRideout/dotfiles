#!/usr/bin/env bash
# Test the Yoga Book 9i keyboard dock driver (lenovo-yb9-kbdock with 83FF added).
# Run as root, on the Yoga, with the keyboard paired and Bluetooth on if you like
# (the dock sensor doesn't need Bluetooth):
#
#   sudo ~/.dotfiles/yoga/kbdock-test.sh            # load, then guided dock/undock steps
#   sudo ~/.dotfiles/yoga/kbdock-test.sh watch      # load, then just print changes (Ctrl-C to stop)
#   sudo ~/.dotfiles/yoga/kbdock-test.sh unload     # rmmod it again
#
# It loads the DKMS build if present (`modprobe`), otherwise builds a throwaway
# copy in a temp dir and `insmod`s it. Nothing is installed or written outside
# /tmp and the log file. Undo everything with `sudo ... unload` or a reboot.
# Output is also saved to ~/yb9-kbdock-test-<time>.log (owner = SUDO_USER).
#
# What it answers: does the Gen 9 firmware answer the Gen 10 dock protocol
# (BKBD via WMI block E7F300FA, event 0xEB on WM10) and does keyboard_position
# change when the keyboard is docked/undocked?

set -u
MOD=lenovo_yb9_kbdock
MODFILE=lenovo-yb9-kbdock
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kbdock-dkms"
BLOCK=/sys/bus/wmi/devices/E7F300FA-21CD-4003-ADAC-2696135982E6-17
EVENT=/sys/bus/wmi/devices/806BD2A2-177B-481D-BFB5-3BA0BB4A2285-16
ATTR="$BLOCK/keyboard_position"

[ "$(id -u)" = 0 ] || { echo "run as root: sudo $0 ${1:-}" >&2; exit 1; }

home=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
log="$home/yb9-kbdock-test-$(date +%Y%m%d-%H%M%S).log"
[ "${1:-}" = unload ] || { exec > >(tee "$log") 2>&1; echo "logging to $log"; }

if [ "${1:-}" = unload ]; then
  rmmod "$MOD" && echo "unloaded $MOD"
  exit 0
fi

say() { printf '\n== %s\n' "$*"; }
ts()  { date +%H:%M:%S.%N | cut -c1-12; }

say "machine"
echo "kernel:  $(uname -r)"
echo "product: $(cat /sys/class/dmi/id/product_name) / $(cat /sys/class/dmi/id/product_version)"
[ "$(cat /sys/class/dmi/id/product_name)" = 83FF ] || echo "WARNING: not an 83FF; the DMI table in this build only knows 83KJ and 83FF"

say "WMI devices present"
for d in "$EVENT" "$BLOCK"; do
  [ -e "$d" ] && echo "ok   $(basename "$d")  driver=$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)" \
              || echo "MISSING $(basename "$d")"
done
echo "notify_id=$(cat "$EVENT/notify_id" 2>/dev/null) object_id=$(cat "$BLOCK/object_id" 2>/dev/null)"

if lsmod | grep -q "^$MOD "; then
  say "module already loaded (use 'unload' to reload)"
else
  say "load the module"
  if modinfo -F filename "$MODFILE" 2>/dev/null | grep -q '/updates/'; then
    echo "using the DKMS build: $(modinfo -F filename "$MODFILE")"
    modprobe -v "$MODFILE" || echo "modprobe failed"
  else
    tmp=$(mktemp -d /tmp/yb9-kbdock.XXXXXX)
    cp "$SRC/Makefile" "$SRC/lenovo-yb9-kbdock.c" "$tmp/"
    echo "DKMS build not installed; building in $tmp"
    make -C "$tmp" >"$tmp/build.log" 2>&1 || { tail -30 "$tmp/build.log"; echo "build failed"; exit 1; }
    insmod "$tmp/lenovo-yb9-kbdock.ko" || echo "insmod failed"
  fi
fi

say "kernel messages from the load (WMI / yb9)"
dmesg | grep -iE 'yb9|kbdock|BKBD|wmi' | tail -15
lsmod | grep -q "^$MOD " || { echo "module is not loaded; see messages above (DMI mismatch gives a silent -ENODEV)"; exit 1; }

say "did the drivers bind?"
for d in "$EVENT" "$BLOCK"; do
  echo "$(basename "$d") driver: $(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null || echo NONE)"
done
if [ ! -r "$ATTR" ]; then
  echo "NO keyboard_position: the block driver did not probe. Probably wmidev_query_block failed or the"
  echo "returned id != 0x00060000 (-EIO), i.e. the Gen 10 protocol does not match this firmware."
  echo "Check 'dmesg | tail -30'. This is the 'Gen 9 lacks the mechanism' outcome; see docs/yoga-book/kbdock.md."
  exit 2
fi
echo "initial keyboard_position = $(cat "$ATTR")  (0 detached, 1 / 2 docked)"
grep -B1 -A6 'keyboard dock switch' /proc/bus/input/devices

# dev_dbg prints "BKBD=%u SW_TABLET_MODE=%d" per event; enable it (needs debugfs)
mount | grep -q ' /sys/kernel/debug ' || mount -t debugfs none /sys/kernel/debug 2>/dev/null
echo "module $MOD +p" >/sys/kernel/debug/dynamic_debug/control 2>/dev/null \
  && echo "dynamic debug on for $MOD (undo: echo 'module $MOD -p' > /sys/kernel/debug/dynamic_debug/control)"

# hinge sensor's 'keyboard' channel, for correlation (does it move on dock?)
hinge=""
for d in /sys/bus/iio/devices/iio:device*; do
  [ "$(cat "$d/name" 2>/dev/null)" = hinge ] && hinge=$d
done
snapshot() {
  local h=""
  [ -n "$hinge" ] && h="hinge=$(cat $hinge/in_angl0_raw) screen=$(cat $hinge/in_angl1_raw) keyboard=$(cat $hinge/in_angl2_raw)"
  echo "$(ts) keyboard_position=$(cat "$ATTR" 2>&1) $h"
}

# background watcher: print every change of the attribute, and every driver dmesg line
(
  last=""
  while sleep 0.3; do
    now=$(cat "$ATTR" 2>&1)
    [ "$now" != "$last" ] && { echo "$(ts) CHANGE keyboard_position: ${last:-?} -> $now"; last=$now; }
  done
) &
w1=$!
dmesg -w --time-format iso 2>/dev/null | grep --line-buffered -iE 'yb9|kbdock|BKBD' | sed 's/^/dmesg: /' &
w2=$!
trap 'kill $w1 $w2 2>/dev/null; echo; echo "log: $log"' EXIT INT TERM

if [ "${1:-}" = watch ]; then
  say "watching; dock and undock the keyboard (Ctrl-C to stop)"
  wait
  exit 0
fi

say "guided steps (press Enter after each action; watch for CHANGE lines)"
steps=(
  "Take the keyboard completely off the screen and away from the laptop."
  "Dock the keyboard on the bottom screen NEAR THE HINGE (the usual laptop position)."
  "Slide it to the FRONT EDGE of the bottom screen (uncovering the strip near the hinge)."
  "Slide it back near the hinge."
  "Lift it off again (detached)."
  "Dock it near the hinge once more."
)
for s in "${steps[@]}"; do
  echo
  echo ">> $s"
  read -r -p "   done? [Enter] " _ </dev/tty
  sleep 1
  echo "   STATE: $(snapshot)"
done
say "summary: the list of CHANGE lines above is the result"
echo "Expected if the Gen 10 protocol applies: 0 detached, 1 or 2 docked, with a distinct value per position."
echo "If the value never changed from the first reading, the firmware does not report the dock this way."
