#!/bin/bash

~/scripts/fixres.sh
~/scripts/synaptics.sh &

spacefm -d &
nm-applet &
dropbox start &

xrdb -merge ~/.Xresources &
xmodmap ~/.Xmodmap &

compton --config ~/.compton.conf &

~/.fehbg &

autocutsel -f
autocutself -selection PRIMARY -f

xset -dpms
xset s off
xset s noblank
xset r rate 200 50
