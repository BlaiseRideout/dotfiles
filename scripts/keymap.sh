#!/bin/bash

LAYOUT=$(setxkbmap -query | awk '/layout/{print $2}' | sed 's/,.*//g')
VARIANT=$(setxkbmap -query | awk '/variant/{print $2}' | sed 's/,.*//g')

case $LAYOUT in
	"us") case $VARIANT in
		"dvorak") setxkbmap us && pkill -RTMIN+1 i3blocks ;;
		"") setxkbmap us -variant dvorak && pkill -RTMIN+1 i3blocks ;;
	esac ;;
	"dvorak") setxkbmap us && pkill -RTMIN+1 i3blocks ;;
esac
