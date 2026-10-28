# pyright: strict
"""Keeps Discord's WebRTC logs of calls, to look into lag in a call later on:
Discord keeps them only for its last session or two, the next starts
overwrite them.

Run by a timer (home-manager/desktop/default.nix); copies the logs with a
call in them, compressed, to ~/.local/state/discord-call-logs, one file per
session and part (the one of a running session is replaced as it grows), and
removes the oldest beyond 100 MB. Read them with zstdcat or zstdgrep.
Built with writePython3Bin (pkgs/default.nix).
"""

import os
import re
from compression import zstd
from pathlib import Path

ARCHIVE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "discord-call-logs"
LOGS = [Path.home() / ".config/discord/logs", Path.home() / ".var/app/com.discordapp.Discord/config/discord/logs"]
MAX_BYTES = 100 * 1024 * 1024
LEVEL = 10
STARTED = re.compile(rb"^\[(\d{4}-\d{2}-\d{2}) (\d{2}):(\d{2}):(\d{2})", re.MULTILINE)


def archive_name(log: Path, content: bytes) -> str | None:
    """Named by the session's first line, so a log keeps its name when
    Discord renames it to discord-last-webrtc at its next start:
    discord-webrtc_0 → webrtc-2026-10-28_14-05-09-part0.log.zst"""
    started = STARTED.search(content)
    if not started:
        return None
    day, hour, minute, second = (g.decode() for g in started.groups())
    part = log.name.rsplit("_", 1)[-1]
    return f"webrtc-{day}_{hour}-{minute}-{second}-part{part}.log.zst"


def keep(log: Path) -> None:
    content = log.read_bytes()
    # Sessions without a call only log the audio devices
    if b"Transport stats" not in content:
        return
    name = archive_name(log, content)
    if not name:
        return
    target = ARCHIVE / name
    mtime = log.stat().st_mtime
    if target.exists() and target.stat().st_mtime >= mtime:
        return
    temp = target.with_name(target.name + ".tmp")
    temp.write_bytes(zstd.compress(content, level=LEVEL))
    os.utime(temp, (mtime, mtime))
    temp.replace(target)


def to_remove(sizes: dict[str, int], limit: int) -> list[str]:
    """Newest first (the names begin with the date), so the oldest go over
    the limit"""
    total = 0
    over: list[str] = []
    for name in sorted(sizes, reverse=True):
        total += sizes[name]
        if total > limit:
            over.append(name)
    return over


def main() -> None:
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    for logs in LOGS:
        for log in sorted(logs.glob("discord-*webrtc_*")):
            if log.is_file():
                keep(log)
    sizes = {f.name: f.stat().st_size for f in ARCHIVE.glob("webrtc-*.log.zst")}
    for name in to_remove(sizes, MAX_BYTES):
        (ARCHIVE / name).unlink(missing_ok=True)


if __name__ == "__main__":
    main()
