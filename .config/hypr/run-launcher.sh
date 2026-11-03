#!/bin/bash
# $mod+r: pick any command on PATH (fuzzel) and run it, detached so it outlives
# this script. Hyprland's version of Sway's kitty + fzf launcher; no terminal
# to start, so it opens at once.

cmd=$(compgen -c | grep -v '^[[:punct:]]' | sort -u |
  fuzzel --dmenu --no-icons --placeholder='Run a command')
[[ -n $cmd ]] && setsid -f sh -c "$cmd" >/dev/null 2>&1
exit 0
