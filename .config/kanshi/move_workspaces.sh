#!/bin/bash

outputs=$(swaymsg -t get_outputs | jq '[.[] | select(.name!="eDP-1")] | sort_by(.name) | sort_by(.current_mode) | .[].name')

NUM=$(echo $outputs | wc -w)

if [[ $NUM -eq 1 ]]; then
  echo "dual mode, primary $outputs"
  swaymsg workspace 9, move workspace to eDP-1
  swaymsg workspace 10, move workspace to eDP-1
  for I in $(seq 8 -1 1); do
    swaymsg workspace $I, move workspace to $outputs
  done
elif [[ $NUM -eq 2 ]]; then
  secondary="$(echo $outputs | cut -d' ' -f 1)"
  primary="$(echo $outputs | cut -d' ' -f 2)"
  echo "triple mode, primary $primary secondary $secondary"
  swaymsg workspace 9, move workspace to $secondary
  swaymsg workspace 10, move workspace to eDP-1
  for I in $(seq 8 -1 1); do
    swaymsg workspace $I, move workspace to $primary
  done
fi
