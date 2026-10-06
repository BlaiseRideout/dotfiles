#!/bin/bash
# Assign workspaces to outputs by role:
#   primary   (largest external monitor): 1-8
#   secondary (next external monitor):    9
#   tertiary  (laptop panel, else TV):    10
# Each workspace gets a fallback list of outputs; sway uses the first one that's
# enabled, so a missing role falls through (e.g. 9 goes to the laptop with only
# one external monitor, 10 goes to the secondary while the TV is off) and moves
# back when that output is re-enabled.
#
# DRY_RUN=1 reads `swaymsg -t get_outputs -r` JSON from stdin and prints the
# commands instead of running them.

if [[ $DRY_RUN ]]; then
  outputs=$(cat)
  msg() { echo "swaymsg $*"; }
else
  outputs=$(swaymsg -t get_outputs -r)
  msg() { swaymsg "$@"; }
fi

# Laptop panels first, then the TV; inactive ones are kept so workspaces return to them
tertiaries=$(jq -r '[.[] | select(.name | startswith("eDP"))] + [.[] | select(.model == "SAMSUNG")] | .[].name' <<<"$outputs")
# Active external monitors, largest first
externals=$(jq -r '[.[] | select(.active and (.name | startswith("eDP") | not) and .model != "SAMSUNG")]
  | sort_by(-(.current_mode.width * .current_mode.height)) | .[].name' <<<"$outputs")
active=$(jq -r '.[] | select(.active) | .name' <<<"$outputs")

primary=$(sed -n 1p <<<"$externals")
secondary=$(sed -n 2p <<<"$externals")
if [[ ! $primary ]]; then
  # Laptop on its own
  primary=$(head -1 <<<"$tertiaries")
fi

uniq_words() { tr ' \n' '\n\n' <<<"$*" | awk 'NF && !seen[$0]++' | tr '\n' ' '; }
ws_primary="$primary"
ws_9=$(uniq_words "$secondary $tertiaries $primary")
ws_10=$(uniq_words "$tertiaries $secondary $primary")

# First enabled output in a fallback list
first_active() {
  for o in $1; do
    grep -qx "$o" <<<"$active" && { echo "$o"; return; }
  done
}

echo "primary $primary, workspace 9 on $(first_active "$ws_9"), workspace 10 on $(first_active "$ws_10")" >&2

for I in $(seq 1 8); do
  msg "workspace $I output $ws_primary"
done
msg "workspace 9 output $(echo $ws_9)"
msg "workspace 10 output $(echo $ws_10)"

# Move existing workspaces, finishing with 1 focused and 9/10 visible
msg "workspace 10, move workspace to $(first_active "$ws_10")"
msg "workspace 9, move workspace to $(first_active "$ws_9")"
for I in $(seq 8 -1 1); do
  msg "workspace $I, move workspace to $primary"
done
