#!/bin/sh
# Do-not-disturb for mako, shown in waybar's custom/makomode module.
#   dndctl.sh          print the status icon for waybar
#   dndctl.sh toggle   turn do-not-disturb on or off
#   dndctl.sh on|off   set it explicitly
# The [mode=dnd] section in ~/.config/mako/config hides notifications while the
# mode is set; they're still kept in the history (makoctl history/restore).

WAYBAR_SIGNAL=8

is_dnd() {
  makoctl mode 2>/dev/null | grep -qx dnd
}

refresh_waybar() {
  pkill -RTMIN+"$WAYBAR_SIGNAL" -x waybar 2>/dev/null
}

case "$1" in
  toggle)
    if is_dnd; then makoctl mode -r dnd >/dev/null; else makoctl mode -a dnd >/dev/null; fi
    refresh_waybar
    ;;
  on)
    makoctl mode -a dnd >/dev/null
    refresh_waybar
    ;;
  off)
    makoctl mode -r dnd >/dev/null
    refresh_waybar
    ;;
  "")
    # Print nothing if mako isn't running so the module hides
    makoctl mode >/dev/null 2>&1 || exit 0
    # Font Awesome bell-slash (U+F1F6) while on, bell (U+F0F3) while off
    if is_dnd; then printf '\357\207\266\n'; else printf '\357\203\263\n'; fi
    ;;
  *)
    echo "usage: $0 [toggle|on|off]" >&2
    exit 1
    ;;
esac
