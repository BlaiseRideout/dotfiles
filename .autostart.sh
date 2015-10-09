#!/bin/bash

~/scripts/fixres.sh
~/scripts/synaptics.sh &

spacefm -d &
nm-applet &

xrdb -merge ~/.Xresources &
xmodmap ~/.Xmodmap &

compton --config ~/.compton.conf &

~/.fehbg &

xset -dpms
xset s off
xset s noblank
