#!/usr/bin/env python3
# pyright: strict
"""Reboot or shut down from the power menu (power.qml): close the apps and
Hyprland with hyprshutdown first, which shows the apps that hold it up,
then run the command.

  shutdown.py LABEL COMMAND

hyprshutdown ends every program of the session at once, the shell, the
wallpaper and the idle lock too, and has no way to leave some running. On
Cancel, start them again (autostart.lua: daemons).
"""

import json
import os
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

# Seconds the apps get to close before they are killed (hyprshutdown itself
# only waits, or kills on its Force quit button)
TIMEOUT = 30
# Still held up after that (an app that can't be killed): run the command anyway
GRACE = 5
# Only there once hyprshutdown has closed everything
CLOSED = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "hyprshutdown-closed"


def hyprctl_json(*args: str) -> list[dict[str, object]]:
    result = subprocess.run(["hyprctl", *args, "-j"], capture_output=True, text=True, check=False)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return []


def holding_up(hyprshutdown: int) -> set[int]:
    """What hyprshutdown waits for: the windows and Hyprland's own children
    but Xwayland (and this script and hyprshutdown)"""
    pids = {int(str(c["pid"])) for c in hyprctl_json("clients")}
    instance = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    for i in hyprctl_json("instances"):
        if i.get("instance") == instance:
            children = subprocess.run(
                ["pgrep", "-P", str(i["pid"])], capture_output=True, text=True, check=False
            ).stdout.split()
            pids |= {int(pid) for pid in children}
    pids -= {os.getpid(), hyprshutdown}
    return {pid for pid in pids if pid > 0 and comm(pid) not in ("Xwayland", None)}


def comm(pid: int) -> str | None:
    try:
        return Path(f"/proc/{pid}/comm").read_text().strip()
    except OSError:
        return None


def force_quit(hyprshutdown: subprocess.Popen[bytes], command: str) -> None:
    """Kills what holds hyprshutdown up once the time is over; with none left
    it exits Hyprland and runs the command. Ends with hyprshutdown, so Cancel
    stops it too."""
    try:
        hyprshutdown.wait(TIMEOUT)
        return
    except subprocess.TimeoutExpired:
        pass
    for pid in holding_up(hyprshutdown.pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
    try:
        hyprshutdown.wait(GRACE)
        return
    except subprocess.TimeoutExpired:
        pass
    CLOSED.touch()
    hyprshutdown.terminate()
    subprocess.run(["sh", "-c", command], check=False)


def main(label: str, command: str) -> None:
    if not shutil.which("hyprshutdown"):
        os.execvp("sh", ["sh", "-c", command])

    CLOSED.unlink(missing_ok=True)
    post = f"touch {shlex.quote(str(CLOSED))}; {command}"
    hyprshutdown = subprocess.Popen(["hyprshutdown", "--no-fork", "-t", label, "-p", post])
    watchdog = threading.Thread(target=force_quit, args=(hyprshutdown, command), daemon=True)
    watchdog.start()
    hyprshutdown.wait()
    watchdog.join()
    time.sleep(0.5)
    if not CLOSED.exists():
        subprocess.run(["hyprctl", "eval", 'require("autostart").daemons()'], capture_output=True, check=False)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
