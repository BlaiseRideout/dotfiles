#!/bin/bash
# Waybar modules for an NVIDIA GPU, read from nvidia-smi.
#   gpu.sh usage   utilization, with VRAM, power and clocks in the tooltip
#   gpu.sh temp    temperature, "critical" at CRITICAL degrees or above
# Prints an empty, "hidden" module where there's no NVIDIA GPU (e.g. the laptop).

CRITICAL=${GPU_TEMP_CRITICAL:-80}

hidden() {
    echo '{"text": "", "class": "hidden"}'
    exit 0
}

# Pads $1 to $2 characters with figure spaces (as wide as a digit in Roboto), so the module
# keeps the same width as the number changes; bytes rather than \u so it doesn't depend on the locale
pad() { local s; printf -v s '%*s' "$2" "$1"; printf '%s' "${s// /$'\xe2\x80\x87'}"; }

command -v nvidia-smi >/dev/null || hidden
IFS=, read -r name util temp mem_used mem_total power clock < <(
    timeout 3 nvidia-smi --format=csv,noheader,nounits \
        --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,clocks.gr
) || hidden
[[ $util =~ ^\ *[0-9]+$ ]] || hidden

case $1 in
usage)
    tip="$name\\nVRAM: $((mem_used)) / $((mem_total)) MiB\\nPower: $((${power%.*})) W\\nClock: $((clock)) MHz"
    printf '{"text": "\uf26c  %s%%", "tooltip": "%s", "class": "ok"}\n' "$(pad "$((util))" 2)" "$tip"
    ;;
temp)
    if (( temp < 50 )); then icon=$'\uf76b'; elif (( temp < 70 )); then icon=$'\uf2c9'; else icon=$'\uf769'; fi
    class=ok; (( temp >= CRITICAL )) && class=critical
    value="$(pad "$((temp))" 2)\u00b0C"
    # Same red bold text as the temperature module's critical state
    [[ $class == critical ]] && value="<span color='#ce3e60'><b>$value</b></span>"
    printf '{"text": "%s  %s", "tooltip": "%s", "class": "%s"}\n' "$icon" "$value" "$name" "$class"
    ;;
*)
    echo "usage: $0 usage|temp" >&2
    exit 1
    ;;
esac
