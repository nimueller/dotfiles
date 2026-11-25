#!/usr/bin/env python3
# pyright: strict
"""The batteries of wireless devices that charge, which UPower hides, for
Batteries.qml.

  charging-batteries.py
  charging-batteries.py --upower-fixed

Prints {"devices": [{"model": ..., "kind": ..., "percent": ..., "state": ...}]}:
  model    the name UPower gives the device: the battery's model_name, else
           the name of its input device
  kind     "keyboard", "mouse", "gamepad", "tablet" or "device"
  percent  0 to 100
  state    always "charging"

Logitech's driver (hid-logitech-hidpp) sets a battery's `online` to 0 while
it charges, as it counts the charge as exact only when discharging or full.
UPower reads `online` of a device's battery as its wireless link, so it takes
the device for disconnected and leaves it out until the cable is unplugged.
A battery that is really out of reach also has `online` 0, but its status is
"Unknown": only those still reporting "Charging" are listed here.

UPower fixed this after 1.91.5. With --upower-fixed, the exit code says
whether the installed UPower is newer (0) or not (1), so Batteries.qml can
remind to remove this script (README, TODO).
"""

import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

POWER_SUPPLY = Path("/sys/class/power_supply")
LAST_UNFIXED_UPOWER = (1, 91, 5)

# UPower's order (up-device-supply.c): the first kind any of the device's
# input nodes has wins
INPUT_KINDS = (
    ("ID_INPUT_JOYSTICK", "gamepad"),
    ("ID_INPUT_KEYBOARD", "keyboard"),
    ("ID_INPUT_TABLET", "tablet"),
    ("ID_INPUT_TOUCHPAD", "device"),
    ("ID_INPUT_MOUSE", "mouse"),
)


@dataclass
class Battery:
    model: str
    kind: str
    percent: float
    state: str


def read_attribute(supply: Path, name: str) -> str:
    """A sysfs attribute, "" where the driver has none or can't answer"""
    try:
        return (supply / name).read_text().strip()
    except OSError:
        return ""


def is_hidden_while_charging(supply: Path) -> bool:
    """A device's battery that charges but reports itself offline"""
    if read_attribute(supply, "type") != "Battery":
        return False
    if read_attribute(supply, "scope") != "Device":
        return False
    if read_attribute(supply, "online") != "0":
        return False
    return read_attribute(supply, "status") == "Charging"


def parse_properties(text: str) -> dict[str, str]:
    """`udevadm info --query=property` output: KEY=VALUE lines"""
    properties: dict[str, str] = {}
    for line in text.splitlines():
        key, separator, value = line.partition("=")
        if separator:
            properties[key] = value
    return properties


def udev_properties(device: Path) -> dict[str, str]:
    result = subprocess.run(
        ["udevadm", "info", "--query=property", f"--path={device.resolve()}"],
        capture_output=True,
        text=True,
        check=False,
    )
    return parse_properties(result.stdout)


def input_nodes(supply: Path) -> list[Path]:
    """The input devices next to the battery, on the same HID device"""
    return sorted((supply / "device/input").glob("input*"))


def kind_of(inputs: list[dict[str, str]]) -> str:
    for property_name, kind in INPUT_KINDS:
        if any(properties.get(property_name) == "1" for properties in inputs):
            return kind
    return "device"


def model_of(supply: Path, inputs: list[Path]) -> str:
    model = read_attribute(supply, "model_name")
    if model != "":
        return model
    for node in inputs:
        name = read_attribute(node, "name")
        if name != "":
            return name
    return ""


def read_battery(supply: Path) -> Battery | None:
    if not is_hidden_while_charging(supply):
        return None
    try:
        percent = float(read_attribute(supply, "capacity"))
    except ValueError:
        return None
    nodes = input_nodes(supply)
    kind = kind_of([udev_properties(node) for node in nodes])
    return Battery(model_of(supply, nodes), kind, percent, "charging")


def batteries() -> list[Battery]:
    found: list[Battery] = []
    for supply in sorted(POWER_SUPPLY.iterdir()):
        battery = read_battery(supply)
        if battery is not None:
            found.append(battery)
    return found


def parse_upower_version(text: str) -> tuple[int, ...] | None:
    """The daemon's version from `upower --version`, None if it isn't there"""
    match = re.search(r"^UPower daemon version (\d+(?:\.\d+)*)", text, re.MULTILINE)
    if not match:
        return None
    return tuple(int(part) for part in match[1].split("."))


def is_upower_fixed() -> bool:
    result = subprocess.run(["upower", "--version"], capture_output=True, text=True, check=False)
    version = parse_upower_version(result.stdout)
    if version is None:
        return False
    return version > LAST_UNFIXED_UPOWER


def main(args: list[str]) -> int:
    if args == ["--upower-fixed"]:
        return 0 if is_upower_fixed() else 1
    if args != []:
        print(__doc__, file=sys.stderr)
        return 2
    print(json.dumps({"devices": [vars(battery) for battery in batteries()]}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
