#!/usr/bin/env python3
# pyright: strict
"""Starts XWayland again when it died while starting up.

  xwayland-restart.py

Run by Hyprland when it starts and when it gets a monitor (xwayland.lua).

A monitor that comes and goes while XWayland starts (a KVM switch connecting
the monitors at login) kills XWayland: it binds the monitor's wl_output after
Hyprland has removed it, and Hyprland ends it with a protocol error. Hyprland
0.57 starts XWayland again only when it dies after starting up; here it keeps
the X11 socket open with nobody behind it, and every program that connects to
it waits forever (Brave's GPU process too, so Brave shows no window).

With a Lua config, Hyprland starts or stops XWayland only on a config reload
in which `xwayland.enabled` changed. So this reloads once with
XWAYLAND_OFF present, which xwayland.lua reads as "XWayland off", and once
without it. While XWayland is off, the runs started by the reloads see
`xwayland.enabled` false and leave it alone. Not run on config.reloaded, so an
XWayland that can't start at all doesn't make it reload in a loop.
"""

import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, cast

RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
XWAYLAND_OFF = RUNTIME / "hypr-xwayland-off"  # read by xwayland.lua
PROC = Path("/proc")
XWAYLAND = "Xwayland"
ZOMBIE = "Z"
SETTLE = 1.0  # s; alive this long, it got past the point where it dies
WAIT = 5.0  # s; Hyprland starts XWayland once its event loop runs
DELAY = 0.25  # s


@dataclass(frozen=True)
class Process:
    name: str
    parent: int
    is_zombie: bool  # ended, not yet collected by its parent


def parse_stat(stat: str) -> Process:
    """From /proc/PID/stat: the command name is in parentheses and may hold
    spaces and parentheses itself; the state and the parent's PID follow it"""
    opening = stat.index("(")
    closing = stat.rindex(")")
    name = stat[opening + 1 : closing]
    fields = stat[closing + 2 :].split()
    return Process(name=name, parent=int(fields[1]), is_zombie=fields[0] == ZOMBIE)


def instance_pid(instances: list[dict[str, Any]], signature: str) -> int | None:
    """Hyprland's PID, from `hyprctl instances -j`"""
    return next((int(i["pid"]) for i in instances if i.get("instance") == signature), None)


def hyprctl_json(*arguments: str) -> Any:
    result = subprocess.run(["hyprctl", "-j", *arguments], capture_output=True, text=True, check=False)
    try:
        return json.loads(result.stdout)
    except ValueError:
        return None


def hyprland_pid() -> int | None:
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") or ""
    instances = hyprctl_json("instances")
    if not isinstance(instances, list):
        return None
    return instance_pid(cast(list[dict[str, Any]], instances), signature)


def is_enabled() -> bool:
    """`xwayland.enabled`; false also while a restart has it off"""
    option = hyprctl_json("getoption", "xwayland:enabled")
    if not isinstance(option, dict):
        return False
    return bool(cast(dict[str, Any], option).get("bool"))


def is_running(hyprland: int) -> bool:
    """Whether Hyprland has an XWayland child; other XWayland servers (a game's
    gamescope) don't count"""
    for stat in PROC.glob("[0-9]*/stat"):
        try:
            process = parse_stat(stat.read_text())
        except (OSError, ValueError, IndexError):
            continue  # the process ended while we looked
        if process.name == XWAYLAND and process.parent == hyprland and not process.is_zombie:
            return True
    return False


def has_settled(hyprland: int) -> bool:
    """True once XWayland has run for SETTLE seconds, false if it isn't running
    after WAIT seconds or dies"""
    deadline = time.monotonic() + WAIT
    running_since: float | None = None
    while time.monotonic() < deadline:
        now = time.monotonic()
        if not is_running(hyprland):
            running_since = None
        elif running_since is None:
            running_since = now
        elif now - running_since >= SETTLE:
            return True
        time.sleep(DELAY)
    return False


def reload() -> None:
    subprocess.run(["hyprctl", "reload"], capture_output=True, check=False)


def restart() -> None:
    XWAYLAND_OFF.touch()
    try:
        reload()
    finally:
        XWAYLAND_OFF.unlink(missing_ok=True)
    reload()


def main() -> int:
    if XWAYLAND_OFF.exists():
        return 0  # a restart is under way
    hyprland = hyprland_pid()
    if hyprland is None:
        return 1
    if not is_enabled():
        return 0
    if has_settled(hyprland):
        return 0
    print("XWayland isn't running, starting it again", file=sys.stderr)
    restart()
    return 0


if __name__ == "__main__":
    sys.exit(main())
