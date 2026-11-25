#!/usr/bin/env python3
# pyright: strict
"""The charge history of the wireless devices' batteries and how long each
one lasts, for the battery menu (battery.qml). DeviceBatteryWatch.qml in the
daemon runs it when a device's charge changes and every few minutes.

  device-battery-log.py '[{"key": ..., "percent": ..., "state": ...}, ...]'

Takes the devices as Batteries.qml lists them: `key` names the device,
`percent` is 0 to 100, `state` "charging" (also full on the cable),
"draining" or "unknown". A device's charge or state that differs from its
last sample is appended to ~/.local/state/device-batteries/samples.csv,
which keeps 60 days.

Prints {"estimates": {key: {"left": ..., "pace": ..., "measured": ...}}} for
each draining device whose pace is known:
  left      seconds until empty at that pace
  pace      percent per second
  measured  "now": since this charge; "before": not enough of that yet, so
            the pace of the charge before

The pace is the charge used over the whole time since the device was last
charged, nights and days off included: a mouse or keyboard drains with how
it's used over the days, not with an hour of gaming. A charge counts as used
up from the first sample after the cable came off to now; it needs at least
MINIMUM_HOURS and MINIMUM_PERCENT. A rise of RISE_PERCENT or more ends a
charge as well: the device was charged where this machine didn't see it
(another computer, the KVM switched away), while smaller ones are the
voltage-based readings of some devices recovering after a load.
"""

import csv
import fcntl
import io
import json
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import cast

STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "device-batteries"
SAMPLES = STATE / "samples.csv"
LOCK = STATE / "lock"
KEEP_DAYS = 60
DAY = 86400
HOUR = 3600
MINIMUM_HOURS = 3
MINIMUM_PERCENT = 3
RISE_PERCENT = 5
STATES = {"charging": "c", "draining": "d", "unknown": "u"}
CHARGING = "c"
DRAINING = "d"


@dataclass
class Sample:
    time: float
    key: str
    percent: float
    state: str  # a letter of STATES


@dataclass
class Estimate:
    left: float
    pace: float
    measured: str


# ---------- The samples ----------


def parse_samples(text: str) -> list[Sample]:
    """The lines of samples.csv; broken ones are left out (a hard power-off
    can leave the last append as NUL bytes)."""
    samples: list[Sample] = []
    for row in csv.reader(io.StringIO(text)):
        if len(row) != 4:
            continue
        stamp, state, percent, key = row
        try:
            samples.append(Sample(float(stamp), key, float(percent), state))
        except ValueError:
            continue
    return samples


def format_samples(samples: list[Sample]) -> str:
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    for sample in samples:
        writer.writerow([int(sample.time), sample.state, f"{sample.percent:g}", sample.key])
    return out.getvalue()


def parse_devices(text: str, now: float) -> list[Sample]:
    """The devices passed in, as samples taken now; anything else is an error"""
    devices = cast(list[dict[str, object]], json.loads(text))
    samples: list[Sample] = []
    for device in devices:
        key = device["key"]
        percent = device["percent"]
        state = STATES[cast(str, device["state"])]
        if not isinstance(key, str) or not isinstance(percent, int | float):
            raise ValueError(f"not a device: {device}")
        samples.append(Sample(now, key, float(percent), state))
    return samples


def new_samples(history: list[Sample], devices: list[Sample]) -> list[Sample]:
    """The devices whose charge or state changed since their last sample"""
    last: dict[str, Sample] = {}
    for sample in history:
        last[sample.key] = sample
    changed: list[Sample] = []
    for device in devices:
        previous = last.get(device.key)
        if previous is None or previous.percent != device.percent or previous.state != device.state:
            changed.append(device)
    return changed


def recent(samples: list[Sample], now: float) -> list[Sample]:
    cutoff = now - KEEP_DAYS * DAY
    return [sample for sample in samples if sample.time >= cutoff]


# ---------- The estimate ----------


def charges(samples: list[Sample]) -> list[list[Sample]]:
    """One device's samples, oldest first, cut into the stretches between
    two charges: no charging sample in them, no rise of RISE_PERCENT"""
    stretches: list[list[Sample]] = []
    current: list[Sample] = []
    for sample in samples:
        is_charged = sample.state == CHARGING
        has_risen = current != [] and sample.percent >= current[-1].percent + RISE_PERCENT
        if is_charged or has_risen:
            if current:
                stretches.append(current)
            current = []
        if not is_charged:
            current.append(sample)
    if current:
        stretches.append(current)
    return stretches


def pace(first: Sample, percent: float, until: float) -> float:
    """Percent per second from the first sample to `percent` at `until`,
    0 while that's too little to tell"""
    used = first.percent - percent
    elapsed = until - first.time
    if elapsed < MINIMUM_HOURS * HOUR or used < MINIMUM_PERCENT:
        return 0
    return used / elapsed


def estimate(samples: list[Sample], now: float) -> Estimate | None:
    """How long one device lasts, from its samples, oldest first; None
    unless it drains now and a pace is known"""
    if not samples or samples[-1].state != DRAINING:
        return None
    stretches = charges(samples)
    *earlier, current = stretches
    percent = current[-1].percent
    current_pace = pace(current[0], percent, now)
    if current_pace:
        return Estimate(percent / current_pace, current_pace, "now")
    for stretch in reversed(earlier):
        earlier_pace = pace(stretch[0], stretch[-1].percent, stretch[-1].time)
        if earlier_pace:
            return Estimate(percent / earlier_pace, earlier_pace, "before")
    return None


def estimates(samples: list[Sample], keys: list[str], now: float) -> dict[str, Estimate]:
    found: dict[str, Estimate] = {}
    for key in keys:
        own = [sample for sample in samples if sample.key == key]
        result = estimate(own, now)
        if result is not None:
            found[key] = result
    return found


# ---------- Files ----------


def save(path: Path, text: str) -> None:
    temp = path.with_suffix(".tmp")
    temp.write_text(text)
    temp.replace(path)


def read_samples() -> list[Sample]:
    try:
        return parse_samples(SAMPLES.read_text())
    except OSError:
        return []


def record(devices: list[Sample], now: float) -> list[Sample]:
    """Appends what changed, drops what's too old, and returns all samples"""
    STATE.mkdir(parents=True, exist_ok=True)
    with LOCK.open("w") as lock:
        # The daemon runs one at a time, but a restart can overlap the last
        fcntl.flock(lock, fcntl.LOCK_EX)
        history = read_samples()
        kept = recent(history, now)
        changed = new_samples(kept, devices)
        if len(kept) < len(history):
            save(SAMPLES, format_samples(kept + changed))
        elif changed:
            with SAMPLES.open("a") as samples_file:
                samples_file.write(format_samples(changed))
        return kept + changed


def main(args: list[str]) -> int:
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    now = time.time()
    try:
        devices = parse_devices(args[0], now)
    except (ValueError, KeyError, TypeError) as error:
        print(f"device-battery-log.py: {error}", file=sys.stderr)
        print(__doc__, file=sys.stderr)
        return 2
    samples = record(devices, now)
    keys = [device.key for device in devices]
    found = estimates(samples, keys, now)
    print(json.dumps({"estimates": {key: vars(value) for key, value in found.items()}}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
