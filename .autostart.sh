#!/bin/bash

~/scripts/fixres.sh &
~/scripts/synaptics.sh &

xrdb -merge ~/.Xresources &
xmodmap ~/.Xmodmap &
if [ ! $(pidof unity-settings-daemon) ]; then
	spacefm -d &
	nm-applet &
	dropbox start &
	if [ -f ~/.compton.conf ]; then
		compton --config ~/.compton.conf &
	fi
	if [ -f ~/.fehbg ]; then
		~/.fehbg &
	fi
fi

autocutsel -f
autocutsel -selection PRIMARY -f

xset -dpms
xset s off
xset s noblank
xset r rate 200 50
