# pyright: strict
"""The media player on the lock screen (config/hypr/hyprlock.conf): hyprlock
asks for each part again and again, and the buttons control the same player.

lock-media title|artist     the track's title or artist, as Pango markup
lock-media position         "1:23  ━━━━━━━━━━━━━━━━━━  4:04", the part played
                            in lavender; "● Live  1:03:29" for live streams
lock-media cover            the path of the cover as a file hyprlock can
                            read (BLANK, a transparent one, without a track)
lock-media blank            writes BLANK's PNG to stdout (for the package)
lock-media button previous|toggle|next
                            the button's glyph (play or pause for toggle)
lock-media previous|toggle|next
                            the button's click

The player: the one playing, else a paused one with a track. playerctld
only mirrors the others, and browsers keep a player without a track around.
Everything prints nothing (and the buttons do nothing) without a player.
Built with writePython3Bin (pkgs/default.nix), so the file has no shebang.
"""

import hashlib
import html
import os
import shutil
import struct
import subprocess
import sys
import urllib.parse
import urllib.request
import zlib
from dataclasses import dataclass
from pathlib import Path

CACHE = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "lock-media"
# Installed by home-manager/desktop from `lock-media blank`: hyprlock's image
# needs a file that exists from the start (an empty or missing path stalls
# every label's update)
BLANK = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "lock-media/blank.png"
# playerInstance: "chromium.instance1162", for -p; playerName would match every instance
FIELDS = ["playerInstance", "status", "xesam:title", "xesam:artist", "mpris:artUrl", "position", "mpris:length"]
BAR = 18  # cells of the position bar
DONE, LEFT = "#b7bdf8", "#494d64"  # Catppuccin Macchiato lavender, surface1
LIVE_COLOR = "#ed8796"  # red
# Browsers send the largest int64 in µs as a live stream's length, about
# 292,000 years; no recording comes near 1e9 s (31 years)
LIVE = 1e9
GLYPHS = {"previous": "󰒮", "next": "󰒭", "play": "󰐊", "pause": "󰏤"}  # 󰒮 󰒭 󰐊 󰏤


@dataclass
class Player:
    name: str
    status: str  # Playing, Paused, Stopped
    title: str
    artist: str
    art: str
    position: float  # s
    length: float  # s, 0 if unknown


def parse(output: str) -> list[Player]:
    """`playerctl -a metadata --format` with FIELDS separated by tabs, one
    player per line"""
    players: list[Player] = []
    for line in output.splitlines():
        parts = line.split("\t")
        if len(parts) != len(FIELDS):
            continue
        name, status, title, artist, art, position, length = parts
        players.append(Player(name, status, title, artist, art, int(position or 0) / 1e6, int(length or 0) / 1e6))
    return players


def choose(players: list[Player]) -> Player | None:
    shown = [p for p in players if p.name != "playerctld" and p.title]
    return next((p for p in shown if p.status == "Playing"), None) or next(
        (p for p in shown if p.status == "Paused"), None
    )


def current() -> Player | None:
    form = "\t".join(f"{{{{{field}}}}}" for field in FIELDS)
    out = subprocess.run(
        ["playerctl", "-a", "metadata", "--format", form], capture_output=True, text=True, check=False
    ).stdout
    return choose(parse(out))


def time(seconds: float) -> str:
    """1:23, 1:02:45"""
    s = max(0, int(seconds))
    h, m = s // 3600, s // 60 % 60
    return f"{h}:{m:02}:{s % 60:02}" if h else f"{m}:{s % 60:02}"


def position(player: Player) -> str:
    if player.length >= LIVE:
        played = f"  {time(player.position)}" if player.position > 0 else ""
        return f'<span foreground="{LIVE_COLOR}">●  Live</span>{played}'
    if player.length <= 0:
        return ""
    done = round(min(1, player.position / player.length) * BAR)
    bar = f'<span foreground="{DONE}">{"━" * done}</span><span foreground="{LEFT}">{"━" * (BAR - done)}</span>'
    return f"{time(player.position)}  {bar}  {time(player.length)}"


def image_type(data: bytes) -> str | None:
    """The extension hyprlock goes by; Chromium's covers have none"""
    if data.startswith(b"\x89PNG"):
        return "png"
    if data.startswith(b"\xff\xd8"):
        return "jpg"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return None


def blank_png() -> bytes:
    """A transparent 1×1 PNG"""

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
    return png + chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00\x00")) + chunk(b"IEND", b"")


def cover(player: Player | None) -> Path:
    """The cover copied (file://) or downloaded (http) once into CACHE,
    named by the URL, so a new track is a new path for hyprlock"""
    if not player or not player.art:
        return BLANK
    key = hashlib.sha1(player.art.encode()).hexdigest()[:16]
    for known in CACHE.glob(f"cover-{key}.*"):
        return known
    url = urllib.parse.urlparse(player.art)
    try:
        if url.scheme == "file":
            data = Path(urllib.parse.unquote(url.path)).read_bytes()
        elif url.scheme in ("http", "https"):
            with urllib.request.urlopen(player.art, timeout=3) as response:
                data: bytes = response.read()
        else:
            return BLANK
    except OSError:
        return BLANK
    kind = image_type(data)
    if not kind:
        return BLANK
    # Only the latest cover stays
    shutil.rmtree(CACHE, ignore_errors=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / f"cover-{key}.{kind}"
    path.write_bytes(data)
    return path


def button(player: Player, which: str) -> str:
    if which == "toggle":
        return GLYPHS["pause" if player.status == "Playing" else "play"]
    return GLYPHS[which]


def main(args: list[str]) -> None:
    actions = {"previous": "previous", "toggle": "play-pause", "next": "next"}
    match args:
        case ["title" | "artist" | "position" as part]:
            player = current()
            if player:
                text = position(player) if part == "position" else getattr(player, part)
                print(text if part == "position" else html.escape(text, quote=False))
        case ["cover"]:
            print(cover(current()))
        case ["blank"]:
            sys.stdout.buffer.write(blank_png())
        case ["button", ("previous" | "toggle" | "next") as which]:
            player = current()
            if player:
                print(button(player, which))
        case [("previous" | "toggle" | "next") as which]:
            player = current()
            if player:
                subprocess.run(["playerctl", "-p", player.name, actions[which]], check=False)
        case _:
            print(__doc__, file=sys.stderr)
            sys.exit(2)


if __name__ == "__main__":
    main(sys.argv[1:])
