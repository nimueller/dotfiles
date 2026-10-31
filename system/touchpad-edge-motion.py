#!/usr/bin/python3
# pyright: strict
"""Keeps a drag going at the edge of a touchpad, as Windows does.

    touchpad-edge-motion /dev/input/eventN

The finger runs out of touchpad long before a selection box is big enough, and
libinput has no option for it. During a drag, with the touchpad pressed down
or with a tap and a touch right after it, this moves the pointer on towards
the edge while the finger sits in the outer few millimetres, until the finger
comes back or lets go.

Runs as root, one process per touchpad (touchpad-edge-motion@.service, started
by a udev rule from system/setup.sh): only root may open /dev/uinput. It only
reads the touchpad, without grabbing it, and moves the pointer through a
virtual mouse.
"""

import fcntl
import os
import select
import struct
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

ZONE_MM = 5  # how far in from the edge a finger counts as being at it
SPEED = 300  # pointer units per second, before the pointer acceleration
TICK = 0.01  # seconds between steps of the pointer
# A tapped drag shows no button on the device: it's told by its timing, with
# libinput's limits (180 ms, 1.3 mm) and a little room for the first one
TAP_SECONDS = 0.2
TAP_MOVE_MM = 1.3

EVENT = struct.Struct("qqHHi")  # struct input_event on a 64-bit kernel
ABSINFO = struct.Struct("6i")

EV_SYN, EV_KEY, EV_REL, EV_ABS = 0, 1, 2, 3
SYN_REPORT, SYN_DROPPED = 0, 3
REL_X, REL_Y = 0, 1
BTN_LEFT = 0x110
ABS_MT_SLOT = 0x2F
ABS_MT_POSITION_X = 0x35
ABS_MT_POSITION_Y = 0x36
ABS_MT_TRACKING_ID = 0x39

EVIOCGABS = 0x80184540
UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_SET_RELBIT = 0x40045566
UI_DEV_SETUP = 0x405C5503
UI_DEV_CREATE = 0x5501
BUS_VIRTUAL = 6


@dataclass
class Finger:
    # The kernel only reports what changed: a new touch at the same height as
    # the slot's last one sends no Y, so these outlive the touch.
    x: int = 0
    y: int = 0
    down: bool = False
    fresh: bool = False  # came down in this report
    since: float = 0.0
    start_x: int = 0
    start_y: int = 0
    moved: bool = False  # too far for a tap
    ignored: set[str] = field(default_factory=set[str])


class Tracker:
    """Follows the touchpad's events and says where the pointer should go.

    A finger that is at an edge already when it comes down or presses doesn't
    count until it has left that edge. Otherwise a thumb holding the button at
    the bottom, while a finger drags, would pull the pointer down, and a click
    in a corner would move it.
    """

    def __init__(self, width: int, height: int, units: int, slot: int = 0) -> None:
        self.width, self.height = width, height
        self.zone = ZONE_MM * units
        self.tap_move = TAP_MOVE_MM * units
        self.slot = slot
        self.fingers: dict[int, Finger] = {}
        self.pressed = False
        self.tap_dragging = False
        self.was_holding = False
        self.now = 0.0
        self.tapped_at: float | None = None
        self.several = False  # more than one finger since the pad was last free

    def holding(self) -> bool:
        return self.pressed or self.tap_dragging

    def event(self, kind: int, code: int, value: int, now: float = 0.0) -> None:
        self.now = now
        if kind == EV_KEY and code == BTN_LEFT:
            self.pressed = value != 0
        elif kind == EV_SYN and code == SYN_REPORT:
            self.report()
        elif kind == EV_SYN and code == SYN_DROPPED:
            # Events got lost, a release perhaps: rather stop than run on
            self.pressed = self.tap_dragging = False
            self.tapped_at = None
            for finger in self.fingers.values():
                finger.down = False
        elif kind == EV_ABS:
            self.absolute(code, value)

    def absolute(self, code: int, value: int) -> None:
        if code == ABS_MT_SLOT:
            self.slot = value
            return
        finger = self.fingers.setdefault(self.slot, Finger())
        if code == ABS_MT_POSITION_X:
            finger.x = value
        elif code == ABS_MT_POSITION_Y:
            finger.y = value
        elif code == ABS_MT_TRACKING_ID:
            if value >= 0:
                self.touched(finger)
            else:
                self.lifted(finger)

    def down(self) -> int:
        return sum(finger.down for finger in self.fingers.values())

    def tapped_just_now(self) -> bool:
        return self.tapped_at is not None and self.now - self.tapped_at <= TAP_SECONDS

    def touched(self, finger: Finger) -> None:
        finger.down = finger.fresh = True
        finger.since = self.now
        finger.moved = False
        if self.down() > 1:
            self.several = True
        elif self.tapped_just_now():
            self.tap_dragging = True
        self.tapped_at = None

    def lifted(self, finger: Finger) -> None:
        finger.down = False
        if self.down() > 0:
            return
        quick = self.now - finger.since <= TAP_SECONDS
        was_tap = quick and not finger.moved and not self.several and not self.pressed
        self.tapped_at = self.now if was_tap else None
        self.tap_dragging = self.several = False

    def edges(self, finger: Finger) -> set[str]:
        found: set[str] = set()
        if finger.x < self.zone:
            found.add("left")
        if finger.x > self.width - self.zone:
            found.add("right")
        if finger.y < self.zone:
            found.add("top")
        if finger.y > self.height - self.zone:
            found.add("bottom")
        return found

    def report(self) -> None:
        starting = self.holding() and not self.was_holding
        self.was_holding = self.holding()
        for finger in self.fingers.values():
            at = self.edges(finger)
            if finger.fresh:
                finger.start_x, finger.start_y = finger.x, finger.y
            elif max(abs(finger.x - finger.start_x), abs(finger.y - finger.start_y)) > self.tap_move:
                finger.moved = True
            if finger.fresh or starting:
                finger.ignored = at
            else:
                finger.ignored &= at
            finger.fresh = False

    def direction(self) -> tuple[int, int]:
        """Where to push the pointer: -1, 0 or 1 on each axis."""
        if not self.holding():
            return 0, 0
        for finger in self.fingers.values():
            at = self.edges(finger) - finger.ignored
            if finger.down and at:
                return ("right" in at) - ("left" in at), ("bottom" in at) - ("top" in at)
        return 0, 0


def axis_range(fd: int, code: int) -> tuple[int, int, int]:
    """The (largest value, current value, units per mm) of an axis"""
    info = bytearray(ABSINFO.size)
    fcntl.ioctl(fd, EVIOCGABS + code, info)
    value, _minimum, maximum, _fuzz, _flat, resolution = ABSINFO.unpack(info)
    return maximum, value, resolution


def virtual_mouse() -> int:
    fd = os.open("/dev/uinput", os.O_WRONLY)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_REL)
    fcntl.ioctl(fd, UI_SET_RELBIT, REL_X)
    fcntl.ioctl(fd, UI_SET_RELBIT, REL_Y)
    # Never pressed, but without a button nothing takes it for a mouse
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_LEFT)
    setup = struct.pack("4H80sI", BUS_VIRTUAL, 0, 0, 0, b"touchpad-edge-motion", 0)
    fcntl.ioctl(fd, UI_DEV_SETUP, setup)
    fcntl.ioctl(fd, UI_DEV_CREATE)
    return fd


def move(mouse: int, x: int, y: int) -> None:
    events = [EVENT.pack(0, 0, EV_REL, REL_X, x), EVENT.pack(0, 0, EV_REL, REL_Y, y)]
    os.write(mouse, b"".join(events) + EVENT.pack(0, 0, EV_SYN, SYN_REPORT, 0))


def run(device: str) -> None:
    fd = os.open(device, os.O_RDONLY)
    width, _, resolution = axis_range(fd, ABS_MT_POSITION_X)
    height, _, _ = axis_range(fd, ABS_MT_POSITION_Y)
    _, slot, _ = axis_range(fd, ABS_MT_SLOT)
    # Touchpads without a resolution report: about a hundred units per mm of a 10 cm pad
    units = resolution or width // 100
    tracker = Tracker(width, height, units, slot)
    mouse = virtual_mouse()
    step = max(round(SPEED * TICK), 1)
    next_step = 0.0
    while True:
        wait = None
        if tracker.direction() != (0, 0):
            wait = max(next_step - time.monotonic(), 0)
        ready, _, _ = select.select([fd], [], [], wait)
        if ready:
            try:
                data = os.read(fd, EVENT.size * 64)
            except OSError:  # unplugged: the udev rule starts a new one for it
                return
            for sec, usec, kind, code, value in EVENT.iter_unpack(data):
                tracker.event(kind, code, value, sec + usec / 1e6)
        # By the clock, not when the touchpad is quiet: a finger resting at the
        # edge keeps reporting, faster than a tick
        x, y = tracker.direction()
        if (x, y) != (0, 0) and time.monotonic() >= next_step:
            move(mouse, x * step, y * step)
            next_step = time.monotonic() + TICK


def main() -> None:
    if len(sys.argv) != 2 or not Path(sys.argv[1]).exists():
        sys.exit(__doc__)
    run(sys.argv[1])


if __name__ == "__main__":
    main()
