#!/bin/bash

offset_f="$(dirname $0)/month_offset"
# How many seconds before file is deemed "older"
COOLDOWN=60
# Get current and file times
CURTIME=$(date +%s)
FILETIME=$(stat $offset_f -c %Y)
TIMEDIFF=$(expr $CURTIME - $FILETIME)

# Check if file older
if [ $TIMEDIFF -gt $COOLDOWN ]; then
  echo "0" > $offset_f
fi

text="$(date +'%a, %b %d %R')"
offset="$(cat $offset_f)"

if [[ $offset -ge 0 ]]; then
  tooltip="$(ncal -b -A "$offset" -B "-$offset" | sed -e '/^\\s\*$/d;s/ \?$/\\\\n/g;s/ /\xC2\xA0/g;s/\x5f\x08\(.\)/<span color=\\"#2b303b\\" background=\\"#ffffff\\" weight=\\"bold\\">\1<\/span>/g')"
else
  abs_offset=${offset#-}
  tooltip="$(ncal -b -A "-$abs_offset" -B "$abs_offset" | sed -e '/^\\s\*$/d;s/ \?$/\\\\n/g;s/ /\xC2\xA0/g;s/\x5f\x08\(.\)/<span color=\\"#2b303b\\" background=\\"#ffffff\\" weight=\\"bold\\">\1<\/span>/g')"
fi

class="customclock"

cmd="$1"
case $cmd in
  "shift_up")
    echo "$(( $offset + 1))" > $offset_f
    ;;
  "shift_down")
    echo "$(( $offset - 1))" > $offset_f
    ;;
  *)
    echo -e '{"text":"'$text'","tooltip":"<tt>'$tooltip'</tt>"}'
    ;;
esac
