#!/bin/bash
# Keep an app running and show or hide it from the Sway scratchpad, like Everything on
# Windows: a key binding or a Waybar button brings it up, and the same again hides it.
#
#   scratchpad-app.sh APP start    start it hidden, unless it's running (Sway config, at login)
#   scratchpad-app.sh APP toggle   show it on the current workspace, or hide it if it's focused
#   scratchpad-app.sh APP label    print the Waybar button text; nothing if APP isn't installed,
#                                  which hides the button
#
# APP is one of the profiles below. Does nothing where the app isn't installed.

app=$1 action=$2

case $app in
    fsearch)
        APP_ID=io.github.cboxdoerfer.FSearch
        TITLE='^FSearch'   # the main window; its dialogs share the app_id
        LAUNCH="flatpak run $APP_ID"
        FLOAT=1            # shown floating and centered
        LABEL=$''    # magnifying glass
        installed() { flatpak info "$APP_ID" >/dev/null 2>&1; }
        ;;
    t3code)
        APP_ID=com.t3tools.T3Code
        TITLE=''
        LAUNCH=~/.local/bin/t3code
        FLOAT=0            # shown tiled, like a normal window
        LABEL=T3
        installed() { [[ -x $LAUNCH ]]; }
        ;;
    *)
        echo "usage: $0 fsearch|t3code start|toggle|label" >&2
        exit 2
        ;;
esac

installed || exit 0

if [[ $action == label ]]; then
    echo "$LABEL"
    exit 0
fi

# Under Hyprland the config does the work (scratch_toggle in hypr/hyprland.lua) and starts
# FSearch itself
if [[ -n $HYPRLAND_INSTANCE_SIGNATURE ]]; then
    [[ $action == toggle ]] && hyprctl -q eval "scratch_toggle('$app')"
    exit 0
fi

# The window as "id focused workspace" (the workspace is __i3_scratch while it's hidden)
window() {
    swaymsg -t get_tree | jq -r --arg app "$APP_ID" --arg title "$TITLE" '
        first(.. | objects | select(.type? == "workspace") | .name as $ws
              | .. | objects
              | select(.app_id? == $app and ((.name // "") | test($title)))
              | "\(.id) \(.focused) \($ws)")'
}

# Start the app and wait up to 15 s for its window
launch() {
    swaymsg -q exec "$LAUNCH"
    for _ in $(seq 60); do
        read -r id focused ws <<< "$(window)"
        [[ -n $id ]] && return 0
        sleep 0.25
    done
    return 1
}

hide() {
    swaymsg -q "[con_id=$id] move scratchpad"
}

show() {
    if (( FLOAT )); then
        # Sized to fit the focused output (the G95C is 5120 wide, the AOC 1080)
        read -r w h <<< "$(swaymsg -t get_outputs | jq -r '
            first(.[] | select(.focused)) | .rect
            | "\([1600, .width * 0.9 | floor] | min) \([1000, .height * 0.8 | floor] | min)"')"
        swaymsg -q "[con_id=$id] scratchpad show, resize set $w $h, move position center, focus"
    else
        swaymsg -q "[con_id=$id] scratchpad show, floating disable, focus"
    fi
}

read -r id focused ws <<< "$(window)"

case $action in
    start)
        [[ -n $id ]] && exit 0
        launch && hide
        ;;
    toggle)
        if [[ -z $id ]]; then
            # A floating app is moved through the scratchpad so it gets its size and place
            if (( FLOAT )); then launch && hide && show; else launch; fi
        elif [[ $ws == __i3_scratch ]]; then
            show
        elif [[ $focused == true ]]; then
            hide
        elif (( FLOAT )); then
            # Open on another workspace: pull it over rather than switching there
            hide && show
        else
            swaymsg -q "[con_id=$id] focus"
        fi
        ;;
    *)
        echo "usage: $0 fsearch|t3code start|toggle|label" >&2
        exit 2
        ;;
esac
