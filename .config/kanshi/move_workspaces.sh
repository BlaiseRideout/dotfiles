#!/bin/bash

outputs=$(swaymsg -t get_outputs | jq '[.[] | select(.name!="eDP-1")] | sort_by(.current_mode) | .[].name')

if [[ $(echo outputs | wc -l) -eq 1 ]]; then
  echo "dual mode"
  swaymsg workspace 9, move workspace to eDP-1
  swaymsg workspace 10, move workspace to eDP-1
  swaymsg workspace 1, move workspace to $outputs
elif [[ $(outputs | wc -l) -eq 2 ]]; then
  echo "triple mode"
  mon1="$(echo $outputs | cut -d' ' -f 1)"
  mon2="$(echo $outputs | cut -d' ' -f 2)"
  swaymsg workspace 9, move workspace to $mon1
  swaymsg workspace 10, move workspace to eDP-1
  swaymsg workspace 1, move workspace to $mon2
fi
