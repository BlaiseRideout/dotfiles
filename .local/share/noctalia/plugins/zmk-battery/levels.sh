#!/bin/bash
# Prints one line per keyboard half: <device path> TAB <name> TAB <index> TAB <level>.
# Connected BlueZ devices with a keyboard icon, each Battery Level (0x2a19)
# characteristic in object order (ZMK's proxy: central half first). ZMK reports 0
# for a half it hasn't read yet or has lost contact with.

bluez() { busctl --system "$@" 2>/dev/null; }

objects=$(bluez tree org.bluez --list)

for dev in $(grep -E '^/org/bluez/hci[0-9]+/dev_[0-9A-F_]+$' <<<"$objects"); do
    [[ $(bluez get-property org.bluez "$dev" org.bluez.Device1 Connected) == "b true" ]] || continue
    [[ $(bluez get-property org.bluez "$dev" org.bluez.Device1 Icon) == *input-keyboard* ]] || continue
    name=$(bluez get-property org.bluez "$dev" org.bluez.Device1 Alias | sed -E 's/^s "(.*)"$/\1/')
    i=0
    for ch in $(grep -E "^$dev/service[0-9a-f]+/char[0-9a-f]+$" <<<"$objects" | sort); do
        [[ $(bluez get-property org.bluez "$ch" org.bluez.GattCharacteristic1 UUID) == *00002a19-* ]] || continue
        level=$(bluez call org.bluez "$ch" org.bluez.GattCharacteristic1 ReadValue 'a{sv}' 0 | awk '{print $3}')
        [[ $level =~ ^[0-9]+$ ]] || continue
        printf '%s\t%s\t%s\t%s\n' "$dev" "$name" "$i" "$level"
        i=$((i + 1))
    done
done
