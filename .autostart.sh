#!/bin/bash

~/scripts/synaptics.sh &

xrdb -merge ~/.Xresources &
xmodmap ~/.Xmodmap &
pidof nm-applet || nm-applet &

if [ ! $(pidof unity-settings-daemon) ]; then
	spacefm -d &
	dropbox start &
fi

if [ -f ~/.fehbg ]; then
	~/.fehbg &
else
  xsetroot -solid dimgrey -cursor_name left_ptr &
fi

autocutsel -f
autocutsel -selection PRIMARY -f

xset -dpms
xset s off
xset s noblank
xset r rate 200 50
