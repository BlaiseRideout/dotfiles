#!/bin/bash
# $mod+v: clipboard history (cliphist, recording since hyprland.lua's start-up)
# in fzf, in a floating kitty window (hyprland.lua's clipboard-picker rule).
# The preview on the right shows the whole entry, wrapped, or the image at full
# size (kitty's image protocol).
#
# Vim-style keys, Dvorak's like .vimrc and the window keys (t n for j k), with
# search as a mode of its own (like clipse; needs fzf 0.59+, from Nix on
# nhuto-Mint):
#   t n              down, up          g G         first, last entry
#   T N              half a page       Enter       copy it back, close
#   d, Shift+Delete  delete the entry  Esc q       close
#   /                search: type to filter, then Enter keeps the filter and
#                    goes back to the keys above, Esc clears it
# $mod+v again closes it too.
#
#   clipboard.sh             open the picker (or close it if it's open)
#   clipboard.sh --picker    the fzf part, inside the kitty window
#   clipboard.sh --preview   fzf's preview of one entry
#
# From a terminal:  cliphist list | fzf --with-nth=2.. | cliphist decode | wl-copy

self=$(readlink -f "$0")
class=clipboard-picker

case $1 in
--preview)
  line=$2
  id=${line%%$'\t'*}
  if [[ ${line#*$'\t'} == '[[ binary data '* ]]; then
    img=${XDG_RUNTIME_DIR:-/tmp}/clipboard-preview
    cliphist decode "$id" > "$img"
    # As in fzf's own fzf-preview.sh: a picture the size of the preview, sent
    # as Unicode placeholders that fzf can show. One line short when the
    # preview is as tall as the terminal, or the picture scrolls.
    cols=$FZF_PREVIEW_COLUMNS lines=$FZF_PREVIEW_LINES
    (( lines >= $(tput lines) )) && (( lines-- ))
    kitty icat --clear --transfer-mode=memory --unicode-placeholder --stdin=no \
      --place="${cols}x${lines}@0x0" "$img" | sed '$d' | sed $'$s/$/\e[m/'
  else
    cliphist decode "$id"
  fi
  exit ;;

--picker)
  # Colours from fuzzel.ini (the WM's: pink accents, deep pink selection)
  colors='bg:#222222,fg:#f7f6ec,hl:#d18ea6,bg+:#4e262f,fg+:#ffffff,hl+:#d18ea6'
  colors+=',gutter:#222222,border:#333333,separator:#333333,scrollbar:#333333'
  colors+=',prompt:#d18ea6,pointer:#d18ea6,info:#888888,query:#f7f6ec,footer:#888888'
  keys='t,n,T,N,g,G,d,q,/'
  delete="execute-silent(cliphist delete <<< {})+reload(cliphist list)"
  # Enter and Esc depend on the mode: while searching (input shown) they go
  # back to the keys, keeping or clearing the filter. Esc clears it outside
  # the transform, which drops query changes (and it's closing otherwise).
  back="hide-input+rebind($keys)"
  searching='[[ $FZF_INPUT_STATE == enabled ]]'
  on_enter="$searching && echo '$back' || echo accept"
  on_esc="$searching && echo '$back' || echo abort"
  # cliphist lists the newest first: keep that order among equal matches
  line=$(cliphist list | fzf --delimiter=$'\t' --with-nth=2.. --tiebreak=index \
    --no-input --layout=reverse --info=inline-right --prompt='/ ' --pointer='▌' \
    --color="$colors" \
    --footer='t n move · / search · enter copy · d delete · esc close' \
    --preview="$self --preview {}" --preview-window='right,55%,wrap,border-left' \
    --bind="t:down,n:up,T:half-page-down,N:half-page-up,g:first,G:last" \
    --bind="d:$delete,shift-delete:$delete,q:abort" \
    --bind="/:show-input+unbind($keys)" \
    --bind="enter:transform:$on_enter" --bind="esc:clear-query+transform:$on_esc")
  [[ -n $line ]] || exit 0
  # setsid: wl-copy stays behind to serve the clipboard, and would otherwise
  # go with the window (and not keep it open by holding on to its terminal)
  cliphist decode <<< "$line" | setsid -f wl-copy >/dev/null 2>&1
  exit ;;
esac

# Toggle: close the picker if it's open
if hyprctl -j clients | jq -e --arg c "$class" 'any(.[]; .class == $c)' >/dev/null; then
  hyprctl -q dispatch "hl.dsp.window.close({ window = 'class:^$class\$' })"
  exit 0
fi

exec kitty --class "$class" \
  -o background=#222222 -o foreground=#f7f6ec -o window_padding_width=10 \
  -o confirm_os_window_close=0 \
  "$self" --picker
