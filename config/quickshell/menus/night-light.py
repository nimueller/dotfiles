#!/usr/bin/env python3
# pyright: strict
"""The night light's schedule: warmer colours (hyprsunset) at night, run by
daemon.qml for the session. Machine Settings (settings.qml) sets it in the
"-- settings:" line of local.lua, as "nightLight":

  {"schedule": "sun", "from": "21:00", "until": "07:00", "temperature": 4500}

schedule "sun" is from sunset to sunrise at this machine's location (also
in local.lua), else at the calendar menu's weather location, else FALLBACK;
"times" from `from` until `until`; "off" only by hand (the system menu's
switch). Missing or invalid values are DEFAULTS.

  night-light.py

Once a minute it works out whether it's night, and only when that (or the
temperature) changes does it tell hyprsunset (hyprctl hyprsunset), so the
system menu's switch (system.qml) holds until the next change. For the
system menu it writes the day's times to $XDG_RUNTIME_DIR/night-light.json:

  {"night": true, "schedule": "sun", "from": "16:51", "until": "07:12",
   "place": "Berlin", "temperature": 4500}

(from and until are null for "off" and on days the sun doesn't set or rise,
place is null unless the times are a place's sunset and sunrise.)
"""

import json
import math
import os
import re
import subprocess
import sys
import time
from datetime import UTC, date, datetime, timezone
from pathlib import Path
from typing import cast

DEFAULTS: dict[str, object] = {"schedule": "sun", "from": "21:00", "until": "07:00", "temperature": 4500}
SCHEDULES = ("sun", "times", "off")
TEMPERATURES = (1000, 6000)  # K, hyprsunset's range that tints at all
FALLBACK = ("19:00", "07:00")  # "sun" without a location: from, until
HHMM = re.compile(r"^([01]?\d|2[0-3]):[0-5]\d$")
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
MACHINE = CONFIG / "hypr/local.lua"  # Machine Settings' "-- settings:" line (settings.qml)
CALENDAR = Path.home() / ".local/state/quickshell-calendar.json"  # calendar.qml's settings
STATE = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "night-light.json"
J2000 = 2451545.0  # Julian date of 2000-01-01 12:00 UTC
UNIX_EPOCH = 2440587.5  # Julian date of 1970-01-01 00:00 UTC
POLAR_NIGHT = "polar night"
MIDNIGHT_SUN = "midnight sun"


def sun_times(day: date, lat: float, lon: float) -> tuple[datetime, datetime] | str:
    """Sunrise and sunset in UTC (the sunrise equation, within a minute or
    two), or POLAR_NIGHT / MIDNIGHT_SUN when the sun doesn't rise or set"""
    rad = math.radians
    n = day.toordinal() - date(2000, 1, 1).toordinal() + 0.0008
    mean_noon = n - lon / 360
    anomaly = (357.5291 + 0.98560028 * mean_noon) % 360
    center = 1.9148 * math.sin(rad(anomaly)) + 0.02 * math.sin(rad(2 * anomaly)) + 0.0003 * math.sin(rad(3 * anomaly))
    longitude = (anomaly + center + 180 + 102.9372) % 360
    transit = J2000 + mean_noon + 0.0053 * math.sin(rad(anomaly)) - 0.0069 * math.sin(rad(2 * longitude))
    declination = math.asin(math.sin(rad(longitude)) * math.sin(rad(23.4397)))
    # -0.833°: refraction and the sun's radius, the official sunrise
    cos_hour = (math.sin(rad(-0.833)) - math.sin(rad(lat)) * math.sin(declination)) / (
        math.cos(rad(lat)) * math.cos(declination)
    )
    if cos_hour > 1:
        return POLAR_NIGHT
    if cos_hour < -1:
        return MIDNIGHT_SUN
    half_day = math.degrees(math.acos(cos_hour)) / 360

    def utc(julian: float) -> datetime:
        return datetime.fromtimestamp((julian - UNIX_EPOCH) * 86400, UTC)

    return utc(transit - half_day), utc(transit + half_day)


def at(day: date, hhmm: str, tz: timezone) -> datetime:
    hours, minutes = hhmm.split(":")
    return datetime(day.year, day.month, day.day, int(hours), int(minutes), tzinfo=tz)


def options(settings: object) -> dict[str, object]:
    """settings["nightLight"] over DEFAULTS, invalid values left out"""
    given: object = cast(dict[str, object], settings).get("nightLight") if isinstance(settings, dict) else None
    night = cast(dict[str, object], given) if isinstance(given, dict) else {}
    out = dict(DEFAULTS)
    if night.get("schedule") in SCHEDULES:
        out["schedule"] = night["schedule"]
    for key in ("from", "until"):
        value = night.get(key)
        if isinstance(value, str) and HHMM.match(value):
            out[key] = value
    temperature = night.get("temperature")
    if isinstance(temperature, int | float) and TEMPERATURES[0] <= temperature <= TEMPERATURES[1]:
        out["temperature"] = int(temperature)
    return out


def schedule(now: datetime, place: dict[str, object] | None, opts: dict[str, object]) -> dict[str, object]:
    """Whether it's night at `now` (local, with tzinfo), and the day's times"""
    state: dict[str, object] = {"schedule": opts["schedule"], "temperature": opts["temperature"], "place": None}
    if opts["schedule"] == "off":
        return {"night": False, "from": None, "until": None, **state}
    tz = now.tzinfo if isinstance(now.tzinfo, timezone) else UTC
    if opts["schedule"] == "times":
        start, end = at(now.date(), str(opts["from"]), tz), at(now.date(), str(opts["until"]), tz)
    elif place is not None:
        state["place"] = place.get("name")
        times = sun_times(now.date(), float(str(place["lat"])), float(str(place["lon"])))
        if isinstance(times, str):
            return {"night": times == POLAR_NIGHT, "from": None, "until": None, **state}
        end, start = (t.astimezone(now.tzinfo) for t in times)
    else:
        start, end = at(now.date(), FALLBACK[0], tz), at(now.date(), FALLBACK[1], tz)
    # Across midnight (the usual) or within the day
    night = (now >= start or now < end) if start > end else start <= now < end
    return {"night": night, "from": start.strftime("%H:%M"), "until": end.strftime("%H:%M"), **state}


def place_in(settings: object) -> dict[str, object] | None:
    """settings["location"] if it's a place with lat and lon"""
    if not isinstance(settings, dict):
        return None
    place: object = cast(dict[str, object], settings).get("location")
    if isinstance(place, dict) and "lat" in place and "lon" in place:
        return cast(dict[str, object], place)
    return None


def machine_settings(lua: str) -> object:
    """The JSON of local.lua's "-- settings:" line, None without one"""
    line = re.search(r"^-- settings: (.*)$", lua, re.MULTILINE)
    return json.loads(line[1]) if line else None


def read_machine_settings() -> object:
    try:
        return machine_settings(MACHINE.read_text())
    except (OSError, ValueError):
        return None


def location(settings: object) -> dict[str, object] | None:
    """The machine's location, else the calendar's"""
    place = place_in(settings)
    if place is None:
        try:
            place = place_in(json.loads(CALENDAR.read_text()))
        except (OSError, ValueError):
            pass
    return place


def tell_hyprsunset(night: bool, temperature: int) -> bool:
    """False while hyprsunset isn't there (yet): try again next minute"""
    command = ["temperature", str(temperature)] if night else ["identity"]
    result = subprocess.run(["hyprctl", "hyprsunset", *command], capture_output=True, text=True, check=False)
    return result.returncode == 0 and result.stdout.strip() == "ok"


def main(args: list[str]) -> int:
    if args:
        print(__doc__, file=sys.stderr)
        return 2
    told: tuple[bool, int | None] | None = None
    while True:
        settings = read_machine_settings()
        state = schedule(datetime.now().astimezone(), location(settings), options(settings))
        night = bool(state["night"])
        temperature = int(str(state["temperature"]))
        # The temperature only matters at night: changing it by day keeps a
        # night light that was switched on by hand
        wanted = (night, temperature if night else None)
        if wanted != told and tell_hyprsunset(night, temperature):
            told = wanted
        try:
            STATE.write_text(json.dumps(state) + "\n")
        except OSError:
            pass
        # On the minute, so a change comes on time
        time.sleep(60 - datetime.now().second + 1)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
