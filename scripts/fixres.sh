#!/bin/bash

outputs=($(xrandr | grep connected | awk '{print $1}'))

for output in ${outputs[@]}; do
	xrandr --output "${output}" --auto
done

for((i=0;i<${#outputs[@]}-1;++i)); do
	xrandr --output "${outputs[i]}" --right-of "${outputs[i+1]}"
done

xrandr --dpi 96
if [ -f "$HOME/.xrandr.sh" ]; then
	"$HOME/.xrandr.sh"
fi
