#!/usr/bin/env python3
# pyright: strict
"""The batteries of Corsair's wireless headsets and mice, which UPower
doesn't know, for Batteries.qml.

  corsair-battery.py

Prints {"devices": [{"model": ..., "kind": ..., "percent": ..., "state": ...}]}:
  model    the device's name from its receiver, "" where the receiver serves
           all kinds of devices (Slipstream) and so doesn't name it
  kind     "headset" for a receiver with sound, "mouse" otherwise
  percent  0 to 100
  state    "charging", "discharging" or "unknown"
A device that is off or out of reach is left out.

The receivers speak Corsair's "Bragi" protocol on a HID interface of their
own (usage page 0xFF42), where the battery is a property of the device
paired with the receiver. This only asks for properties, it never sets one.
It needs read and write access to the receivers' /dev/hidraw*, which the
udev rule from system/setup.sh gives the logged-in user.
"""

import fcntl
import json
import os
import select
import sys
from dataclasses import dataclass
from pathlib import Path

HIDRAW = Path("/sys/class/hidraw")
CORSAIR = 0x1B1C
LOCK_NAME = "corsair-battery.lock"
ANSWER_TIMEOUT = 0.5  # seconds
REPORTS_PER_ANSWER = 5  # events the device sends on its own may come first
READ_SIZE = 256

# HID report descriptor items: the tag with its size bits cleared
USAGE_PAGE = 0x04
USAGE = 0x08
COLLECTION = 0xA0
END_COLLECTION = 0xC0
REPORT_ID = 0x84
REPORT_COUNT = 0x94
INPUT = 0x80
OUTPUT = 0x90
BRAGI_USAGE_PAGE = 0xFF42
BRAGI_USAGE = 0x01

# Bragi: the device behind the receiver, asked for a property, and its index
# in the answer
PAIRED_DEVICE = 0x09
PAIRED_DEVICE_IN_ANSWER = 0x01
GET_PROPERTY = 0x02
ANSWER_OK = 0x00
BATTERY_LEVEL = 0x0F  # in tenths of a percent
BATTERY_STATUS = 0x10
STATES = {1: "charging", 2: "discharging"}

AUDIO_CLASS = "01"  # bInterfaceClass of a USB audio interface
SHARED_RECEIVER = "SLIPSTREAM"
NAME_PREFIX = "CORSAIR "
NAME_SUFFIXES = (" Gaming Receiver", " Receiver")


@dataclass
class BragiInterface:
    """The reports of the Bragi interface; report id 0 means it uses none"""

    input_report_id: int
    output_report_id: int
    output_size: int


@dataclass
class Battery:
    model: str
    kind: str
    percent: float
    state: str


def descriptor_items(descriptor: bytes) -> list[tuple[int, int]]:
    """The short items of a HID report descriptor as (tag, value)"""
    items: list[tuple[int, int]] = []
    i = 0
    while i < len(descriptor):
        prefix = descriptor[i]
        size = [0, 1, 2, 4][prefix & 0x03]
        value = int.from_bytes(descriptor[i + 1 : i + 1 + size], "little")
        items.append((prefix & 0xFC, value))
        i += 1 + size
    return items


def find_bragi_interface(descriptor: bytes) -> BragiInterface | None:
    """The reports of the Bragi collection, if the descriptor has one"""
    usage_page = 0
    usage = 0
    report_id = 0
    report_count = 0
    is_inside = False
    found = BragiInterface(0, 0, 0)
    for tag, value in descriptor_items(descriptor):
        if tag == USAGE_PAGE:
            usage_page = value
        elif tag == USAGE:
            usage = value
        elif tag == COLLECTION and usage_page == BRAGI_USAGE_PAGE and usage == BRAGI_USAGE:
            is_inside = True
        elif tag == END_COLLECTION and is_inside:
            return found if found.output_size > 0 else None
        elif tag == REPORT_ID:
            report_id = value
        elif tag == REPORT_COUNT:
            report_count = value
        elif tag == INPUT and is_inside:
            found.input_report_id = report_id
        elif tag == OUTPUT and is_inside:
            found.output_report_id = report_id
            found.output_size = report_count
    return None


def get_property_request(interface: BragiInterface, prop: int) -> bytes:
    """The output report that asks the paired device for a property; hidraw
    wants the report id first, 0 for an interface without ids"""
    request = bytes([PAIRED_DEVICE, GET_PROPERTY, prop])
    report = request.ljust(interface.output_size, b"\0")
    return bytes([interface.output_report_id]) + report


def parse_answer(interface: BragiInterface, report: bytes) -> int | None:
    """The value of an answer to a property request, None for an event or a
    refusal (e.g. the device is off)"""
    data = report[1:] if interface.input_report_id != 0 else report
    if len(data) < 5:
        return None
    is_answer = data[0] == PAIRED_DEVICE_IN_ANSWER and data[1] == GET_PROPERTY
    if not is_answer:
        return None
    if data[2] != ANSWER_OK:
        return None
    return int.from_bytes(data[3:5], "little")


def battery_state(status: int | None) -> str:
    if status is None:
        return "unknown"
    return STATES.get(status, "unknown")


def model_name(product: str) -> str:
    """The device's name from its receiver's ("CORSAIR VOID Wireless
    Gaming Receiver"), "" for a receiver that serves several kinds"""
    if SHARED_RECEIVER in product.upper():
        return ""
    name = product.removeprefix(NAME_PREFIX)
    for suffix in NAME_SUFFIXES:
        name = name.removesuffix(suffix)
    return name.strip()


def is_corsair(hidraw: Path) -> bool:
    """HID_ID=0003:00001B1C:00000A6B in the uevent: bus, vendor, product"""
    for line in (hidraw / "device/uevent").read_text().splitlines():
        if line.startswith("HID_ID="):
            vendor = line.removeprefix("HID_ID=").split(":")[1]
            return int(vendor, 16) == CORSAIR
    return False


def usb_device(hidraw: Path) -> Path:
    """The receiver's USB device: hidraw -> HID device -> USB interface -> USB device"""
    return (hidraw / "device").resolve().parent.parent


def has_sound(usb: Path) -> bool:
    for interface_class in usb.glob("*:*/bInterfaceClass"):
        if interface_class.read_text().strip() == AUDIO_CLASS:
            return True
    return False


def ask(fd: int, interface: BragiInterface, prop: int) -> int | None:
    """One property of the paired device, None without an answer"""
    os.write(fd, get_property_request(interface, prop))
    for _ in range(REPORTS_PER_ANSWER):
        readable, _, _ = select.select([fd], [], [], ANSWER_TIMEOUT)
        if not readable:
            return None
        value = parse_answer(interface, os.read(fd, READ_SIZE))
        if value is not None:
            return value
    return None


def read_battery(hidraw: Path, interface: BragiInterface) -> Battery | None:
    usb = usb_device(hidraw)
    fd = os.open(f"/dev/{hidraw.name}", os.O_RDWR)
    try:
        level = ask(fd, interface, BATTERY_LEVEL)
        status = ask(fd, interface, BATTERY_STATUS)
    finally:
        os.close(fd)
    if level is None:
        return None
    product = (usb / "product").read_text().strip()
    kind = "headset" if has_sound(usb) else "mouse"
    return Battery(model_name(product), kind, level / 10, battery_state(status))


def receivers() -> list[tuple[Path, BragiInterface]]:
    found: list[tuple[Path, BragiInterface]] = []
    for hidraw in sorted(HIDRAW.glob("hidraw*")):
        if not is_corsair(hidraw):
            continue
        descriptor = (hidraw / "device/report_descriptor").read_bytes()
        interface = find_bragi_interface(descriptor)
        if interface is not None:
            found.append((hidraw, interface))
    return found


def batteries() -> list[Battery]:
    found: list[Battery] = []
    for hidraw, interface in receivers():
        try:
            battery = read_battery(hidraw, interface)
        except OSError as error:
            # No access without the udev rule, or the receiver was unplugged
            print(f"{hidraw.name}: {error}", file=sys.stderr)
            continue
        if battery is not None:
            found.append(battery)
    return found


def main(args: list[str]) -> int:
    if args != []:
        print(__doc__, file=sys.stderr)
        return 2
    # Answers carry no request id, and every open hidraw gets each of them:
    # the shell's processes must not ask at the same time
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")
    with (runtime / LOCK_NAME).open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        found = batteries()
    print(json.dumps({"devices": [vars(battery) for battery in found]}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
