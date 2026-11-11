#!/usr/bin/env python3
# pyright: strict
"""The calendar menu's weather (calendar.qml) from the open data of the
Deutscher Wetterdienst, so the place asked about goes to no one else.

  weather.py LAT LON

Prints JSON:

  {"forecast": {"station": STATION, "issued": EPOCH},
   "hourly": [{"time": "yyyy-MM-ddTHH:mm", "temp", "code", "rain", "night"}],
   "daily": {"yyyy-MM-dd": {"code", "max", "min", "rain"}},
   "current": {"station": STATION, "time": EPOCH, "code", "night", "temp",
               "dewPoint", "humidity", "windDirection", "windSpeed", "gusts",
               "visibility", "pressure", "cloudCover", "cloudBase", "rain"}
              or null}

STATION is {"id", "name", "distance"} with the distance in km. Times and days
are local; temperatures in °C, rain as the chance in % of more than 0.1 mm in
an hour, wind in km/h, visibility in km, pressure in hPa (sea level), cloud
cover in %, the cloud base in m and `current.rain` in mm in the last hour.
Values a station didn't report are null. On failure {"error": "..."} and exit
status 1.

The forecast is MOSMIX_L of the nearest forecast point: hourly for ten days,
issued four times a day. The current weather is the newest hourly report of
the nearest station within REPORT_MAX_DISTANCE that reported in the last
REPORT_MAX_AGE (the "POI" reports), null if there is none.

`code` is a WMO present weather code (table 4677), as Weather.qml describes
them: MOSMIX's significant weather already is one, the stations' own codes
are mapped (REPORT_CODES).

The list of forecast points (with the reporting stations among them) is the
MOSMIX station catalogue on www.dwd.de, cached for CATALOGUE_MAX_AGE in
~/.cache/quickshell-weather-stations.cfg.
"""

import io
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import TypedDict

OPENDATA = "https://opendata.dwd.de/weather"
FORECAST_URL = f"{OPENDATA}/local_forecasts/mos/MOSMIX_L/single_stations/{{id}}/kml/MOSMIX_L_LATEST_{{id}}.kmz"
REPORTS_URL = f"{OPENDATA}/weather_reports/poi/"
REPORT_URL = f"{REPORTS_URL}{{id}}-BEOB.csv"
CATALOGUE_URL = "https://www.dwd.de/DE/leistungen/met_verfahren_mosmix/mosmix_stationskatalog.cfg?view=nasPublication"
CATALOGUE_FILE = "quickshell-weather-stations.cfg"
CATALOGUE_MAX_AGE = 30 * 24 * 3600  # s
TIMEOUT = 20  # s

FORECAST_TRIES = 3  # nearest points; not every one in the catalogue has a forecast
REPORT_TRIES = 3
REPORT_MAX_DISTANCE = 50  # km
REPORT_MAX_AGE = 3 * 3600  # s

KELVIN = 273.15
EARTH_RADIUS = 6371  # km

KML = {
    "kml": "http://www.opengis.net/kml/2.2",
    "dwd": "https://opendata.dwd.de/weather/lib/pointforecast_dwd_extension_V1_0.xsd",
}
KML_MISSING = "-"
REPORT_MISSING = "---"
REPORT_HEADER_ROWS = 3  # English names, units, German names

# The reports' present weather (DWD's own code table for the POI reports)
# as WMO codes. 31, gusts, says nothing about the sky: the cloud cover does.
REPORT_CODES = {
    1: 0,  # clear
    2: 1,  # mostly clear
    3: 2,  # partly cloudy
    4: 3,  # overcast
    5: 45,  # fog
    6: 48,  # freezing fog
    7: 61,  # light rain
    8: 63,  # rain
    9: 65,  # heavy rain
    10: 66,  # freezing rain
    11: 67,  # heavy freezing rain
    12: 68,  # sleet
    13: 69,  # heavy sleet
    14: 71,  # light snow
    15: 73,  # snow
    16: 75,  # heavy snow
    17: 77,  # snow pellets
    18: 80,  # rain showers
    19: 81,  # heavy rain showers
    20: 83,  # sleet showers
    21: 84,  # heavy sleet showers
    22: 85,  # snow showers
    23: 86,  # heavy snow showers
    24: 85,  # snow pellet showers, shown as snow showers
    25: 86,  # heavy snow pellet showers
    26: 95,  # thunderstorm without rain
    27: 95,  # thunderstorm
    28: 95,  # heavy thunderstorm
    29: 96,  # thunderstorm with hail
    30: 99,  # heavy thunderstorm with hail
}
# Upper limits of cloud cover (%) for WMO codes 0 to 2, else 3 (overcast)
CLOUD_CODE_LIMITS = (12.5, 37.5, 75.0)


@dataclass(frozen=True)
class Station:
    id: str
    name: str
    lat: float
    lon: float


class StationInfo(TypedDict):
    id: str
    name: str
    distance: float


@dataclass(frozen=True)
class Hour:
    time: datetime  # UTC, the end of the hour the values are for
    temp: float
    code: int
    rain: float | None
    is_night: bool


class Fail(Exception):
    pass


# Stations ---------------------------------------------------------------------


def degrees(degrees_minutes: str) -> float:
    """The catalogue's "50.03" (50° 3') -> 50.05"""
    sign = -1 if degrees_minutes.startswith("-") else 1
    whole, minutes = degrees_minutes.lstrip("-").split(".")
    return sign * (int(whole) + int(minutes) / 60)


def parse_catalogue(text: str) -> list[Station]:
    """The MOSMIX station catalogue: a header, a line of dashes, then
    "ID    ICAO NAME                 LAT    LON     ELEV" per station"""
    stations: list[Station] = []
    for line in text.splitlines()[2:]:
        fields = line[5:].split()
        if len(fields) < 5:
            continue
        name = " ".join(fields[1:-3])
        stations.append(Station(line[:5].strip(), name.title(), degrees(fields[-3]), degrees(fields[-2])))
    return stations


def distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    sin_lat = math.sin(math.radians(lat2 - lat1) / 2)
    sin_lon = math.sin(math.radians(lon2 - lon1) / 2)
    a = sin_lat**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * sin_lon**2
    return 2 * EARTH_RADIUS * math.asin(math.sqrt(a))


def by_distance(stations: list[Station], lat: float, lon: float) -> list[tuple[float, Station]]:
    with_distance = [(distance_km(lat, lon, s.lat, s.lon), s) for s in stations]
    return sorted(with_distance, key=lambda pair: pair[0])


def station_info(distance: float, station: Station) -> StationInfo:
    return {"id": station.id, "name": station.name, "distance": round(distance, 1)}


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=TIMEOUT) as response:
        data: bytes = response.read()
        return data


def load_catalogue() -> list[Station]:
    """From the cache while it's fresh; a stale one still does when the
    download fails"""
    cache_home = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    cached = Path(cache_home) / CATALOGUE_FILE
    if cached.exists() and time.time() - cached.stat().st_mtime < CATALOGUE_MAX_AGE:
        return parse_catalogue(cached.read_text(errors="replace"))
    try:
        text = fetch(CATALOGUE_URL).decode("latin-1")
    except OSError as error:
        if cached.exists():
            return parse_catalogue(cached.read_text(errors="replace"))
        raise Fail("Couldn't load the DWD station list") from error
    cached.parent.mkdir(parents=True, exist_ok=True)
    cached.write_text(text)
    return parse_catalogue(text)


# Forecast ---------------------------------------------------------------------


def kml_values(text: str) -> list[float | None]:
    return [None if value == KML_MISSING else float(value) for value in text.split()]


def parse_forecast(kmz: bytes) -> tuple[datetime, list[Hour]]:
    """MOSMIX_L of one point: a KML in a zip -> (issued, hours with values)"""
    with zipfile.ZipFile(io.BytesIO(kmz)) as archive:
        root = ET.fromstring(archive.read(archive.namelist()[0]))
    issued = datetime.fromisoformat(root.findtext(".//dwd:IssueTime", "", KML))
    times = [datetime.fromisoformat(step.text or "") for step in root.iterfind(".//dwd:TimeStep", KML)]
    series: dict[str, list[float | None]] = {}
    for forecast in root.iterfind(".//dwd:Forecast", KML):
        name = forecast.get(f"{{{KML['dwd']}}}elementName", "")
        series[name] = kml_values(forecast.findtext("dwd:value", "", KML))
    return issued, hours(times, series)


def hours(times: list[datetime], series: dict[str, list[float | None]]) -> list[Hour]:
    """Hours without a temperature or weather (the last days lack some) are
    left out. Night is an hour without sunlight."""
    missing = [None] * len(times)
    out: list[Hour] = []
    for i, at in enumerate(times):
        temp = series.get("TTT", missing)[i]
        code = series.get("ww", missing)[i]
        if temp is None or code is None:
            continue
        radiation = series.get("Rad1h", missing)[i]
        out.append(Hour(at, temp - KELVIN, int(code), series.get("R101", missing)[i], radiation == 0))
    return out


def local_time(at: datetime) -> str:
    return at.astimezone().strftime("%Y-%m-%dT%H:%M")


def hourly_json(forecast: list[Hour]) -> list[dict[str, object]]:
    return [
        {
            "time": local_time(hour.time),
            "temp": round(hour.temp),
            "code": hour.code,
            "rain": None if hour.rain is None else round(hour.rain),
            "night": hour.is_night,
        }
        for hour in forecast
    ]


def daily_json(forecast: list[Hour]) -> dict[str, dict[str, object]]:
    """Per local day: the highest and lowest temperature, the most severe
    weather (the highest code) and the highest chance of rain"""
    days: dict[str, list[Hour]] = {}
    for hour in forecast:
        days.setdefault(local_time(hour.time)[:10], []).append(hour)
    out: dict[str, dict[str, object]] = {}
    for day, day_hours in days.items():
        rain = [hour.rain for hour in day_hours if hour.rain is not None]
        out[day] = {
            "code": max(hour.code for hour in day_hours),
            "max": round(max(hour.temp for hour in day_hours)),
            "min": round(min(hour.temp for hour in day_hours)),
            "rain": round(max(rain)) if rain else None,
        }
    return out


def load_forecast(nearest: list[tuple[float, Station]]) -> tuple[StationInfo, datetime, list[Hour]]:
    for distance, station in nearest[:FORECAST_TRIES]:
        try:
            issued, forecast = parse_forecast(fetch(FORECAST_URL.format(id=station.id)))
        except urllib.error.HTTPError as error:
            print(f"No forecast for {station.id}: {error}", file=sys.stderr)
            continue
        except (OSError, zipfile.BadZipFile, ET.ParseError, ValueError) as error:
            raise Fail("Couldn't load the DWD forecast") from error
        return station_info(distance, station), issued, forecast
    raise Fail("No DWD forecast for this place")


# Current weather --------------------------------------------------------------


def parse_reports_listing(html: str) -> dict[str, datetime]:
    """The reports' directory listing -> station id: when its file changed"""
    pattern = r'href="(\w+)-BEOB\.csv">.*?</a>\s+(\d{2}-\w{3}-\d{4} \d{2}:\d{2})'
    changed: dict[str, datetime] = {}
    for station_id, stamp in re.findall(pattern, html):
        changed[station_id] = datetime.strptime(stamp, "%d-%b-%Y %H:%M").replace(tzinfo=UTC)
    return changed


def report_value(text: str) -> float | None:
    return None if text == REPORT_MISSING else float(text.replace(",", "."))


def cloud_code(cover: float) -> int:
    for code, limit in enumerate(CLOUD_CODE_LIMITS):
        if cover <= limit:
            return code
    return 3


def report_code(weather: float | None, cover: float | None) -> int | None:
    if weather is not None and int(weather) in REPORT_CODES:
        return REPORT_CODES[int(weather)]
    return None if cover is None else cloud_code(cover)


def parse_report(text: str) -> tuple[datetime, dict[str, object]] | None:
    """A station's reports, newest first -> the newest with a temperature:
    (when, values)"""
    lines = text.splitlines()
    names = lines[0].split(";")
    for line in lines[REPORT_HEADER_ROWS:]:
        cells = line.split(";")
        values = {name: report_value(cell) for name, cell in zip(names[2:], cells[2:], strict=False)}
        if values.get("dry_bulb_temperature_at_2_meter_above_ground") is None:
            continue
        at = datetime.strptime(f"{cells[0]} {cells[1]}", "%d.%m.%y %H:%M").replace(tzinfo=UTC)
        return at, report_json(values)
    return None


def report_json(values: dict[str, float | None]) -> dict[str, object]:
    cover = values.get("cloud_cover_total")
    return {
        "code": report_code(values.get("present_weather"), cover),
        "temp": values.get("dry_bulb_temperature_at_2_meter_above_ground"),
        "dewPoint": values.get("dew_point_temperature_at_2_meter_above_ground"),
        "humidity": values.get("relative_humidity"),
        "windDirection": values.get("mean_wind_direction_during_last_10 min_at_10_meters_above_ground"),
        "windSpeed": values.get("mean_wind_speed_during last_10_min_at_10_meters_above_ground"),
        "gusts": values.get("maximum_wind_speed_last_hour"),
        "visibility": values.get("horizontal_visibility"),
        "pressure": values.get("pressure_reduced_to_mean_sea_level"),
        "cloudCover": cover,
        "cloudBase": values.get("height_of_base_of_lowest_cloud_above_station"),
        "rain": values.get("precipitation_amount_last_hour"),
    }


def is_night_at(at: datetime, forecast: list[Hour]) -> bool:
    """Night as the forecast has it for that hour, else for its first one"""
    for hour in forecast:
        if hour.time == at:
            return hour.is_night
    return forecast[0].is_night if forecast else False


def reporting_nearby(nearest: list[tuple[float, Station]], changed: dict[str, datetime]) -> list[tuple[float, Station]]:
    """Stations within reach whose reports changed recently, nearest first"""
    now = time.time()
    out: list[tuple[float, Station]] = []
    for distance, station in nearest:
        if distance > REPORT_MAX_DISTANCE:
            break
        if station.id in changed and now - changed[station.id].timestamp() < REPORT_MAX_AGE:
            out.append((distance, station))
    return out


def load_current(nearest: list[tuple[float, Station]], forecast: list[Hour]) -> dict[str, object] | None:
    """None without a fresh report nearby, or when they can't be loaded: the
    forecast still stands"""
    try:
        changed = parse_reports_listing(fetch(REPORTS_URL).decode("utf-8", errors="replace"))
    except OSError as error:
        print(f"Couldn't list the reports: {error}", file=sys.stderr)
        return None
    for distance, station in reporting_nearby(nearest, changed)[:REPORT_TRIES]:
        try:
            report = parse_report(fetch(REPORT_URL.format(id=station.id)).decode("utf-8", errors="replace"))
        except (OSError, ValueError, IndexError) as error:
            print(f"Couldn't read the report of {station.id}: {error}", file=sys.stderr)
            continue
        if report is None:
            continue
        at, values = report
        if time.time() - at.timestamp() > REPORT_MAX_AGE:
            continue
        current: dict[str, object] = {
            "station": station_info(distance, station),
            "time": int(at.timestamp()),
            "night": is_night_at(at, forecast),
        }
        return current | values
    return None


# Main -------------------------------------------------------------------------


def weather(lat: float, lon: float) -> dict[str, object]:
    nearest = by_distance(load_catalogue(), lat, lon)
    station, issued, forecast = load_forecast(nearest)
    return {
        "forecast": {"station": station, "issued": int(issued.timestamp())},
        "hourly": hourly_json(forecast),
        "daily": daily_json(forecast),
        "current": load_current(nearest, forecast),
    }


def main(args: list[str]) -> int:
    try:
        lat, lon = (float(arg) for arg in args)
    except ValueError:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        print(json.dumps(weather(lat, lon)))
    except Fail as error:
        print(json.dumps({"error": str(error)}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
