#!/usr/bin/env python3
# pyright: strict
"""The built-in screen's brightness in percent, on one scale for the keys
(Osd.qml) and the slider in the system menu (system.qml).

  backlight.py get | set PERCENT | step +/-PERCENT

Prints the percent afterwards; exits with 1 without a backlight.

A backlight whose driver already maps its values onto a perceived curve
(scale "non-linear", e.g. pwm-backlight on the Surface Pro X) is taken as it
is, others (linear to the power) are bent by an exponent of 4 so the steps
look even. Never below 2 % of the backlight's range, where the screen goes
dark (brightnessctl's own -n takes raw steps, not percent).
"""

import subprocess
import sys
from pathlib import Path

MIN = 2  # % of the raw range
EXPONENT = 4


def to_percent(raw: int, max_raw: int, exponent: float) -> int:
    return int(100 * (raw / max_raw) ** (1 / exponent) + 0.5)


def to_raw(percent: float, max_raw: int, exponent: float) -> int:
    """At least MIN % of the range"""
    percent = min(max(percent, 0), 100)
    raw = max(max_raw * (percent / 100) ** exponent, max_raw * MIN / 100)
    return int(raw + 0.5)


def main(args: list[str]) -> int:
    # "intel_backlight,backlight,cur,percent%,max"
    info = subprocess.run(
        ["brightnessctl", "-m", "-c", "backlight", "info"], capture_output=True, text=True, check=False
    )
    fields = info.stdout.strip().split(",")
    if info.returncode != 0 or len(fields) != 5:
        return 1
    device, cur, max_raw = fields[0], int(fields[2]), int(fields[4])
    scale = Path(f"/sys/class/backlight/{device}/scale")
    exponent = 1 if scale.exists() and scale.read_text().strip() == "non-linear" else EXPONENT

    match args:
        case [] | ["get"]:
            new = cur
        case ["set", percent]:
            new = to_raw(int(percent), max_raw, exponent)
        case ["step", step]:
            new = to_raw(to_percent(cur, max_raw, exponent) + int(step), max_raw, exponent)
        case _:
            print(__doc__, file=sys.stderr)
            return 2
    if new != cur:
        subprocess.run(["brightnessctl", "-q", "-d", device, "set", str(new)], check=False)
    print(to_percent(new, max_raw, exponent))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
