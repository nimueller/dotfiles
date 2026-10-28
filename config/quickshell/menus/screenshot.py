#!/usr/bin/env python3
# pyright: strict
"""Screenshots with an editor in Quickshell (screenshot.qml).

screenshot.py [region|window|screen]
    Freeze every monitor (grim), then open the editor on top: pick a
    region or a window, adjust it, draw on it, choose the resolution, copy
    or save. `window` and `screen` start with the active window or the
    focused monitor already selected.
screenshot.py --export DIR SOURCE.png LAYER.png|- WxH+X+Y PERCENT copy|save|text
    Run by the editor as it closes (ShotScreen.qml): draws the layer over
    the screenshot, crops and scales it, copies it (and saves it), with a
    notification. `text` copies what's in it instead: the content of the
    QR codes or barcodes (zbar), else the text Tesseract reads.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "qs-screenshot"
SAVED = Path.home() / "Pictures/Screenshots"
PREVIEW = 300  # characters of copied text in the notification
STALE = 10 * 60  # seconds after which a shot's directory is a leftover


def notify(*args: str, transient: bool = False) -> str:
    """notify-send; returns the action clicked. It waits for a click for a
    while, not forever. Success only pops up: transient, so it stays out of
    the notification center."""
    command = ["notify-send", "-a", "Screenshot", *(["-e"] if transient else []), *args]
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=300, check=False).stdout.strip()
    except subprocess.TimeoutExpired:
        return ""


def markup(text: str) -> str:
    """Escapes text for a notification body, which takes markup"""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def preview(text: str) -> str:
    return text[:PREVIEW] + "…" if len(text) > PREVIEW else text


def is_url(text: str) -> bool:
    return re.fullmatch(r"https?://\S+", text) is not None


def open_path(target: str | Path) -> None:
    subprocess.run(["xdg-open", str(target)], check=False)


def read_text(image: Path) -> None:
    zbar = subprocess.run(["zbarimg", "--raw", "-q", str(image)], capture_output=True, text=True, check=False)
    if zbar.returncode == 0:
        what, text = "QR code", zbar.stdout.rstrip("\n")
    else:
        # Twice the size: Tesseract misses small letters at 1x
        gray = subprocess.run(
            ["magick", str(image), "-colorspace", "Gray", "-resize", "200%", "png:-"], capture_output=True, check=False
        ).stdout
        ocr = subprocess.run(
            ["tesseract", "-", "-", "-l", "deu+eng", "-c", "page_separator="],
            input=gray,
            capture_output=True,
            check=False,
        )
        what, text = "Text", ocr.stdout.decode(errors="replace").rstrip("\n")
    if not text.strip():
        notify("-i", "dialog-information", "No text found", "Neither a QR code nor text in the selection")
        sys.exit(1)
    subprocess.run(["wl-copy", "--type", "text/plain"], input=text.encode(), check=False)

    body = markup(preview(text))
    if is_url(text):
        if notify("-i", "edit-paste", "-A", "open=Open", f"{what} copied", body, transient=True) == "open":
            open_path(text)
    else:
        notify("-i", "edit-paste", f"{what} copied", body, transient=True)


def save_copy(image: Path) -> Path:
    SAVED.mkdir(parents=True, exist_ok=True)
    file = SAVED / f"Screenshot_{datetime.now():%Y-%m-%d_%H-%M-%S}.png"
    shutil.copyfile(image, file)
    return file


def magick_args(source: str, layer: str, geometry: str, percent: str, action: str) -> list[str]:
    args = [source]
    if layer != "-":
        args += [layer, "-composite"]
    args += ["-crop", geometry, "+repage"]
    # The text is read at full size
    if percent != "100" and action != "text":
        args += ["-resize", f"{percent}%"]
    return args


def export(shot: Path, source: str, layer: str, geometry: str, percent: str, action: str) -> None:
    out = RUNTIME / "last.png"
    written = subprocess.run(["magick", *magick_args(source, layer, geometry, percent, action), str(out)], check=False)
    shutil.rmtree(shot, ignore_errors=True)
    if written.returncode != 0:
        notify("-u", "critical", "-i", "dialog-error", "Screenshot failed", "ImageMagick couldn't write the image")
        sys.exit(1)
    if action == "text":
        read_text(out)
        return
    with out.open("rb") as image:
        subprocess.run(["wl-copy", "--type", "image/png"], stdin=image, check=False)

    size = subprocess.run(
        ["magick", "identify", "-format", "%w × %h", str(out)], capture_output=True, text=True, check=False
    ).stdout
    if action == "save":
        file = save_copy(out)
        actions = ["-A", "open=Open", "-A", "folder=Show in folder"]
        clicked = notify(
            "-i", str(file), *actions, "Screenshot saved", f"{file.name} · {size}, also copied", transient=True
        )
        if clicked == "open":
            open_path(file)
        elif clicked == "folder":
            open_path(SAVED)
    elif notify("-i", str(out), "-A", "save=Save", "Screenshot copied", size, transient=True) == "save":
        file = save_copy(out)
        notify("-i", str(file), "Screenshot saved", file.name, transient=True)


def capture(mode: str) -> None:
    entry = HERE / "screenshot.qml"
    running = subprocess.run(["qs", "list", "-p", str(entry)], capture_output=True, text=True, check=False)
    if "Process ID:" in running.stdout:
        return

    # Leftovers of cancelled or crashed editors
    RUNTIME.mkdir(parents=True, exist_ok=True)
    for old in RUNTIME.iterdir():
        if old.is_dir() and time.time() - old.stat().st_mtime > STALE:
            shutil.rmtree(old, ignore_errors=True)

    shot = RUNTIME / str(time.time_ns())
    shot.mkdir()
    monitors = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, check=True).stdout
    # Uncompressed PNGs: ~70 ms for 4K instead of ~270 ms; the export compresses
    grims = [
        subprocess.Popen(["grim", "-l", "0", "-o", m["name"], str(shot / f"{m['name']}.png")])
        for m in json.loads(monitors)
    ]
    (shot / "monitors.json").write_text(monitors)
    clients = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, check=False).stdout
    (shot / "clients.json").write_text(clients)
    for grim in grims:
        grim.wait()

    env = {**os.environ, "QS_SCREENSHOT_DIR": str(shot), "QS_SCREENSHOT_MODE": mode}
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 1)
    os.dup2(devnull, 2)
    os.execvpe("qs", ["qs", "-p", str(entry), "-n", "-d"], env)


def main(args: list[str]) -> None:
    match args:
        case ["--export", shot, source, layer, geometry, percent, ("copy" | "save" | "text") as action]:
            export(Path(shot), source, layer, geometry, percent, action)
        case [] | [("region" | "window" | "screen")]:
            capture(args[0] if args else "region")
        case _:
            print(__doc__, file=sys.stderr)
            sys.exit(2)


if __name__ == "__main__":
    main(sys.argv[1:])
