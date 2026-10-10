# Usage: recorder [region|monitor]
# Running it again while a recording is active stops that recording.

OUTPUT_FILE="$HOME/Videos/$(date --iso-8601=seconds).mp4"
RUNNING_PID=$(pgrep -x wf-recorder)

if [ -n "$RUNNING_PID" ]; then
    kill $RUNNING_PID
    exit 0
fi

case "$1" in
    region)
        GEOMETRY=$(slurp -d) || exit 1
        ;;
    monitor)
        GEOMETRY=$(slurp -o) || exit 1
        ;;
    *)
        echo "Usage: recorder [region|monitor]" >&2
        exit 1
        ;;
esac

wf-recorder -g "$GEOMETRY" -f "$OUTPUT_FILE"

notify-send "Recording stopped" "The recording was saved to $OUTPUT_FILE" --expire-time=5000
