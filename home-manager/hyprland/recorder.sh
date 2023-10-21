#!/usr/bin/env nix-shell
#!nix-shell -i bash -p wf-recorder slurp

function start_region() {
    wf-recorder -g "$(slurp -d)" -f $OUTPUT_FILE
}

function start_monitor() {
    wf-recorder -g "$(slurp -o)" -f $OUTPUT_FILE
}

function end() {
    pgrep -l wf-recorder | awk '{print $1}'
}

OUTPUT_FILE="$HOME/Videos/$(date --iso-8601=seconds).mp4"
RUNNING_PID=$(pgrep wf-recorder)

if [ -z $RUNNING_PID ]; then 
    case "$1" in
        window)
            ;;
        region)
            start_region
            ;;
        monitor)
            start_monitor
            ;;
    esac

    notify-send "Recording stopped" "The recording was saved to $OUTPUT_FILE" --action="Click here to open" --wait --expire-time=5000
else
    kill $RUNNING_PID
fi

