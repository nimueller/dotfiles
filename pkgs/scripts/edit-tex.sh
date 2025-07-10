#!/bin/sh

texfiles=$(find . -maxdepth 1 -type f -name "*.tex")
count=$(echo "$texfiles" | wc -l)

if [ "$count" -eq 0 ]; then
    echo "❌ No .tex file found"
    exit 1
elif [ "$count" -eq 1 ]; then
    texfile="$texfiles"
else
    texfile=$(echo "$texfiles" | fzf --prompt="Choose a .tex file ")
    [ -z "$texfile" ] && echo "❌ No choice made" && exit 1
fi

latexmk -pvc -pdf -silent "$texfile" >/dev/null 2>&1 &
pid=$!

nvim "$texfile"

kill "$pid" 2>/dev/null && echo "🛑 latexmk PID $pid killed"

