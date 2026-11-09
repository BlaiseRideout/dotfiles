#!/bin/bash
# x-all-transparent.sh CLASS: succeeds when at least one X11 window has this
# class and every one of them asks to be fully transparent
# (_NET_WM_WINDOW_OPACITY = 0), a hint Hyprland ignores. Used by hyprland.lua
# to hide the windows WebView2 keeps off screen under Wine (Clip Studio Paint's
# sign-up and welcome pages), which would otherwise sit over the page as black
# boxes. Fails without xprop, so nothing is hidden.
class=$1
found=
for id in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | sed 's/.*# //; s/,//g'); do
    props=$(xprop -id "$id" WM_CLASS _NET_WM_WINDOW_OPACITY 2>/dev/null) || continue
    case $props in *"\"$class\""*) ;; *) continue ;; esac
    case $props in *"_NET_WM_WINDOW_OPACITY(CARDINAL) = 0"*) found=1 ;; *) exit 1 ;; esac
done
[ -n "$found" ]
