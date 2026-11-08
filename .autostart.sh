#!/bin/bash

~/scripts/synaptics.sh &

xrdb -merge ~/.Xresources &
xmodmap ~/.Xmodmap &
command -v nm-applet >/dev/null && { pidof nm-applet || nm-applet & }

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

# Screens off after 15 minutes idle, to match swayidle and hypridle (the Wayland
# hosts); the X screensaver and blanking stay off
xset +dpms
xset dpms 900 900 900
xset s off
xset s noblank
xset r rate 200 50
