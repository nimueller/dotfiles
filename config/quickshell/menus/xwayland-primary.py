#!/usr/bin/env python3
# pyright: strict
"""Makes the main monitor of Machine Settings XWayland's primary output.

  xwayland-primary.py

Run by Hyprland when it starts, reloads and gets a monitor (xwayland.lua).

Without a primary output, X11 programs take the first in the list as the main
screen, and the list follows the order the monitors came up in: games then
pick the resolution of whichever that was. XWayland forgets the primary output
when it goes away (a monitor turned off) and doesn't bring it back, so it's
set again each time. Does nothing without a main monitor, or while it's off.
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, cast

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
MACHINE = CONFIG / "hypr/local.lua"  # Machine Settings' "-- settings:" line (settings.qml)
ATTEMPTS = 40
DELAY = 0.25  # s; XWayland gets a new monitor a moment after Hyprland


def main_description(lua: str) -> str | None:
    """The description of the monitor marked as main in local.lua"""
    line = re.search(r"^-- settings: (.*)$", lua, re.MULTILINE)
    if not line:
        return None
    try:
        settings = json.loads(line[1])
    except ValueError:
        return None
    monitors = cast(list[dict[str, Any]], settings.get("monitors") or [])
    return next((str(m["desc"]) for m in monitors if m.get("main")), None)


def output_name(monitors: list[dict[str, Any]], description: str) -> str | None:
    """Its port now, from `hyprctl monitors -j`: ports can change, descriptions don't"""
    return next((str(m["name"]) for m in monitors if m.get("description") == description), None)


def is_primary(xrandr: str, name: str) -> bool:
    """From xrandr's listing; its exit code is 0 even for an unknown output"""
    return re.search(rf"^{re.escape(name)} connected primary\b", xrandr, re.MULTILINE) is not None


def monitors() -> list[dict[str, Any]]:
    result = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, check=False)
    try:
        return cast(list[dict[str, Any]], json.loads(result.stdout))
    except ValueError:
        return []


def set_primary(name: str) -> bool:
    """True once XWayland has it as primary"""
    subprocess.run(["xrandr", "--output", name, "--primary"], capture_output=True, check=False)
    listing = subprocess.run(["xrandr", "--query"], capture_output=True, text=True, check=False)
    return is_primary(listing.stdout, name)


def main() -> int:
    try:
        description = main_description(MACHINE.read_text())
    except OSError:
        return 0
    name = description and output_name(monitors(), description)
    if not name:
        return 0
    for _ in range(ATTEMPTS):
        if set_primary(name):
            return 0
        time.sleep(DELAY)
    return 1


if __name__ == "__main__":
    sys.exit(main())
