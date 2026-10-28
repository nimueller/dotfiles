#!/usr/bin/env python3
# pyright: strict
"""Waiting updates, for the bar's update chip and the system menu (Updates.qml).

  updates.py

Prints one JSON object:

  {"pacman": 12, "aur": 2, "flatpak": 1, "aurHelper": "yay",
   "flakeAge": 3, "flakeStale": false}

A count is null when its tool is missing or failed (no AUR helper, no
Flatpak, checkupdates offline). flakeAge is the age of the dotfiles'
flake.lock in days: the time since its newest input was updated, null
without the file. CI updates it every week, so a lock older than
FLAKE_STALE_DAYS means this checkout hasn't been pulled (and switched).

The three checks ask the network and take about a second each, so they run
at the same time.
"""

import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

# config/quickshell/menus/updates.py, linked into ~/.config
FLAKE_LOCK = Path(__file__).resolve().parents[3] / "flake.lock"
FLAKE_STALE_DAYS = 14
AUR_HELPERS = ["paru", "yay"]


def count_lines(output: str) -> int:
    return sum(1 for line in output.splitlines() if line.strip())


def flake_age(lock: str, now: float) -> int | None:
    """Whole days since the newest locked input"""
    try:
        nodes = json.loads(lock)["nodes"]
        newest = max(node["locked"]["lastModified"] for node in nodes.values() if "locked" in node)
    except (ValueError, KeyError, TypeError):
        return None
    return max(0, int((now - newest) // 86400))


def main(args: list[str]) -> int:
    if args:
        print(__doc__, file=sys.stderr)
        return 2

    aur_helper = next((h for h in AUR_HELPERS if shutil.which(h)), None)
    # The command and the exit codes that mean it worked: checkupdates
    # exits with 2 when there are none (1 is an error), yay and paru with 1,
    # like pacman -Qu
    commands = {
        "pacman": (["checkupdates"], (0, 2)) if shutil.which("checkupdates") else None,
        "aur": ([aur_helper, "-Qua"], (0, 1)) if aur_helper else None,
        "flatpak": (["flatpak", "remote-ls", "--updates", "--columns=application"], (0,))
        if shutil.which("flatpak")
        else None,
    }
    running = {
        name: subprocess.Popen(command[0], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        for name, command in commands.items()
        if command
    }

    result: dict[str, object] = {}
    for name, command in commands.items():
        process = running.get(name)
        if not process or not command:
            result[name] = None
            continue
        output, _ = process.communicate()
        result[name] = count_lines(output) if process.returncode in command[1] else None

    try:
        age = flake_age(FLAKE_LOCK.read_text(), time.time())
    except OSError:
        age = None
    result["aurHelper"] = aur_helper
    result["flakeAge"] = age
    result["flakeStale"] = age is not None and age > FLAKE_STALE_DAYS
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
