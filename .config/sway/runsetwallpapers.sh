#!/bin/bash

if [[ $1 ]]; then
  rm -f ~/.config/sway/wallpapers.json
  ln -s "$1" ~/.config/sway/wallpapers.json
fi

pkill -f '^python3 [^ ]*setwallpapers.py'
python3 ~/.config/sway/setwallpapers.py -c ~/.config/sway/wallpapers.json -i 15m -v & disown
