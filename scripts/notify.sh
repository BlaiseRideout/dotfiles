#!/bin/bash
len=$(expr length "$@")
len=$(($len>20?$len+1:20))
urxvt -borderLess -geometry ${len}x3 -e bash -c 'echo; echo '"$@"'; termwin=$(xdotool getactivewindow); while true; do if [[ $(xdotool getactivewindow) != $termwin ]]; then exit; fi; done'
