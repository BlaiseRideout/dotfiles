#!/bin/bash

#swaymsg -t get_tree --raw | jq '.nodes[0].nodes[0].floating_nodes.[] | .name' | fzf | xargs swaymsg

jq_filter='
    # descend to workspace or scratchpad
    .nodes[].nodes[]
    # save workspace name as .w
    | {"w": .name} + (
      if (.nodes|length) > 0 then # workspace
        [recurse(.nodes[])]
      else # scratchpad
        []
      end
      + .floating_nodes
      | .[]
      # select nodes with no children (windows)
      | select(.nodes==[])
    )
    | [
      "<span size=\"xx-small\">\(.id)</span>",
      # remove markup and index from workspace name, replace scratch with "[S]"
      "<span size=\"xx-small\">\(.w | gsub("^[^:]*:|<[^>]*>"; "") | sub("__i3_scratch"; "[S]"))</span>",
      # get app name (or window class if xwayland)
      "<span weight=\"bold\">\(if .app_id == null then .window_properties.class else .app_id end)</span>",
      "<span style=\"italic\">\(.name)</span>"
    ] | @tsv
'

swaymsg -t get_tree |
  jq -r "$jq_filter" |
  wofi -m --insensitive --show dmenu --prompt='Focus a window' |
  {
    read -r id name && swaymsg "[con_id=$id]" focus
  }
