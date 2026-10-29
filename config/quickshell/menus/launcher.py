#!/usr/bin/env python3
# pyright: strict
"""Search sources of the launcher (Launcher.qml) that need more than QML:
SSH hosts, unit and currency conversion, file search.

launcher.py
    Runs while the launcher is shown. First prints the SSH hosts:
        {"hosts": [{"host": "server", "detail": "user@server.example.org"}, ...]}
    then answers each query line on stdin, {"id": 7, "q": "10 km in mi"},
    with {"id": 7, "results": [...]} on stdout, each result one of
        {"kind": "convert", "value": "6.21371", "text": "6.21371 mi",
         "detail": "10 km = 6.21371 mi"}
        {"kind": "file", "name": "notes.md", "path": "/home/…/notes.md",
         "dir": "~/Documents", "folder": false}
    Conversions: "<number> <unit> in|to|as|= <unit>", lengths, masses,
    volumes, areas, times, speeds, data, energy, pressure, temperatures
    and currencies (the ECB's daily rates, cached for a day; a query waits
    for them in the background and is answered again once they're there).
    Files: "/<part of a name>" finds files and folders in the home folder
    (fd, without hidden and ignored ones).
"""

import json
import os
import re
import select
import subprocess
import sys
import threading
import time
import urllib.request
import xml.etree.ElementTree as ET
from collections.abc import Iterator
from pathlib import Path

HOME = Path.home()
SSH_CONFIG = HOME / ".ssh/config"
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "quickshell-launcher"
RATES_URL = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"
RATES_MAX_AGE = 12 * 3600  # s; the ECB publishes once a working day
FILE_RESULTS = 30
FILE_TIMEOUT = 2.0  # s

# --- SSH hosts ---------------------------------------------------------------


def ssh_hosts(config: Path = SSH_CONFIG) -> list[dict[str, str]]:
    """The `Host` entries without wildcards, following `Include`, each
    once, with "user@hostname" if set"""
    result: list[dict[str, str]] = []
    names: set[str] = set()
    for h in ssh_entries(config, set()):
        if h["host"] in names:
            continue
        names.add(h["host"])
        target = h.get("hostname", "")
        detail = f"{h['user']}@{target or h['host']}" if "user" in h else target
        result.append({"host": h["host"], "detail": detail})
    return result


def ssh_entries(config: Path, seen: set[Path]) -> list[dict[str, str]]:
    """{"host", "hostname"?, "user"?} for each name of a `Host` line"""
    if config in seen or not config.is_file():
        return []
    seen.add(config)
    hosts: list[dict[str, str]] = []
    current: list[dict[str, str]] = []
    for raw in config.read_text(errors="replace").splitlines():
        line = raw.split("#", 1)[0].strip()
        match = re.match(r"(\S+)\s*=?\s*(.*)", line)
        if not match:
            continue
        key, value = match[1].lower(), match[2].strip()
        if key == "include":
            for pattern in value.split():
                base = Path(pattern).expanduser()
                paths = (
                    sorted(base.parent.glob(base.name)) if base.is_absolute() else sorted(config.parent.glob(pattern))
                )
                for path in paths:
                    hosts += ssh_entries(path, seen)
            current = []
        elif key == "host":
            current = [{"host": h} for h in value.split() if not re.search(r"[*?!]", h)]
            hosts += current
        elif key == "match":
            current = []
        elif key in ("hostname", "user"):
            for host in current:
                host.setdefault(key, value)
    return hosts


# --- Conversion --------------------------------------------------------------

# unit: (dimension, factor to the dimension's base unit)
UNITS: dict[str, tuple[str, float]] = {}


def units(dimension: str, factor: float, *names: str) -> None:
    for name in names:
        UNITS[name] = (dimension, factor)


units("length", 1, "m", "meter", "meters", "metre", "metres")
units("length", 1e3, "km", "kilometer", "kilometers", "kilometre", "kilometres")
units("length", 1e-2, "cm", "centimeter", "centimeters")
units("length", 1e-3, "mm", "millimeter", "millimeters")
units("length", 1e-6, "µm", "um", "micrometer", "micrometers")
units("length", 1609.344, "mi", "mile", "miles")
units("length", 0.9144, "yd", "yard", "yards")
units("length", 0.3048, "ft", "foot", "feet")
units("length", 0.0254, "in", "inch", "inches")
units("length", 1852, "nmi", "nautical mile", "nautical miles")
units("mass", 1, "kg", "kilogram", "kilograms", "kilo", "kilos")
units("mass", 1e-3, "g", "gram", "grams")
units("mass", 1e-6, "mg", "milligram", "milligrams")
units("mass", 1e3, "t", "ton", "tons", "tonne", "tonnes")
units("mass", 0.45359237, "lb", "lbs", "pound", "pounds")
units("mass", 0.028349523125, "oz", "ounce", "ounces")
units("mass", 6.35029318, "st", "stone", "stones")
units("volume", 1, "l", "liter", "liters", "litre", "litres")
units("volume", 1e-3, "ml", "milliliter", "milliliters")
units("volume", 1e-2, "cl", "centiliter", "centiliters")
units("volume", 1e3, "m3", "m³", "cubic meter", "cubic meters")
units("volume", 3.785411784, "gal", "gallon", "gallons")
units("volume", 0.946352946, "qt", "quart", "quarts")
units("volume", 0.473176473, "pt", "pint", "pints")
units("volume", 0.2365882365, "cup", "cups")
units("volume", 0.0295735295625, "floz", "fl oz", "fluid ounce", "fluid ounces")
units("volume", 0.01478676478125, "tbsp", "tablespoon", "tablespoons")
units("volume", 0.00492892159375, "tsp", "teaspoon", "teaspoons")
units("area", 1, "m2", "m²", "square meter", "square meters")
units("area", 1e6, "km2", "km²", "square kilometer", "square kilometers")
units("area", 1e-4, "cm2", "cm²")
units("area", 1e4, "ha", "hectare", "hectares")
units("area", 4046.8564224, "acre", "acres", "ac")
units("area", 0.09290304, "ft2", "ft²", "sq ft", "square foot", "square feet")
units("area", 2589988.110336, "mi2", "mi²", "square mile", "square miles")
units("time", 1, "s", "sec", "second", "seconds")
units("time", 1e-3, "ms", "millisecond", "milliseconds")
units("time", 60, "min", "minute", "minutes")
units("time", 3600, "h", "hr", "hour", "hours")
units("time", 86400, "d", "day", "days")
units("time", 604800, "wk", "week", "weeks")
units("time", 31557600, "y", "yr", "year", "years")  # Julian year
units("speed", 1, "m/s", "mps")
units("speed", 1 / 3.6, "km/h", "kmh", "kph")
units("speed", 0.44704, "mph")
units("speed", 1852 / 3600, "kn", "kt", "knot", "knots")
units("speed", 0.3048, "ft/s")
units("data", 1, "b", "byte", "bytes")
units("data", 1 / 8, "bit", "bits")
for i, prefix in enumerate(["k", "m", "g", "t", "p"], start=1):
    units("data", 1000**i, f"{prefix}b", f"{prefix}byte", f"{prefix}bytes")
    units("data", 1024**i, f"{prefix}ib")
    units("data", 1000**i / 8, f"{prefix}bit", f"{prefix}bits")
units("energy", 1, "j", "joule", "joules")
units("energy", 1e3, "kj", "kilojoule", "kilojoules")
units("energy", 4.184, "cal", "calorie", "calories")
units("energy", 4184, "kcal", "kilocalorie", "kilocalories")
units("energy", 3600, "wh")
units("energy", 3.6e6, "kwh")
units("pressure", 1, "pa", "pascal")
units("pressure", 100, "hpa", "mbar")
units("pressure", 1e3, "kpa")
units("pressure", 1e5, "bar")
units("pressure", 6894.757293168, "psi")
units("pressure", 101325, "atm")
units("pressure", 133.322387415, "mmhg")

TEMPERATURES = {
    "c": "C", "°c": "C", "celsius": "C",
    "f": "F", "°f": "F", "fahrenheit": "F",
    "k": "K", "kelvin": "K",
}  # fmt: skip

CURRENCY_SYMBOLS = {"€": "EUR", "$": "USD", "£": "GBP", "¥": "JPY", "₹": "INR", "₩": "KRW", "₺": "TRY", "₽": "RUB"}
# The ECB's list (and EUR); anything else that looks like a currency is
# still asked for, so new ones work once the ECB has them
CURRENCIES = (
    "EUR USD JPY BGN CZK DKK GBP HUF PLN RON SEK CHF ISK NOK TRY AUD BRL CAD CNY HKD IDR ILS INR KRW MXN MYR NZD PHP "
    "SGD THB ZAR"
).split()

# Units as shown in results, where that isn't their first name in lower case
DISPLAY = {"m3": "m³", "m2": "m²", "km2": "km²", "cm2": "cm²", "ft2": "ft²", "mi2": "mi²", "um": "µm", "b": "B"}
DISPLAY.update({"kj": "kJ", "j": "J", "wh": "Wh", "kwh": "kWh", "pa": "Pa", "hpa": "hPa", "kpa": "kPa", "mmhg": "mmHg"})
for p in "kmgtp":
    prefix = "k" if p == "k" else p.upper()  # kB, MB, GB, …
    DISPLAY.update({f"{p}b": f"{prefix}B", f"{p}ib": f"{p.upper()}iB", f"{p}bit": f"{prefix}bit"})

NUMBER = r"[-+]?(?:\d+(?:[.,]\d*)?|[.,]\d+)(?:e[-+]?\d+)?"
QUERY = re.compile(rf"^\s*({NUMBER})\s*(.+?)\s+(?:in|to|as|=|->|→)\s+(.+?)\s*$", re.IGNORECASE)


def short_name(unit: str) -> str:
    """The canonical short name of a unit: the first alias registered"""
    dimension, factor = UNITS[unit]
    for name, value in UNITS.items():
        if value == (dimension, factor):
            return DISPLAY.get(name, name)
    return unit


def currency(text: str) -> str | None:
    code = CURRENCY_SYMBOLS.get(text.strip()) or text.strip().upper()
    return code if re.fullmatch(r"[A-Z]{3}", code) else None


def number(value: float, digits: int = 6) -> str:
    """6 significant digits without trailing zeros, no exponent for
    everyday sizes"""
    if value == 0:
        return "0"
    if 1e-6 <= abs(value) < 1e15:
        text = f"{value:.{max(0, digits - 1 - int(f'{abs(value):e}'.split('e')[1]))}f}"
        return text.rstrip("0").rstrip(".") if "." in text else text
    return f"{value:.{digits - 1}e}"


def temperature(value: float, source: str, target: str) -> float:
    kelvin = {"C": value + 273.15, "F": (value - 32) * 5 / 9 + 273.15, "K": value}[source]
    return {"C": kelvin - 273.15, "F": (kelvin - 273.15) * 9 / 5 + 32, "K": kelvin}[target]


class Rates:
    """The ECB's rates: EUR → currency, and the day they're from"""

    def __init__(self, rates: dict[str, float], date: str) -> None:
        self.rates = rates
        self.date = date


def convert(query: str, rates: Rates | None) -> dict[str, str | bool] | None:
    """The conversion a query asks for, or None. Units are case-blind, so
    "MB" and "mb" are megabytes; bits are "Mbit". `rates` is None while they
    aren't loaded, which then raises RatesMissing for a currency query."""
    match = QUERY.match(query)
    if not match:
        return None
    value = float(match[1].replace(",", "."))
    source, target = match[2].strip(), match[3].strip()
    s, t = source.lower(), target.lower()
    if s in TEMPERATURES and t in TEMPERATURES:
        a, b = TEMPERATURES[s], TEMPERATURES[t]
        result = temperature(value, a, b)
        unit_from, unit_to = f"°{a}" if a != "K" else "K", f"°{b}" if b != "K" else "K"
    elif s in UNITS and t in UNITS and UNITS[s][0] == UNITS[t][0]:
        result = value * UNITS[s][1] / UNITS[t][1]
        unit_from, unit_to = short_name(s), short_name(t)
    else:
        a, b = currency(source), currency(target)
        if not a or not b:
            return None
        if rates is None:
            raise RatesMissing
        if a not in rates.rates or b not in rates.rates:
            return None
        result = value / rates.rates[a] * rates.rates[b]
        text = f"{result:,.2f}".replace(",", " ")
        return {
            "kind": "convert",
            "value": f"{result:.2f}",
            "text": f"{text} {b}",
            "detail": f"{number(value)} {a} = {text} {b} · ECB rate of {rates.date}",
        }
    text = number(result)
    return {
        "kind": "convert",
        "value": text,
        "text": f"{text} {unit_to}",
        "detail": f"{number(value)} {unit_from} = {text} {unit_to}",
    }


class RatesMissing(Exception):
    pass


def parse_rates(xml: str) -> Rates:
    """The ECB's daily XML, <Cube time="…"><Cube currency="USD" rate="…"/>"""
    rates: dict[str, float] = {"EUR": 1.0}
    date = "?"
    for cube in ET.fromstring(xml).iter():
        date = cube.get("time") or date
        code, rate = cube.get("currency"), cube.get("rate")
        if code and rate:
            rates[code] = float(rate)
    return Rates(rates, date)


# --- Files -------------------------------------------------------------------


def rank_files(paths: list[str], query: str) -> list[str]:
    """Names that start with the text first, then shorter paths"""
    q = query.lower()

    def key(path: str) -> tuple[int, int, int, str]:
        name = Path(path).name.lower()
        return (0 if name == q else 1 if name.startswith(q) else 2, path.count("/"), len(path), path)

    return sorted(paths, key=key)


def short_dir(path: Path) -> str:
    try:
        return "~/" + str(path.parent.relative_to(HOME)) if path.parent != HOME else "~"
    except ValueError:
        return str(path.parent)


def find_files(query: str) -> list[dict[str, str | bool]]:
    # Fixed strings: the text isn't a regex
    command = ["fd", "--ignore-case", "--fixed-strings", "--max-results", "200", "--absolute-path"]
    command += ["--", query, str(HOME)]
    try:
        out = subprocess.run(command, capture_output=True, text=True, timeout=FILE_TIMEOUT, check=False).stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []
    paths = rank_files([p.rstrip("/") for p in out.splitlines() if p], query)[:FILE_RESULTS]
    return [
        {"kind": "file", "name": Path(p).name, "path": p, "dir": short_dir(Path(p)), "folder": Path(p).is_dir()}
        for p in paths
    ]


# --- Serving -----------------------------------------------------------------


class Server:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.answering = threading.Lock()
        self.rates: Rates | None = None
        self.loading = False
        self.last: dict[str, object] = {}

    def send(self, message: dict[str, object]) -> None:
        with self.lock:
            sys.stdout.write(json.dumps(message) + "\n")
            sys.stdout.flush()

    def load_rates(self) -> None:
        """From the cache, or the ECB once it's too old; then the last query
        again"""
        cache = CACHE / "ecb.xml"
        try:
            if not cache.is_file() or time.time() - cache.stat().st_mtime > RATES_MAX_AGE:
                with urllib.request.urlopen(RATES_URL, timeout=10) as response:
                    data: bytes = response.read()
                CACHE.mkdir(parents=True, exist_ok=True)
                cache.write_bytes(data)
            self.rates = parse_rates(cache.read_text())
        except (OSError, ET.ParseError):
            # Offline: an old cache is better than nothing
            try:
                self.rates = parse_rates(cache.read_text())
            except (OSError, ET.ParseError):
                self.rates = Rates({}, "")
        self.loading = False
        if self.last:
            self.answer(self.last)

    def answer(self, request: dict[str, object]) -> None:
        with self.answering:
            self.respond(request)

    def respond(self, request: dict[str, object]) -> None:
        self.last = request
        query = str(request.get("q", ""))
        results: list[dict[str, str | bool]] = []
        if query.startswith("/"):
            if len(query.strip()) > 2:
                results = find_files(query[1:].strip())
        else:
            try:
                result = convert(query, self.rates)
                if result:
                    results.append(result)
            except RatesMissing:
                if not self.loading:
                    self.loading = True
                    threading.Thread(target=self.load_rates, daemon=True).start()
        self.send({"id": request.get("id"), "results": results})

    def run(self) -> None:
        self.send({"hosts": ssh_hosts()})
        for line in latest_lines(sys.stdin.fileno()):
            try:
                request = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(request, dict):
                self.answer(request)  # pyright: ignore[reportUnknownArgumentType]


def latest_lines(fd: int) -> Iterator[str]:
    """The lines from `fd`, skipping those that a newer one has already
    followed: while typing, a file search for an older text is wasted"""
    pending = b""
    while True:
        chunk = os.read(fd, 65536)
        if not chunk:
            return
        pending += chunk
        while select.select([fd], [], [], 0)[0]:
            more = os.read(fd, 65536)
            if not more:
                break
            pending += more
        *lines, pending = pending.split(b"\n")
        if lines:
            yield lines[-1].decode(errors="replace")


def main(args: list[str]) -> None:
    if args:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    Server().run()


if __name__ == "__main__":
    main(sys.argv[1:])
