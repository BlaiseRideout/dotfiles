#!/bin/bash

OPERATION=$((RANDOM % 15))

corrupt_image () {
  IMAGE_PATH="$1"

  case $OPERATION in
    0) echo "minimum"; mogrify -statistic minimum 10 $IMAGE_PATH ;;
    1) echo "maximum"; mogrify -statistic maximum 10 $IMAGE_PATH ;;
    2) echo "gradient"; mogrify -statistic gradient 10 $IMAGE_PATH ;;
    3) echo "mean"; mogrify -statistic mean 10 $IMAGE_PATH ;;
    4) echo "median"; mogrify -statistic median 10 $IMAGE_PATH ;;
    5) echo "mode"; mogrify -statistic mode 10 $IMAGE_PATH ;;
    6) echo "nonpeak"; mogrify -statistic nonpeak 10 $IMAGE_PATH ;;
    7) echo "rms"; mogrify -statistic rms 10 $IMAGE_PATH ;;
    8) echo "standarddeviation"; mogrify -statistic standarddeviation 10 $IMAGE_PATH ;;
    9) echo "blur"; mogrify -blur 5x10 $IMAGE_PATH ;;
    10) echo "paint"; mogrify -paint 3 $IMAGE_PATH ;;
    11) echo "resize"; mogrify -resize 10% -resize 1000% $IMAGE_PATH ;;
    12) echo "sample"; mogrify -sample 10% -sample 1000% $IMAGE_PATH ;;
    13) echo "scale"; mogrify -scale 10% -scale 1000% $IMAGE_PATH ;;
    14) echo "spread"; mogrify -spread 10 $IMAGE_PATH ;;
  esac
}

if [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
  IMAGE=/tmp/i3lock.png
  LOCKARGS=""

  for OUTPUT in `swaymsg -t get_outputs | jq -r '.[] | select(.active == true) | .name'`
  do
      IMAGE=/tmp/$OUTPUT-lock.png
      grim -o $OUTPUT $IMAGE
      corrupt_image $IMAGE
      LOCKARGS="${LOCKARGS} --image ${OUTPUT}:${IMAGE}"
      IMAGES="${IMAGES} ${IMAGE}"
  done
  swaylock $LOCKARGS $@
  rm $IMAGES
else
  scrot /tmp/scrot.png
  corrupt_image /tmp/scrot.png
  i3lock -i /tmp/scrot.png $@
fi
