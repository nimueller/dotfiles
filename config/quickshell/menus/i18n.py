# pyright: strict
"""The helpers' messages in the shell's language, as I18n.qml decides it:
"language" in the "-- settings:" line of local.lua (Machine Settings), "en",
"de" or "system", else the system's (LC_ALL, LC_MESSAGES, LANG).

  from i18n import tr
  tr("Couldn't write %1", name)

German comes from translations/de.json, which the QML side shares; a text
without a translation stays English."""

import datetime as dt
import json
import os
import re
from functools import cache
from pathlib import Path
from typing import cast

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
MACHINE = CONFIG / "hypr/local.lua"  # Machine Settings' "-- settings:" line (settings.qml)
GERMAN = Path(__file__).resolve().parent / "translations/de.json"
LANGUAGES = ("en", "de")
LOCALE_VARIABLES = ("LC_ALL", "LC_MESSAGES", "LANG")
PLACEHOLDER = re.compile(r"%(\d)")
# strftime's names follow the C locale, so they're translated here instead
DAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
MONTHS = (
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
)


def system_language(environ: dict[str, str]) -> str:
    """The language of the first locale variable that's set, "en" if it's neither"""
    locale = next((environ[v] for v in LOCALE_VARIABLES if environ.get(v)), "")
    code = locale[:2]
    return code if code in LANGUAGES else "en"


def chosen_language(lua: str) -> str:
    """The language picked in Machine Settings, "system" without one"""
    line = re.search(r"^-- settings: (.*)$", lua, re.MULTILINE)
    if line is None:
        return "system"
    try:
        settings: object = json.loads(line[1])
    except ValueError:
        return "system"
    if not isinstance(settings, dict):
        return "system"
    chosen = cast(dict[str, object], settings).get("language")
    return chosen if isinstance(chosen, str) else "system"


def read_chosen_language() -> str:
    try:
        return chosen_language(MACHINE.read_text())
    except OSError:
        return "system"


def language() -> str:
    """Read for every text, so a helper that keeps running follows a change"""
    chosen = read_chosen_language()
    return chosen if chosen in LANGUAGES else system_language(dict(os.environ))


@cache
def german() -> dict[str, str]:
    try:
        return json.loads(GERMAN.read_text())
    except (OSError, ValueError):
        # English then, as without a translation
        return {}


def fill(text: str, args: tuple[object, ...]) -> str:
    """%1, %2, … replaced by the arguments; one that's missing stays"""

    def argument(match: re.Match[str]) -> str:
        index = int(match[1]) - 1
        return str(args[index]) if index < len(args) else match[0]

    return PLACEHOLDER.sub(argument, text)


def tr(text: str, *args: object) -> str:
    strings = german() if language() == "de" else {}
    return fill(strings.get(text, text), args)


def long_date(date: dt.date) -> str:
    """Monday, 2 March; Montag, 2. März"""
    day = tr(DAYS[date.weekday()])
    month = tr(MONTHS[date.month - 1])
    return tr("%1, %2 %3", day, date.day, month)
