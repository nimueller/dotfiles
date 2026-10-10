#!/usr/bin/env bash
# Waybar notification center backed by dunst's history.
#   notifications.sh status     -> JSON for the waybar custom module
#   notifications.sh open <id>  -> focus the app that sent a history entry
# The notification center itself is config/quickshell/menus/notifications.qml.

ICON_BELL=$'\U000f009a'   # 󰂚
ICON_BADGE=$'\U000f116b'  # 󱅫
ICON_OFF=$'\U000f009b'    # 󰂛

status() {
    local count paused text class tooltip
    count=$(dunstctl count history 2>/dev/null || echo 0)
    paused=$(dunstctl is-paused 2>/dev/null || echo false)

    if [[ $paused == true ]]; then
        text=$ICON_OFF
        class=dnd
        tooltip="Do not disturb is on"
    elif ((count > 0)); then
        text="$ICON_BADGE $count"
        class=unread
        tooltip="$count missed notification(s)"
    else
        text=$ICON_BELL
        class=empty
        tooltip="No missed notifications"
    fi
    tooltip+="\nLeft: open · Right: do not disturb · Middle: clear"

    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$class"
}

# Show a copy of a history entry as a popup without taking it out of the
# history (history-pop would). The category makes dunst skip saving the copy,
# see the [center-preview] rule in config/dunst/dunstrc.
preview() {
    local app icon urgency summary body
    {
        IFS= read -r -d '' app
        IFS= read -r -d '' icon
        IFS= read -r -d '' urgency
        IFS= read -r -d '' summary
        IFS= read -r -d '' body
    } < <(dunstctl history | jq -j --argjson id "$1" '.data[0][] | select(.id.data == $id) |
        [.appname.data, .icon_path.data, (.urgency.data | ascii_downcase),
         .summary.data, .body.data][] + "\u0000"')
    notify-send -c center.preview -a "$app" -i "$icon" -u "$urgency" "$summary" "$body"
}

# Focus the most recently used window of the app that sent a history entry.
# App names and window classes are compared loosely, e.g. "Thunderbird"
# matches "org.mozilla.Thunderbird". Fails if no window matches.
focus_app() {
    local app addr
    app=$(dunstctl history | jq -r --argjson id "$1" \
        '.data[0][] | select(.id.data == $id) | .appname.data')
    addr=$(hyprctl clients -j | jq -r --arg app "$app" '
        def norm: ascii_downcase | gsub("[^a-z0-9]"; "");
        ($app | norm) as $a |
        [.[] | (.class | split(".") | last | norm) as $short |
            select($a != "" and (
                (.class | norm | contains($a)) or
                (.initialClass | norm | contains($a)) or
                ($short | length > 2 and ($a | contains($short)))))] |
        sort_by(.focusHistoryID) | .[0].address // empty')
    [[ -n $addr ]] || return 1
    hyprctl dispatch "hl.dsp.focus({ window = 'address:$addr' })" >/dev/null
}

# Clicking an entry in the notification center: dunst can't run actions of
# timed-out notifications, so focus the sending app instead, or show the
# entry again if no window matches. Exits 1 in the latter case.
open() {
    focus_app "$1" && return 0
    preview "$1"
    return 1
}

case $1 in
    status) status ;;
    open) open "$2" ;;
    *) echo "usage: $0 {status|open <id>}" >&2; exit 1 ;;
esac
