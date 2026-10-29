#!/usr/bin/env python3
# pyright: strict
"""Screenshots and screen recordings with an editor in Quickshell
(screenshot.qml).

screenshot.py [region|window|screen]
    Freeze every monitor (grim), then open the editor on top: pick a
    region or a window, adjust it, draw on it, choose the resolution, copy
    or save, or record it. `window` and `screen` start with the active
    window or the focused monitor already selected. While a recording
    runs, it stops the recording instead.
screenshot.py --export DIR SOURCE.png LAYER.png|- WxH+X+Y PERCENT copy|save|text
    Run by the editor as it closes (ShotScreen.qml): draws the layer over
    the screenshot, crops and scales it, copies it (and saves it), with a
    notification. `text` copies what's in it instead: the content of the
    QR codes or barcodes (zbar), else the text Tesseract reads.
screenshot.py --record DIR OUTPUT X,Y WxH PERCENT sound|mute
    Run by the editor as it closes: records the area (in the layout's
    logical coordinates) of the monitor OUTPUT with wf-recorder until
    `--stop`, scaled to PERCENT, with what the speakers play or without
    sound. The bar shows it from RECORDING (Recording.qml) and stops it
    on a click. The video goes to ~/Videos/Screencasts, its path to the
    clipboard.
screenshot.py --stop
    Stop the recording.
"""

import json
import os
import re
import shutil
import signal
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
# The running recording, {"pid", "file", "started"}: the bar watches it
RECORDING = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "qs-recording.json"
VIDEOS = Path.home() / "Videos/Screencasts"


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


def recorder_args(output: str, geometry: str, percent: str, sound: bool, file: Path) -> list[str]:
    """wf-recorder's arguments. x264 on the CPU: Nix's FFmpeg can't load the
    system's NVIDIA driver for NVENC. The scaling also rounds the size to
    even numbers, which x264's 4:2:0 needs."""
    scale = int(percent) / 100
    args = ["wf-recorder", "-y", "-o", output, "-g", geometry, "-c", "libx264"]
    args += ["-p", "preset=veryfast", "-p", "crf=23"]
    args += ["-F", f"scale=trunc(iw*{scale:g}/2)*2:trunc(ih*{scale:g}/2)*2"]
    if sound:
        args.append("--audio=@DEFAULT_MONITOR@")
    return args + ["-f", str(file)]


def running_recording() -> int | None:
    """The recorder's PID, if one runs; a leftover state file goes"""
    try:
        pid = int(json.loads(RECORDING.read_text())["pid"])
        os.kill(pid, 0)
        return pid
    except (OSError, ValueError, KeyError, TypeError):
        RECORDING.unlink(missing_ok=True)
        return None


def record(shot: Path, output: str, geometry: str, percent: str, sound: bool) -> None:
    shutil.rmtree(shot, ignore_errors=True)
    if running_recording():
        return
    VIDEOS.mkdir(parents=True, exist_ok=True)
    file = VIDEOS / f"Recording_{datetime.now():%Y-%m-%d_%H-%M-%S}.mp4"
    # The editor's frozen screen has to be gone first
    time.sleep(0.3)
    # --stop interrupts it, which an ignored SIGINT inherited from a
    # background shell would keep out
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    # Its progress goes to a file, not into memory for as long as it records
    log = RECORDING.with_suffix(".log")
    with log.open("w") as errors:
        try:
            recorder = subprocess.Popen(
                recorder_args(output, geometry, percent, sound, file), stdout=subprocess.DEVNULL, stderr=errors
            )
        except FileNotFoundError:
            notify("-u", "critical", "-i", "dialog-error", "Recording failed", "wf-recorder isn't installed")
            sys.exit(1)
        RECORDING.write_text(json.dumps({"pid": recorder.pid, "file": str(file), "started": time.time()}))
        try:
            recorder.wait()
        finally:
            RECORDING.unlink(missing_ok=True)

    if not file.exists() or file.stat().st_size == 0:
        last = log.read_text(errors="replace").strip().splitlines()[-1:] or ["no video was written"]
        notify("-u", "critical", "-i", "dialog-error", "Recording failed", markup(last[0]))
        sys.exit(1)
    # As a file to paste into chats and file managers
    subprocess.run(["wl-copy", "--type", "text/uri-list"], input=file.as_uri().encode(), check=False)
    actions = ["-A", "open=Open", "-A", "folder=Show in folder"]
    clicked = notify("-i", "video-x-generic", *actions, "Recording saved", f"{file.name}, also copied", transient=True)
    if clicked == "open":
        open_path(file)
    elif clicked == "folder":
        open_path(VIDEOS)


def stop() -> bool:
    """Stops the recording; False if there was none. wf-recorder finishes
    the file on SIGINT."""
    pid = running_recording()
    if pid:
        os.kill(pid, signal.SIGINT)
    return pid is not None


def capture(mode: str) -> None:
    if stop():
        return
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
        case ["--record", shot, output, position, size, percent, ("sound" | "mute") as sound]:
            record(Path(shot), output, f"{position} {size}", percent, sound == "sound")
        case ["--stop"]:
            stop()
        case [] | [("region" | "window" | "screen")]:
            capture(args[0] if args else "region")
        case _:
            print(__doc__, file=sys.stderr)
            sys.exit(2)


if __name__ == "__main__":
    main(sys.argv[1:])
