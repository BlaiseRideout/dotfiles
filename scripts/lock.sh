#!/bin/bash

NUM_OPS=8
ALL_OPS=15

corrupt_image () {
  IMAGE_PATH="$1"
  OP="$2"

  case $OP in
    0) echo "minimum"; mogrify -statistic minimum 10 $IMAGE_PATH ;;
    1) echo "maximum"; mogrify -statistic maximum 10 $IMAGE_PATH ;;
    2) echo "sample"; mogrify -sample 10% -sample 1000% $IMAGE_PATH ;;
    3) echo "scale"; mogrify -scale 10% -scale 1000% $IMAGE_PATH ;;
    4) echo "rms"; mogrify -statistic rms 10 $IMAGE_PATH ;;
    5) echo "standarddeviation"; mogrify -statistic standarddeviation 10 $IMAGE_PATH ;;
    6) echo "gradient"; mogrify -statistic gradient 10 $IMAGE_PATH ;;
    7) echo "mean"; mogrify -statistic mean 10 $IMAGE_PATH ;;

    # Slower ops
    8) echo "resize"; mogrify -resize 10% -resize 1000% $IMAGE_PATH ;;
    9) echo "spread"; mogrify -spread 10 $IMAGE_PATH ;;
    10) echo "median"; mogrify -statistic median 10 $IMAGE_PATH ;;
    11) echo "mode"; mogrify -statistic mode 10 $IMAGE_PATH ;;
    12) echo "nonpeak"; mogrify -statistic nonpeak 10 $IMAGE_PATH ;;
    13) echo "blur"; mogrify -blur 5x5 $IMAGE_PATH ;;
    14) echo "paint"; mogrify -paint 3 $IMAGE_PATH ;;
  esac
}

if [[ "$1" == "bench" ]]; then
  echo "Benchmark:"
  export TIMEFORMAT='%R'
  for OP in $(seq 0 $(( $ALL_OPS-1 ))); do
    echo $OPERATION
    # UNIX timestamp concatenated with nanoseconds
    T="$(date +%s%N)"

    for OUTPUT in `swaymsg -t get_outputs | jq -r '.[] | select(.active == true) | .name'`
    do
      IMAGE=/tmp/$OUTPUT-lock.png
      grim -o $OUTPUT $IMAGE

      corrupt_image $IMAGE $OP
    done

    # Time interval in nanoseconds
    T="$(($(date +%s%N)-T))"
    # Milliseconds
    M="$((T/1000000))"
    echo "Time in millis: ${M}"
  done
  exit
fi

OPERATION=$((RANDOM % $NUM_OPS))

# Active outputs, under Sway or Hyprland
outputs() {
  if [[ -n $HYPRLAND_INSTANCE_SIGNATURE ]]; then
    hyprctl monitors -j | jq -r '.[].name'
  else
    swaymsg -t get_outputs | jq -r '.[] | select(.active == true) | .name'
  fi
}

# Hyprland: hyprlock (~/.config/hypr/hyprlock.conf). Nix's hyprlock (nhuto-Mint)
# can only authenticate once build/hyprland/system-setup.sh has given it a PAM
# service; swaylock below until then. A distro's hyprlock brings its own.
hyprlock_ready() {
  local bin
  bin=$(command -v hyprlock) || return 1
  [[ $(readlink -f "$bin") == /nix/store/* ]] || return 0
  [[ -e /etc/pam.d/hyprlock && -x /run/wrappers/bin/unix_chkpwd ]]
}
# Yoga Book 9i, two things hyprlock does not do right by itself. Yoga only (the check is the DMI
# product version); everything else uses the stock config.
#  1. Its `path = screenshot` background comes out upside down on the top panel (mounted
#     rotated 180 degrees, Hyprland transform 2): hyprlock does not undo the screencopy
#     transform, so the blurred workspace behind the password box was flipped, and flashed
#     flipped again as the lock faded out. grim captures in the logical (upright)
#     orientation, so for each rotated panel capture it here and give hyprlock that image for
#     the monitor, via one extra `background` per panel right after the stock one (the stock
#     screenshot is then covered).
#  2. The password box is drawn on every monitor. While the top panel is lit it is the one you
#     look at, and a second box on the bottom panel (under the on-screen keyboard or the
#     docked keyboard) is only in the way: with both laptop panels on, the box is drawn on
#     every monitor except the bottom panel. With only one lit, or none of the laptop panels
#     on (docked to external monitors), the stock config is untouched in this respect.
# Both work on a copy of hyprlock.conf in ~/.cache/hyprlock. Prints the config to use (or
# nothing: use the stock one).
yoga_lock_conf() {
  [[ $(< /sys/class/dmi/id/product_version) == *"Yoga Book 9"* ]] || return 0
  command -v jq >/dev/null || return 0
  local dir=${XDG_CACHE_HOME:-$HOME/.cache}/hyprlock src=$HOME/.config/hypr/hyprlock.conf
  local conf=$dir/hyprlock.conf extra="" out png top bottom fields="" mons
  [[ -r $src ]] || return 0
  mkdir -p "$dir" || return 0
  mons=$(hyprctl monitors -j) || return 0
  if command -v grim >/dev/null; then
    while read -r out; do
      png=$dir/$out.png
      grim -o "$out" "$png" 2>/dev/null || continue
      extra+=$'\n'"background {
    monitor = $out
    path = $png
    blur_passes = 3
    blur_size = 8
    noise = 0.02
    brightness = 0.6
}"$'\n'
    done < <(jq -r '.[] | select(.transform != 0 and (.description | test("Samsung Display Corp"))) | .name' <<<"$mons")
  fi
  # the panels' output names, top first (yoga/hypr/yoga.lua)
  if panels=$(hyprctl repl 'return table.concat({yoga_panel_outputs()}, ",")' 2>/dev/null) \
      && [[ $panels =~ ^([^,\ ]+),([^,\ ]+)$ ]]; then
    top=${BASH_REMATCH[1]} bottom=${BASH_REMATCH[2]}
    if [[ $(jq -r --arg a "$top" --arg b "$bottom" \
        '[.[] | select((.name == $a or .name == $b) and (.disabled | not))] | length' <<<"$mons") == 2 ]]; then
      fields=$(jq -r --arg b "$bottom" '.[] | select(.disabled | not) | select(.name != $b) | .name' <<<"$mons" | tr '\n' ' ')
    fi
  fi
  [[ -n $extra || -n $fields ]] || return 0
  awk -v extra="$extra" -v fields="$fields" '
    BEGIN { n = split(fields, names, " ") }
    /^input-field[ ]*\{/ && n > 0 { infield = 1; blk = "" }
    infield { blk = blk $0 "\n"; if ($0 ~ /^\}/) {
        infield = 0
        for (i = 1; i <= n; i++) { b = blk; sub(/monitor =[^\n]*/, "monitor = " names[i], b); printf "%s", b }
      }
      next }
    {print}
    /^background[ ]*\{/ {inbg=1}
    inbg && /^\}/ && !done {print extra; done=1; inbg=0}
  ' "$src" > "$conf.tmp" && mv "$conf.tmp" "$conf" && echo "$conf"
}

if [[ $1 == "--yoga-lock-conf" ]]; then yoga_lock_conf; exit 0; fi

if [[ -n $HYPRLAND_INSTANCE_SIGNATURE ]] && hyprlock_ready; then
  # Already locked: nothing to do. A hyprlock that's been up a while without the
  # session being locked is a hung leftover, which would otherwise swallow every
  # lock request, so clear it out.
  # "Locked" is logind's LockedHint, which hyprlock never sets itself, so this
  # script does (below) for as long as the hyprlock it started runs. Without
  # that the hint was always "no", and a second lock request (hypridle's
  # timeout, Mod+L) SIGKILLed the live lock screen: Hyprland showed its
  # "lockscreen crashed" screen until the new hyprlock came up (2026-11-08).
  if pid=$(pidof hyprlock); then
    locked=$(loginctl show-session "${XDG_SESSION_ID:-auto}" -p LockedHint --value 2>/dev/null)
    up=$(ps -o etimes= -p "${pid%% *}" 2>/dev/null)
    if [[ $locked == yes || ${up:-0} -lt 5 ]]; then
      exit 0
    fi
    pkill -9 -x hyprlock
  fi
  locked_hint() {
    busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto \
      org.freedesktop.login1.Session SetLockedHint b "$1" >/dev/null 2>&1
  }
  args=()
  conf=$(yoga_lock_conf)
  [[ -n $conf ]] && args=(-c "$conf")
  locked_hint true
  # not exec: the hint is cleared when hyprlock goes (unlock, or killed)
  hyprlock "${args[@]}"
  rc=$?
  # (not if a newer lock.sh has already replaced this hyprlock with its own)
  pidof hyprlock >/dev/null || locked_hint false
  exit $rc
fi

if [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
  IMAGE=/tmp/i3lock.png
  LOCKARGS="-f"

  for OUTPUT in $(outputs)
  do
    IMAGE=/tmp/$OUTPUT-lock.png
    grim -o $OUTPUT $IMAGE
    corrupt_image $IMAGE $OPERATION
    LOCKARGS="${LOCKARGS} --image ${OUTPUT}:${IMAGE}"
    IMAGES="${IMAGES} ${IMAGE}"
  done
  swaylock $LOCKARGS $@
  rm $IMAGES
else
  scrot /tmp/scrot.png
  corrupt_image /tmp/scrot.png $OPERATION
  i3lock -i /tmp/scrot.png $@
fi
