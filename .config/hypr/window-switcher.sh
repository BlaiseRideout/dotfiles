#!/bin/bash
# Pick a window from a list (fuzzel) and focus it, including ones hidden in the
# scratchpad or another special workspace ([S]). Hyprland's version of
# sway/sway_scratchpad.sh ($mod+minus). Each line gets the app's icon (fuzzel
# reads rofi's "\0icon\x1f<name>" suffix); the address goes in a hidden column.

hyprctl clients -j |
  jq -r '.[] | select(.mapped)
    | "\(.address)\t\(.workspace.name | sub("^special:"; "[S] "))   \(.title)\u0000icon\u001f\(.class | ascii_downcase)"' |
  fuzzel --dmenu --with-nth=2 --accept-nth=1 --placeholder='Switch to window' |
  {
    read -r addr && [[ $addr == 0x* ]] && hyprctl -q dispatch "hl.dsp.focus({ window = 'address:$addr' })"
  }
