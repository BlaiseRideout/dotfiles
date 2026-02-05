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

if [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
  IMAGE=/tmp/i3lock.png
  LOCKARGS="-f"

  for OUTPUT in `swaymsg -t get_outputs | jq -r '.[] | select(.active == true) | .name'`
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
