#!/usr/bin/env bash
# helpers: csp.sh launch | kill | wins | shot <file>
APP=com.usebottles.bottles
case "$1" in
  launch) flatpak kill $APP 2>/dev/null; sleep 3
          nohup ~/.local/bin/clip-studio-paint >/dev/null 2>&1 &
          for i in $(seq 1 40); do sleep 3
            n=$(hyprctl clients -j | python3 -I -c "
import json,sys
print(len([c for c in json.load(sys.stdin) if 'exe' in c['class'] and c['title']]))")
            [ "$n" != "0" ] && break; done; sleep 6; echo "launched after ~$((i*3+6))s";;
  kill) flatpak kill $APP 2>/dev/null; sleep 2;;
  wins) hyprctl clients -j | python3 -I -c "
import json,sys
for c in json.load(sys.stdin):
    if 'exe' in c['class'] and (c['size'][0]>1 or c['title']): print(repr(c['title']),'ws',c['workspace']['id'],'at',c['at'],'size',c['size'],'addr',c['address'],'focus',c['focusHistoryID'])";;
  shot) grim -o eDP-1 "$2";;
  cpu) pid=$(for p in $(pgrep -f "[C]LIPStudioPaint"); do tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -q "^WINEPREFIX=" && echo $p && break; done); [ -n "$pid" ] && top -b -n 2 -d 2 -p $pid | tail -1 | awk '{print $9}' || echo none;;
esac
