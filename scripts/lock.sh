#!/bin/bash

scrot /tmp/scrot.png

OPERATION=$((RANDOM % 15))

case $OPERATION in
	0) echo "minimum"; mogrify -statistic minimum 10 /tmp/scrot.png ;;
	1) echo "maximum"; mogrify -statistic maximum 10 /tmp/scrot.png ;;
	2) echo "gradient"; mogrify -statistic gradient 10 /tmp/scrot.png ;;
	3) echo "mean"; mogrify -statistic mean 10 /tmp/scrot.png ;;
	4) echo "median"; mogrify -statistic median 10 /tmp/scrot.png ;;
	5) echo "mode"; mogrify -statistic mode 10 /tmp/scrot.png ;;
	6) echo "nonpeak"; mogrify -statistic nonpeak 10 /tmp/scrot.png ;;
	7) echo "rms"; mogrify -statistic rms 10 /tmp/scrot.png ;;
	8) echo "standarddeviation"; mogrify -statistic standarddeviation 10 /tmp/scrot.png ;;
	9) echo "blur"; mogrify -blur 5x10 /tmp/scrot.png ;;
	10) echo "paint"; mogrify -paint 3 /tmp/scrot.png ;;
	11) echo "resize"; mogrify -resize 10% -resize 1000% /tmp/scrot.png ;;
	12) echo "sample"; mogrify -sample 10% -sample 1000% /tmp/scrot.png ;;
	13) echo "scale"; mogrify -scale 10% -scale 1000% /tmp/scrot.png ;;
	14) echo "spread"; mogrify -spread 10 /tmp/scrot.png ;;
esac

i3lock -i /tmp/scrot.png $@
