#!/usr/bin/env bash
# Open the sound popup, or close it if it's already open.
qs -c audio kill >/dev/null 2>&1 && exit 0

# Clicking the bar icon while the popup is open closes it through the focus
# grab first, so don't reopen if it closed a moment ago.
stamp=$XDG_RUNTIME_DIR/qs-audio-closed
if [[ -e $stamp ]] && (($(date +%s%3N) - $(stat -c %.3Y "$stamp" | tr -d .) < 500)); then
    exit 0
fi

exec qs -c audio -n -d >/dev/null 2>&1
