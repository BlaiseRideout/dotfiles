#!/bin/bash
# Waybar module: battery of a ZMK split keyboard over Bluetooth, read from BlueZ's GATT
# Battery Level (0x2a19) characteristics. With ZMK's CENTRAL_BATTERY_LEVEL_PROXY the
# central half exposes one per half, in order (central first). Sends a notification when
# a half drops to LOW% or below, again at CRITICAL%, and re-arms once it recovers.

LOW=${ZMK_BATTERY_LOW:-20}
CRITICAL=${ZMK_BATTERY_CRITICAL:-10}
LABELS=(L R)
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/zmk-battery"
mkdir -p "$STATE_DIR"

# Pads $1 to $2 characters with figure spaces (as wide as a digit in Roboto), so the module
# keeps the same width as the number changes; bytes rather than \u so it doesn't depend on the locale
pad() { local s; printf -v s '%*s' "$2" "$1"; printf '%s' "${s// /$'\xe2\x80\x87'}"; }

bluez() { busctl --system "$@" 2>/dev/null; }

objects=$(bluez tree org.bluez --list)
parts=()
tooltip=()
worst=100
found=0

for dev in $(grep -E '^/org/bluez/hci[0-9]+/dev_[0-9A-F_]+$' <<<"$objects"); do
    [[ $(bluez get-property org.bluez "$dev" org.bluez.Device1 Connected) == "b true" ]] || continue
    [[ $(bluez get-property org.bluez "$dev" org.bluez.Device1 Icon) == *input-keyboard* ]] || continue
    name=$(bluez get-property org.bluez "$dev" org.bluez.Device1 Alias | sed -E 's/^s "(.*)"$/\1/')
    i=0
    for ch in $(grep -E "^$dev/service[0-9a-f]+/char[0-9a-f]+$" <<<"$objects" | sort); do
        [[ $(bluez get-property org.bluez "$ch" org.bluez.GattCharacteristic1 UUID) == *00002a19-* ]] || continue
        level=$(bluez call org.bluez "$ch" org.bluez.GattCharacteristic1 ReadValue 'a{sv}' 0 | awk '{print $3}')
        [[ $level =~ ^[0-9]+$ ]] || continue
        label=${LABELS[$i]:-$((i + 1))}
        i=$((i + 1))
        # ZMK's proxy reports 0 for a half it hasn't read yet or has lost contact with.
        if (( level == 0 )); then
            parts+=("--")
            tooltip+=("$name ($label): unknown")
            found=1
            continue
        fi
        parts+=("$(pad "$level" 2)%")
        tooltip+=("$name ($label): $level%")
        found=1
        (( level < worst )) && worst=$level

        # Notify once per threshold crossing; the marker is cleared when the level recovers.
        marker="$STATE_DIR/${dev##*/}-$label"
        prev=$(cat "$marker" 2>/dev/null || echo ok)
        if (( level <= CRITICAL )); then state=critical
        elif (( level <= LOW )); then state=low
        elif (( level > LOW + 5 )); then state=ok
        else state=$prev; fi
        if [[ $state != "$prev" && $state != ok && ! ( $prev == critical && $state == low ) ]]; then
            urgency=normal; [[ $state == critical ]] && urgency=critical
            notify-send -u "$urgency" -a "ZMK battery" -i input-keyboard \
                "$name $label battery ${state/critical/very low}" "Battery at $level%. Charge the keyboard soon."
        fi
        echo "$state" >"$marker"
    done
done

if (( ! found )); then
    echo '{"text": "", "class": "disconnected"}'
    exit 0
fi

class=ok
(( worst <= LOW )) && class=low
(( worst <= CRITICAL )) && class=critical
values="${parts[*]}"
# Same red bold text as the temperature module's critical state
[[ $class != ok ]] && values="<span color='#ce3e60'><b>$values</b></span>"
text="  $values"
tip=$(printf '%s\\n' "${tooltip[@]}")
printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$text" "${tip%\\n}" "$class"
