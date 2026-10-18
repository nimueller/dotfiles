# shellcheck shell=bash
# Built with writeShellApplication (pkgs/default.nix), which adds the shebang
# Keeps Discord's WebRTC logs of calls, to look into lag in a call later on:
# Discord keeps them only for its last session or two, the next starts
# overwrite them. Run by a timer (home-manager/desktop/default.nix); copies
# the logs with a call in them, compressed, to
# ~/.local/state/discord-call-logs, one file per session and part (the one
# of a running session is replaced as it grows), and removes the oldest
# beyond 100 MB. Read them with zstdcat or zstdgrep.
archive=${XDG_STATE_HOME:-$HOME/.local/state}/discord-call-logs
max_bytes=$((100 * 1024 * 1024))

mkdir -p "$archive"

for log in "$HOME"/.config/discord/logs/discord-*webrtc_* \
    "$HOME"/.var/app/com.discordapp.Discord/config/discord/logs/discord-*webrtc_*; do
    [ -f "$log" ] || continue
    # Sessions without a call only log the audio devices
    grep -q 'Transport stats' "$log" || continue
    # Named by the session's first line, so a log keeps its name when Discord
    # renames it to discord-last-webrtc at its next start
    started=$(grep -m1 -oE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' "$log" | tr -d '[' | tr ' :' '_-')
    [ -n "$started" ] || continue
    target=$archive/webrtc-$started-part${log##*_}.log.zst
    [ "$log" -nt "$target" ] || continue
    zstd -q -10 -f "$log" -o "$target.tmp" && touch -r "$log" "$target.tmp" && mv "$target.tmp" "$target"
done

# Newest first (the names begin with the date), so the oldest go over the limit
total=0
mapfile -t files < <(find "$archive" -maxdepth 1 -name 'webrtc-*.log.zst' -printf '%f\n' | sort -r)
for name in "${files[@]}"; do
    total=$((total + $(stat -c %s "$archive/$name")))
    if [ "$total" -gt "$max_bytes" ]; then
        rm -f "$archive/$name"
    fi
done
