#!/bin/bash
# Print the name of the primary output, using the same rule as move_workspaces.sh: the largest
# active external monitor (not the laptop panel or the TV), else the laptop panel, else the TV.
# waybar/launch.sh uses it to show the system stats only on the primary monitor.
#
#   primary_output.sh            read the outputs from sway
#   primary_output.sh --stdin    read `swaymsg -t get_outputs -r` JSON from stdin (for testing)
#
# Also works under Hyprland, whose monitor list is converted to the fields used here.

if [[ $1 == --stdin ]]; then
  outputs=$(cat)
elif [[ -n $HYPRLAND_INSTANCE_SIGNATURE ]]; then
  outputs=$(hyprctl monitors all -j | jq '[.[] | {name, model, active: (.disabled | not),
    current_mode: {width, height}}]')
else
  outputs=$(swaymsg -t get_outputs -r)
fi

jq -r '
  ([.[] | select(.active and (.name | startswith("eDP") | not) and .model != "SAMSUNG")]
    | sort_by(-(.current_mode.width * .current_mode.height)) | .[0].name)
  // ([.[] | select(.name | startswith("eDP"))] + [.[] | select(.model == "SAMSUNG")] | .[0].name)
  // empty' <<<"$outputs"
