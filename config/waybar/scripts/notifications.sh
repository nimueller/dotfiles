#!/usr/bin/env bash
# Waybar notification center backed by dunst's history.
#   notifications.sh status   -> JSON for the waybar custom module
#   notifications.sh center   -> rofi list of missed notifications

ICON_BELL=$'\U000f009a'   # 󰂚
ICON_BADGE=$'\U000f116b'  # 󱅫
ICON_OFF=$'\U000f009b'    # 󰂛
ICONS=$HOME/.config/rofi/icons

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

# Rofi rows for the dunst history, newest first. Each row is a two-line pango
# card ("summary  app · age" / body) with the app icon, separated by '|'.
history_rows() {
    dunstctl history | jq -j --argjson now "$1" --arg fallback "$ICONS/notification.svg" '
        def clean: gsub("<[^>]*>"; "") | gsub("\\|"; "¦") | gsub("\\s+"; " ");
        def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
        def age: (($now - .) / 1000000 | floor) as $s |
            if $s < 60 then "just now"
            elif $s < 3600 then "\($s / 60 | floor)m ago"
            elif $s < 86400 then "\($s / 3600 | floor)h ago"
            else "\($s / 86400 | floor)d ago" end;
        .data[0][] |
        (.body.data | clean | .[0:140] | esc) as $body |
        "<b>\(.summary.data | clean | esc)</b>  " +
        "<span size=\"small\" foreground=\"#6e738d\">\(.appname.data | clean | esc) · \(.timestamp.data | age)</span>" +
        (if $body != "" then "\n<span size=\"small\">\($body)</span>" else "" end) +
        "\u0000icon\u001f" +
        (if .icon_path.data != "" then .icon_path.data else $fallback end) +
        "|"'
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

center() {
    local row=0 now_us paused count offset sel rc idx urgent mesg
    local -a ids flags

    while true; do
        now_us=$(awk '{printf "%d", $1 * 1000000}' /proc/uptime)
        paused=$(dunstctl is-paused)
        mapfile -t ids < <(dunstctl history | jq -r '.data[0][].id.data')
        count=${#ids[@]}

        # Action rows first: do not disturb, then "clear all" if there is history
        offset=$((count > 0 ? 2 : 1))
        urgent=$(dunstctl history | jq -r --argjson o "$offset" \
            '[.data[0] | to_entries[] | select(.value.urgency.data == "CRITICAL") | .key + $o] | join(",")')

        # Highlight the DND row while it is on, critical notifications in red
        flags=()
        [[ $paused == true ]] && flags+=(-a 0)
        [[ -n $urgent ]] && flags+=(-u "$urgent")

        if ((count > 0)); then
            mesg="⏎ open  ·  Del remove  ·  Alt+C clear  ·  Alt+D silence"
        else
            mesg="No notifications"
        fi

        sel=$(
            {
                if [[ $paused == true ]]; then
                    printf '%s\0icon\x1f%s|' \
                        "<b>Do not disturb is on</b>"$'\n'"<span size=\"small\">Notifications are held back · select to turn off</span>" \
                        "$ICONS/dnd-on.svg"
                else
                    printf '%s\0icon\x1f%s|' \
                        "<b>Do not disturb</b>"$'\n'"<span size=\"small\" foreground=\"#6e738d\">Off · select to silence notifications</span>" \
                        "$ICONS/dnd-off.svg"
                fi
                ((count > 0)) && printf '%s\0icon\x1f%s|' \
                    "<b>Clear all</b>"$'\n'"<span size=\"small\" foreground=\"#6e738d\">Remove $count notification(s) from history</span>" \
                    "$ICONS/clear-all.svg"
                history_rows "$now_us"
            } | rofi -dmenu -i -no-custom -markup-rows -sep '|' -eh 2 -format i \
                -theme notifications \
                -theme-str "listview { lines: $(( offset + count < 6 ? offset + count : 6 )); }" \
                -p "$ICON_BELL Notifications" -mesg "$mesg" \
                -selected-row "$row" \
                "${flags[@]}" \
                -kb-remove-char-forward "Control+d" \
                -kb-custom-1 "Delete" -kb-custom-2 "Alt+c" -kb-custom-3 "Alt+d"
        )
        rc=$?
        [[ -z $sel ]] && sel=0
        row=$sel
        idx=$((sel - offset))

        case $rc in
            0)  # Enter / click
                if ((sel == 0)); then
                    dunstctl set-paused toggle
                elif ((count > 0 && sel == 1)); then
                    dunstctl history-clear; row=0
                else
                    # dunst can't run actions of timed-out notifications, so
                    # focus the sending app instead and keep the entry
                    focus_app "${ids[idx]}" && break
                    preview "${ids[idx]}"
                fi ;;
            10) ((idx >= 0)) && dunstctl history-rm "${ids[idx]}"
                ((row >= offset + count - 1 && row > 0)) && row=$((row - 1)) ;;
            11) dunstctl history-clear; row=0 ;;
            12) dunstctl set-paused toggle ;;
            *)  break ;;
        esac
        pkill -RTMIN+8 waybar
    done
    pkill -RTMIN+8 waybar
}

case $1 in
    status) status ;;
    center) center ;;
    *) echo "usage: $0 {status|center}" >&2; exit 1 ;;
esac
