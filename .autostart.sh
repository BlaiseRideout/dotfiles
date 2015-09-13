#!/bin/bash

~/scripts/fixres.sh

xrdb -merge ~/.Xresources &
xmodmap ~/.Xmodmap &

compton --config ~/.compton.conf &

~/.fehbg &

xset -dpms
xset s off
xset s noblank
