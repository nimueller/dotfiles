# pyright: strict
"""Turns the built-in screen with the device: the orientation of the
accelerometer from iio-sensor-proxy (its monitor-sensor), as the screen's
transform in Hyprland. Touch input follows the screen's transform.

  auto-rotate

Started by the touch mode (config/hypr/modes.lua) and runs for the session;
exits at once without a built-in screen, monitor-sensor or an accelerometer.
A config reload applies the monitor rules of local.lua again, so the current
orientation is applied once more after each one (Hyprland's event socket). A
transform set there (a panel mounted sideways) stays the base the orientation
turns from.
Built with writePython3Bin (pkgs/default.nix); monitor-sensor and hyprctl
come from the system.
"""

import json
import os
import queue
import re
import socket
import subprocess
import sys
import threading
from pathlib import Path

# monitor-sensor's orientations as wl_output transforms (counterclockwise,
# like GNOME maps them)
TRANSFORMS = {"normal": 0, "left-up": 1, "bottom-up": 2, "right-up": 3}
ORIENTATION = re.compile(r"(?:Accelerometer orientation changed: |Has accelerometer \(orientation: )([a-z-]+)")
BUILT_IN = re.compile(r"^(eDP|LVDS|DSI)")
RELOADED = "configreloaded>>"


def orientation(line: str) -> str | None:
    """A line of monitor-sensor → normal, left-up, …; None for others and
    for "undefined" (lying flat)"""
    match = ORIENTATION.search(line)
    return match.group(1) if match and match.group(1) in TRANSFORMS else None


def turn(base: int, quarter_turns: int) -> int:
    """Turns the base transform further; a flipped one (4-7) stays flipped"""
    return (base & 4) | ((base + quarter_turns) % 4)


def lua_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def monitor_rule(monitor: dict[str, object], transform: int) -> str:
    """The monitor as it is now, with another transform"""
    return (
        f"hl.monitor({{ output = {lua_string('desc:' + str(monitor['description']))}, "
        f'mode = "{monitor["width"]}x{monitor["height"]}@{monitor["refreshRate"]}", '
        f'position = "{monitor["x"]}x{monitor["y"]}", scale = {monitor["scale"]}, transform = {transform} }})'
    )


def built_in_monitor() -> dict[str, object] | None:
    result = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, check=False)
    try:
        monitors: list[dict[str, object]] = json.loads(result.stdout)
    except ValueError:
        return None
    return next((m for m in monitors if BUILT_IN.match(str(m.get("name", "")))), None)


def transform_of(monitor: dict[str, object] | None) -> int:
    value = monitor.get("transform") if monitor else 0
    return value if isinstance(value, int) else 0


def apply(monitor: dict[str, object], transform: int) -> None:
    if transform_of(monitor) != transform:
        subprocess.run(["hyprctl", "eval", monitor_rule(monitor, transform)], capture_output=True, check=False)


def watch_sensor(events: "queue.Queue[str | None]") -> None:
    try:
        sensor = subprocess.Popen(["monitor-sensor", "--accel"], stdout=subprocess.PIPE, text=True)
    except OSError:  # iio-sensor-proxy isn't installed
        events.put(None)
        return
    assert sensor.stdout
    for line in sensor.stdout:
        if "=== No accelerometer" in line:
            break
        if found := orientation(line):
            events.put(found)
    sensor.kill()
    events.put(None)


def watch_reloads(events: "queue.Queue[str | None]") -> None:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    path = Path(runtime) / "hypr" / os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "") / ".socket2.sock"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(str(path))
        for line in s.makefile(encoding="utf-8", errors="replace"):
            if line.startswith(RELOADED):
                events.put(RELOADED)


def main(args: list[str]) -> int:
    if args:
        print(__doc__, file=sys.stderr)
        return 2
    monitor = built_in_monitor()
    if not monitor:
        return 0
    base = transform_of(monitor)

    events: queue.Queue[str | None] = queue.Queue()
    threading.Thread(target=watch_sensor, args=(events,), daemon=True).start()
    threading.Thread(target=watch_reloads, args=(events,), daemon=True).start()

    current = "normal"
    applied = base
    while (event := events.get()) is not None:
        monitor = built_in_monitor()
        if not monitor:
            continue
        # A reload brings back the configured transform, unless no rule
        # names the screen: then it keeps the one applied here
        if event == RELOADED and transform_of(monitor) != applied:
            base = transform_of(monitor)
        elif event != RELOADED:
            current = event
        applied = turn(base, TRANSFORMS[current])
        apply(monitor, applied)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
