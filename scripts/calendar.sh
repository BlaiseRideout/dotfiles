#!/bin/bash
I=$(ps aux | grep cal | grep urxvt | sed "s/^[^ \t]*[ \t]*//g;s/ .*$//g")
if [[ $I ]]; then
	kill $I
else
	urxvt -borderLess -geometry 66x10-0-20 -e bash -c 'echo; cal -3; termwin=$(xdotool getactivewindow); while true; do if [[ $(xdotool getactivewindow) != $termwin ]]; then exit; fi; done'
fi
