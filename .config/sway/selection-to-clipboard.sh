#!/bin/sh
# Copy highlighted text (the primary selection) to the clipboard, like
# `autocutsel -selection PRIMARY` did under Cinnamon. wl-paste runs the copy
# step each time the selection changes; skip empty selections so clearing a
# highlight doesn't wipe the clipboard.

if [ "$1" = --copy ]; then
  tmp=$(mktemp) || exit 1
  cat >"$tmp"
  [ -s "$tmp" ] && wl-copy <"$tmp"
  rm -f "$tmp"
  exit 0
fi

exec wl-paste --primary --type text --watch "$0" --copy
