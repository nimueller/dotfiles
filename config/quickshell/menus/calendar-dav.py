#!/usr/bin/env quickshell-calendar-python
# pyright: strict
"""Calendar backend for the quickshell calendar menu: Nextcloud (CalDAV) and
read-only ICS subscriptions.

  calendar-dav.py login URL USER       app password on stdin: check it, store it
                                       in the keyring, print the calendars
  calendar-dav.py calendars URL USER   print the Nextcloud calendars
  calendar-dav.py logout URL USER      forget the stored password
  calendar-dav.py events               stdin {start, end, nextcloud: {url, user,
                                       calendars: [href]}, ics: [{id, url}]}:
                                       events in [start, end), recurrences
                                       expanded, errors per calendar
  calendar-dav.py create URL USER      stdin {calendar, title, location, allDay,
                                       start, end, alarms}: new event on Nextcloud
  calendar-dav.py update URL USER      stdin {href, etag, title, location, allDay,
                                       start, end, alarms}: change a
                                       (non-recurring) event, keeping
                                       everything else in it
  calendar-dav.py delete URL USER      stdin {href, etag}: delete an event
  calendar-dav.py remind               desktop notifications for reminders that
                                       are due (run every minute by a systemd
                                       user timer, see home-manager/desktop)

`alarms` are reminders as minutes before the start (VALARMs with a
start-related trigger); they are stored in the event, so Nextcloud and its
clients show them too. Events carry their own `color` if they have one.

URL is the Nextcloud address (https://cloud.example.com) or a DAV root. The
password lives in the Secret Service keyring (secret-tool); it is never
written to a file or passed on a command line. Output is JSON on stdout;
on failure {"error": "..."} and exit status 1.

Runs on quickshell-calendar-python (pkgs/default.nix), a Python with the
icalendar and recurring-ical-events libraries.
"""

import base64
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from collections.abc import Mapping
from email.message import Message
from pathlib import Path
from typing import Any, NotRequired, Protocol, Self, TypedDict, cast
from zoneinfo import ZoneInfo

import icalendar

# No type information, used in occurrences() only
import recurring_ical_events  # pyright: ignore[reportMissingTypeStubs]

NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav", "a": "http://apple.com/ns/ical/"}
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "quickshell-calendar"
ICS_CACHE = CACHE / "ics"
ICS_MAX_AGE = 6 * 3600
REMINDER_STATE = CACHE / "reminders.json"
SETTINGS = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state") / "quickshell-calendar.json"
USER_AGENT = "quickshell-calendar/1.0"
HTTP_TIMEOUT = 20
DEFAULT_COLOR = "#8aadf4"
NO_TITLE = "(No title)"
WRITE_PRIVILEGES = {"write", "write-content", "all", "bind"}
ICAL_CONTENT_TYPE = "text/calendar; charset=utf-8"
XML_CONTENT_TYPE = "application/xml; charset=utf-8"
PRODID = "-//quickshell//calendar menu//EN"
KEYRING_SERVICE = "quickshell-calendar"
KEYRING_LABEL = "Nextcloud calendar (quickshell)"
REFETCH_AFTER = 600  # s
CATCH_UP = 600  # s: how far back reminders are caught up on after a pause
PAUSE = 3600  # s: longer between two runs counts as a pause
FIRST_RUN = 60  # s: how far back the first run looks
REMIND_DAYS_BEFORE = 1
REMIND_DAYS_AFTER = 4
FIRED_KEEP_DAYS = 2
COMMANDS_WITH_ACCOUNT = ("login", "calendars", "logout", "create", "update", "delete")
USAGE = "usage: calendar-dav.py login|calendars|logout|create|update|delete URL USER, or events, remind"

Auth = tuple[str, str]  # (user, app password)


class Fail(Exception):
    pass


class Calendar(TypedDict):
    href: str
    name: str
    color: str
    writable: bool


class Source(TypedDict):
    """Where an event comes from: its calendar, and for Nextcloud the event
    object and its ETag."""

    calendar: str
    href: NotRequired[str]
    etag: NotRequired[str]


class Event(Source):
    uid: str
    title: str
    location: str
    allDay: bool
    start: str
    end: str
    recurring: bool
    color: str
    alarms: list[int]


class EventForm(TypedDict):
    """The menu's event form: a new event names its calendar, a changed one
    its href."""

    title: str
    start: str
    end: str
    calendar: NotRequired[str]
    href: NotRequired[str]
    etag: NotRequired[str]
    location: NotRequired[str]
    allDay: NotRequired[bool]
    alarms: NotRequired[list[int]]


class DeleteForm(TypedDict):
    href: str
    etag: NotRequired[str]


class Component(Protocol):
    """The part of icalendar's components this script uses. icalendar's
    own annotations leave much of it unknown, so its objects are cast to
    this where they are made (new_component, parse_calendar)."""

    subcomponents: list["Component"]

    def add(self, name: str, value: object) -> None: ...

    def get(self, name: str, default: object = None) -> Any: ...

    def pop(self, name: str, default: object = None) -> Any: ...

    def __getitem__(self, name: str) -> Any: ...

    def walk(self, name: str) -> list["Component"]: ...

    def add_component(self, component: "Component") -> None: ...

    def add_missing_timezones(self) -> Self: ...

    def to_ical(self) -> bytes: ...


def new_component(kind: type[icalendar.Component]) -> Component:
    return cast(Component, kind())


def parse_calendar(data: str | bytes) -> Component:
    """Raises ValueError for data that isn't iCalendar."""
    return cast(Component, icalendar.Calendar.from_ical(data))


class NextcloudSpec(TypedDict):
    url: str
    user: str
    calendars: list[str]


class IcsSpec(TypedDict):
    id: str
    url: str


class EventsSpec(TypedDict):
    start: str
    end: str
    nextcloud: NotRequired[NextcloudSpec | None]
    ics: NotRequired[list[IcsSpec]]


class EventsResult(TypedDict):
    events: list[Event]
    errors: dict[str, str]


# ---------- Nextcloud / CalDAV ----------


def dav_root(url: str) -> str:
    """The DAV root of a Nextcloud address, with a trailing slash."""
    root = url.strip().rstrip("/")
    if not re.match(r"https?://", root):
        root = "https://" + root
    if "/remote.php/dav" not in root and not root.endswith("/dav"):
        root += "/remote.php/dav"
    return root + "/"


def keyring_attributes(url: str, user: str) -> list[str]:
    return ["service", KEYRING_SERVICE, "url", dav_root(url), "user", user]


def stored_password(url: str, user: str) -> str:
    lookup = subprocess.run(
        ["secret-tool", "lookup", *keyring_attributes(url, user)],
        capture_output=True,
        text=True,
        check=False,
    )
    if lookup.returncode != 0 or not lookup.stdout:
        raise Fail("No app password stored. Sign in again in the settings.")
    return lookup.stdout.rstrip("\n")


def keyring_locked() -> bool:
    """Whether the `login` keyring is locked; a lookup would then open its
    password prompt. False when there is no Secret Service to ask."""
    result = subprocess.run(
        [
            "busctl",
            "--user",
            "get-property",
            "org.freedesktop.secrets",
            "/org/freedesktop/secrets/collection/login",
            "org.freedesktop.Secret.Collection",
            "Locked",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip() == "b true"


def basic_auth(auth: Auth) -> str:
    user, password = auth
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    return f"Basic {token}"


def http_error_message(code: int, reason: str) -> str:
    if code == 401:
        return "Wrong username or app password"
    if code == 412:
        return "The event changed on the server. Reload and try again."
    return f"Server answered {code} {reason}"


def http(
    method: str,
    url: str,
    auth: Auth | None = None,
    body: bytes = b"",
    headers: Mapping[str, str] | None = None,
) -> tuple[int, Message, bytes]:
    """(status, response headers, body); raises Fail for errors."""
    request = urllib.request.Request(url, data=body or None, method=method)
    request.add_header("User-Agent", USER_AGENT)
    if auth is not None:
        request.add_header("Authorization", basic_auth(auth))
    for name, value in (headers or {}).items():
        request.add_header(name, value)
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as error:
        raise Fail(http_error_message(error.code, error.reason)) from None
    except urllib.error.URLError as error:
        raise Fail(f"Can't reach the server ({error.reason})") from None
    except TimeoutError:
        raise Fail("The server took too long to answer") from None


def dav(method: str, url: str, auth: Auth, body: str, depth: int) -> ET.Element:
    headers = {"Content-Type": XML_CONTENT_TYPE, "Depth": str(depth)}
    _status, _headers, data = http(method, url, auth, body.encode(), headers)
    try:
        return ET.fromstring(data)
    except ET.ParseError:
        raise Fail("The server's answer isn't CalDAV. Check the address.") from None


def is_success(propstat: ET.Element) -> bool:
    """Whether a propstat's status line ("HTTP/1.1 200 OK") says 200."""
    status = propstat.findtext("d:status", "", NS)
    return " 200 " in status + " "


def found(response: ET.Element, path: str) -> ET.Element | None:
    """Element at `path` inside a response's successful propstat, or None."""
    for propstat in response.findall("d:propstat", NS):
        if not is_success(propstat):
            continue
        element = propstat.find(f"d:prop/{path}", NS)
        if element is not None:
            return element
    return None


def found_text(response: ET.Element, path: str) -> str | None:
    element = found(response, path)
    if element is None:
        return None
    return element.text


def propfind(url: str, auth: Auth, properties: str, depth: int = 0) -> ET.Element:
    body = (
        '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" '
        f'xmlns:a="http://apple.com/ns/ical/"><d:prop>{properties}</d:prop></d:propfind>'
    )
    return dav("PROPFIND", url, auth, body, depth)


def follow(base: str, tree: ET.Element, path: str, what: str) -> str:
    """The first href at `path` in the responses, as an absolute URL."""
    for response in tree.findall("d:response", NS):
        href = found_text(response, path)
        if href:
            return urllib.parse.urljoin(base, href.strip())
    raise Fail(f"The server didn't tell the {what}, check the address")


def calendars(url: str, auth: Auth) -> list[Calendar]:
    root = dav_root(url)
    principal_answer = propfind(root, auth, "<d:current-user-principal/>")
    principal = follow(root, principal_answer, "d:current-user-principal/d:href", "user")
    home_answer = propfind(principal, auth, "<c:calendar-home-set/>")
    home = follow(root, home_answer, "c:calendar-home-set/d:href", "calendar home")
    properties = (
        "<d:resourcetype/><d:displayname/><a:calendar-color/>"
        "<c:supported-calendar-component-set/><d:current-user-privilege-set/>"
    )
    return parse_calendars(root, propfind(home, auth, properties, 1))


def has_events(response: ET.Element) -> bool:
    """Whether a calendar takes events; some only take tasks (Deck boards).
    Without a component set it takes everything."""
    components = found(response, "c:supported-calendar-component-set")
    if components is None:
        return True
    names = [component.get("name") for component in components.findall("c:comp", NS)]
    return "VEVENT" in names


def is_writable(response: ET.Element) -> bool:
    """Whether the user may add events. Without a privilege set, assume so."""
    privileges = found(response, "d:current-user-privilege-set")
    if privileges is None:
        return True
    # {DAV:}write -> write
    granted = {element.tag.split("}")[-1] for element in privileges.iter()}
    return bool(granted & WRITE_PRIVILEGES)


def calendar_entry(root: str, response: ET.Element) -> Calendar | None:
    """A response of the calendar home as a calendar, None for anything
    else in it."""
    kind = found(response, "d:resourcetype")
    if kind is None or kind.find("c:calendar", NS) is None:
        return None
    if not has_events(response):
        return None
    href = urllib.parse.urljoin(root, response.findtext("d:href", "", NS))
    last_segment = urllib.parse.unquote(href.rstrip("/").rsplit("/", 1)[-1])
    color = found_text(response, "a:calendar-color") or ""
    return {
        "href": href,
        "name": found_text(response, "d:displayname") or last_segment,
        # #rrggbbaa -> #rrggbb
        "color": color[:7] or DEFAULT_COLOR,
        "writable": is_writable(response),
    }


def parse_calendars(root: str, tree: ET.Element) -> list[Calendar]:
    entries = [calendar_entry(root, response) for response in tree.findall("d:response", NS)]
    return [entry for entry in entries if entry is not None]


def utc_stamp(day: dt.date) -> str:
    """Local midnight of a day, in UTC, as CalDAV's time ranges want it."""
    midnight = dt.datetime.combine(day, dt.time()).astimezone()
    return midnight.astimezone(dt.UTC).strftime("%Y%m%dT%H%M%SZ")


def caldav_events(auth: Auth, start: dt.date, end: dt.date, href: str) -> list[Event]:
    """Events of one Nextcloud calendar. Fetches the event objects that touch
    the range and expands recurrences locally, like the ICS feeds."""
    body = (
        '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        "<d:prop><d:getetag/><c:calendar-data/>"
        '</d:prop><c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">'
        f'<c:time-range start="{utc_stamp(start)}" end="{utc_stamp(end)}"/></c:comp-filter></c:comp-filter>'
        "</c:filter></c:calendar-query>"
    )
    found_events: list[Event] = []
    for response in dav("REPORT", href, auth, body, 1).findall("d:response", NS):
        data = found_text(response, "c:calendar-data")
        if not data:
            continue
        source: Source = {
            "calendar": href,
            "href": urllib.parse.urljoin(href, response.findtext("d:href", "", NS)),
            "etag": found_text(response, "d:getetag") or "",
        }
        found_events += expand(data, start, end, source)
    return found_events


# ---------- Writing events ----------


def apply_fields(event: Component, form: EventForm) -> None:
    """Title, place and times from the menu's form onto a VEVENT; times in
    the local zone, all-day `end` is the last day (inclusive)."""
    for key in ("summary", "location", "dtstart", "dtend", "duration"):
        event.pop(key, None)
    title = form["title"]
    event.add("summary", title)
    location = form.get("location")
    if location:
        event.add("location", location)
    if form.get("allDay"):
        first_day = dt.date.fromisoformat(form["start"][:10])
        last_day = dt.date.fromisoformat(form["end"][:10])
        event.add("dtstart", first_day)
        # DTEND is exclusive
        event.add("dtend", max(last_day, first_day) + dt.timedelta(days=1))
    else:
        zone = local_zone()
        start = dt.datetime.fromisoformat(form["start"]).replace(tzinfo=zone)
        end = dt.datetime.fromisoformat(form["end"]).replace(tzinfo=zone)
        event.add("dtstart", start)
        event.add("dtend", max(end, start))
    if "alarms" in form:
        set_alarms(event, form["alarms"], title)


def start_alarms(event: Component) -> list[tuple[Component, int]]:
    """VALARMs of a VEVENT whose trigger is relative to the start, with
    their minutes before it."""
    alarms: list[tuple[Component, int]] = []
    for alarm in event.walk("VALARM"):
        trigger = alarm.get("trigger")
        if trigger is None or not isinstance(trigger.dt, dt.timedelta):
            continue
        related = str(trigger.params.get("RELATED", "START")).upper()
        if related != "START":
            continue
        minutes_before = round(-trigger.dt.total_seconds() / 60)
        alarms.append((alarm, minutes_before))
    return alarms


def set_alarms(event: Component, minutes: list[int], title: str) -> None:
    """Replace the start-related reminders; others (absolute times, e-mail
    alarms relative to the end, ...) stay as they are."""
    for alarm, _minutes in start_alarms(event):
        event.subcomponents.remove(alarm)
    for minutes_before in sorted({int(m) for m in minutes}):
        alarm = new_component(icalendar.Alarm)
        alarm.add("action", "DISPLAY")
        alarm.add("description", title)
        alarm.add("trigger", dt.timedelta(minutes=-minutes_before))
        event.add_component(alarm)


def check_account(url: str, href: str, what: str) -> None:
    if not href.startswith(dav_root(url)):
        raise Fail(f"That {what} doesn't belong to this account")


def create(url: str, auth: Auth, form: EventForm) -> dict[str, str]:
    """PUT a new event into a Nextcloud calendar."""
    calendar_href = form.get("calendar")
    if calendar_href is None:
        raise Fail("The new event has no calendar")
    check_account(url, calendar_href, "calendar")
    calendar = new_component(icalendar.Calendar)
    calendar.add("prodid", PRODID)
    calendar.add("version", "2.0")
    event = new_component(icalendar.Event)
    uid = str(uuid.uuid4())
    event.add("uid", uid)
    event.add("dtstamp", dt.datetime.now(dt.UTC))
    apply_fields(event, form)
    calendar.add_component(event)
    calendar.add_missing_timezones()
    href = calendar_href.rstrip("/") + f"/{uid}.ics"
    # If-None-Match: never overwrite an existing event
    headers = {"Content-Type": ICAL_CONTENT_TYPE, "If-None-Match": "*"}
    http("PUT", href, auth, calendar.to_ical(), headers)
    return {"href": href}


def read_single_event(data: bytes) -> tuple[Component, Component]:
    """The calendar object and its only VEVENT; recurring events (several
    VEVENTs or an RRULE) are left to Nextcloud."""
    try:
        calendar = parse_calendar(data)
    except ValueError as error:
        raise Fail(f"Couldn't read the event ({error})") from None
    events = calendar.walk("VEVENT")
    if len(events) != 1 or events[0].get("rrule") is not None:
        raise Fail("Recurring events can only be changed in Nextcloud")
    return calendar, events[0]


def mark_modified(event: Component) -> None:
    for key in ("dtstamp", "last-modified"):
        event.pop(key, None)
    now = dt.datetime.now(dt.UTC)
    event.add("dtstamp", now)
    event.add("last-modified", now)
    sequence = int(event.pop("sequence", 0))
    event.add("sequence", sequence + 1)


def update(url: str, auth: Auth, form: EventForm) -> dict[str, str]:
    """Change title, place and times of an existing event. Everything else in
    it (description, reminders, attendees, ...) stays; the If-Match ETag makes
    the server refuse if it was changed elsewhere meanwhile."""
    href = form.get("href")
    if href is None:
        raise Fail("The event to change has no href")
    check_account(url, href, "event")
    _status, headers, data = http("GET", href, auth)
    calendar, event = read_single_event(data)
    server_etag = headers.get("ETag", "")
    etag = form.get("etag") or server_etag
    if server_etag and etag and server_etag != etag:
        raise Fail("The event changed on the server. Reload and try again.")
    apply_fields(event, form)
    mark_modified(event)
    calendar.add_missing_timezones()
    put_headers = {"Content-Type": ICAL_CONTENT_TYPE}
    if etag:
        put_headers["If-Match"] = etag
    http("PUT", href, auth, calendar.to_ical(), put_headers)
    return {"href": href}


def delete(url: str, auth: Auth, form: DeleteForm) -> dict[str, str]:
    href = form["href"]
    check_account(url, href, "event")
    etag = form.get("etag")
    headers = {"If-Match": etag} if etag else {}
    http("DELETE", href, auth, headers=headers)
    return {}


def local_zone() -> dt.tzinfo | None:
    """The system's time zone by its name (so events keep its rules), else
    the current offset."""
    try:
        name = os.path.realpath("/etc/localtime").split("zoneinfo/", 1)[1]
        return ZoneInfo(name)
    except (IndexError, KeyError, ValueError):
        return dt.datetime.now().astimezone().tzinfo


# ---------- ICS subscriptions ----------


def ics_text(url: str) -> str:
    """The feed, cached for ICS_MAX_AGE; a stale copy if it can't be fetched."""
    url = re.sub(r"^webcal://", "https://", url.strip(), flags=re.IGNORECASE)
    ICS_CACHE.mkdir(parents=True, exist_ok=True)
    cached = ICS_CACHE / (hashlib.sha1(url.encode()).hexdigest() + ".ics")
    is_fresh = cached.exists() and time.time() - cached.stat().st_mtime < ICS_MAX_AGE
    if is_fresh:
        return cached.read_text(errors="replace")
    try:
        _status, _headers, data = http("GET", url)
    except Fail:
        if cached.exists():
            return cached.read_text(errors="replace")
        raise
    text = data.decode("utf-8", errors="replace")
    if "BEGIN:VCALENDAR" not in text:
        raise Fail("That address isn't an ICS calendar")
    cached.write_text(text)
    return text


# ---------- Events ----------


def as_local(value: dt.date, all_day: bool) -> str:
    """An event time for the menu: an all-day date as it is, a floating
    time in the local zone."""
    if all_day:
        return value.isoformat()
    if isinstance(value, dt.datetime) and value.tzinfo is None:
        return value.astimezone().isoformat()
    return value.isoformat()


def recurring_uids(calendar: Component) -> set[str]:
    """The UIDs of recurring events. Expanded occurrences all carry a
    RECURRENCE-ID, so this looks at the source."""
    uids: set[str] = set()
    for event in calendar.walk("VEVENT"):
        is_recurring = any(event.get(key) is not None for key in ("rrule", "rdate", "recurrence-id"))
        if is_recurring:
            uids.add(str(event.get("uid")))
    return uids


def event_end(event: Component, begin: dt.date, all_day: bool) -> dt.date:
    """DTEND, else DTSTART plus DURATION, else a day (all-day) or nothing."""
    if event.get("dtend") is not None:
        return event["dtend"].dt
    if event.get("duration") is not None:
        return begin + event["duration"].dt
    if all_day:
        return begin + dt.timedelta(days=1)
    return begin


def occurrences(calendar: Component, start: dt.date, end: dt.date) -> list[Component]:
    # recurring_ical_events has no type information
    query = cast(Any, recurring_ical_events).of(calendar)
    return cast(list[Component], query.between(start, end))


def event_entry(event: Component, source: Source, recurring: set[str]) -> Event:
    begin: dt.date = event["dtstart"].dt
    all_day = not isinstance(begin, dt.datetime)
    uid = str(event.get("uid", ""))
    return {
        **source,
        "uid": uid,
        "title": str(event.get("summary", "")) or NO_TITLE,
        "location": str(event.get("location", "")),
        "allDay": all_day,
        "start": as_local(begin, all_day),
        "end": as_local(event_end(event, begin, all_day), all_day),
        "recurring": uid in recurring,
        "color": str(event.get("color", "")),
        "alarms": sorted(minutes for _alarm, minutes in start_alarms(event)),
    }


def expand(text: str, start: dt.date, end: dt.date, source: Source) -> list[Event]:
    """The events of calendar data in [start, end), recurrences expanded,
    cancelled ones left out."""
    try:
        calendar = parse_calendar(text)
    except ValueError as error:
        raise Fail(f"Couldn't read the calendar data ({error})") from None
    recurring = recurring_uids(calendar)
    entries: list[Event] = []
    for event in occurrences(calendar, start, end):
        is_cancelled = str(event.get("status", "")).upper() == "CANCELLED"
        if not is_cancelled:
            entries.append(event_entry(event, source, recurring))
    return entries


def nextcloud_events(
    spec: NextcloudSpec,
    start: dt.date,
    end: dt.date,
    errors: dict[str, str],
) -> list[Event]:
    """Events of the enabled Nextcloud calendars; errors by calendar, or
    under "nextcloud" when there is no password."""
    try:
        auth = (spec["user"], stored_password(spec["url"], spec["user"]))
    except Fail as error:
        errors["nextcloud"] = str(error)
        return []
    found_events: list[Event] = []
    for href in spec["calendars"]:
        try:
            found_events += caldav_events(auth, start, end, href)
        except Fail as error:
            errors[href] = str(error)
            # A wrong password fails for every calendar alike
            if "password" in str(error):
                break
    return found_events


def events(spec: EventsSpec) -> EventsResult:
    start = dt.date.fromisoformat(spec["start"])
    end = dt.date.fromisoformat(spec["end"])
    found_events: list[Event] = []
    errors: dict[str, str] = {}
    nextcloud = spec.get("nextcloud")
    if nextcloud and nextcloud.get("calendars"):
        found_events += nextcloud_events(nextcloud, start, end, errors)
    for feed in spec.get("ics", []):
        try:
            found_events += expand(ics_text(feed["url"]), start, end, {"calendar": feed["id"]})
        except Fail as error:
            errors[feed["id"]] = str(error)
    return {"events": found_events, "errors": errors}


# ---------- Reminders ----------


def sources(settings: dict[str, Any]) -> dict[str, Any]:
    """The events spec for the calendars enabled in the menu's settings."""
    account = settings.get("nextcloud")
    nextcloud: NextcloudSpec | None = None
    if account:
        enabled = [calendar["href"] for calendar in account.get("calendars", []) if calendar.get("enabled")]
        nextcloud = {"url": account["url"], "user": account["user"], "calendars": enabled}
    ics = [{"id": feed["id"], "url": feed["url"]} for feed in settings.get("ics", []) if feed.get("enabled")]
    return {"nextcloud": nextcloud, "ics": ics}


def event_start(event: Event) -> dt.datetime:
    """When an event starts; an all-day one at local midnight."""
    if event["allDay"]:
        midnight = dt.datetime.combine(dt.date.fromisoformat(event["start"]), dt.time())
        return midnight.astimezone()
    return dt.datetime.fromisoformat(event["start"])


def read_json(path: Path) -> dict[str, Any] | None:
    """A JSON file's object, None when it doesn't exist (yet) or is broken."""
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def fetch_reminder_events(settings: dict[str, Any], state: dict[str, Any], now: float) -> None:
    """Refreshes the events with reminders of the next days in the state,
    at most every REFETCH_AFTER seconds."""
    if now - state.get("fetched", 0) <= REFETCH_AFTER:
        return
    # Not while the keyring is locked: the session logs in by itself and the
    # lock screen unlocks the keyring, so the app password's lookup would
    # open a prompt behind the lock screen. The fetch waits for the next run.
    if settings.get("nextcloud") and keyring_locked():
        return
    today = dt.date.today()
    spec = cast(
        EventsSpec,
        {
            **sources(settings),
            "start": str(today - dt.timedelta(days=REMIND_DAYS_BEFORE)),
            "end": str(today + dt.timedelta(days=REMIND_DAYS_AFTER)),
        },
    )
    result = events(spec)
    state["events"] = [event for event in result["events"] if event.get("alarms")]
    state["fetched"] = now


def last_run(state: dict[str, Any], now: float) -> float:
    """Since when reminders are due. After a pause (suspend, boot) only the
    last CATCH_UP seconds are caught up on."""
    last: float = state.get("last", now - FIRST_RUN)
    if now - last > PAUSE:
        return now - CATCH_UP
    return last


def reminder_key(event: Event, minutes: int) -> str:
    return f"{event.get('uid')}|{event['start']}|{minutes}"


def is_recent_key(key: str) -> bool:
    """Whether a fired reminder's event started recently enough to keep
    its key, so it doesn't fire again."""
    # From the right: a UID may hold "|" itself
    _uid, start, _minutes = key.rsplit("|", 2)
    oldest = str(dt.date.today() - dt.timedelta(days=FIRED_KEEP_DAYS))
    return start >= oldest


def fire_due(state: dict[str, Any], since: float, now: float) -> None:
    """Notifies about the reminders due in (since, now] that didn't fire yet."""
    fired: set[str] = set(state.get("fired", []))
    reminder_events: list[Event] = state.get("events", [])
    for event in reminder_events:
        start = event_start(event)
        for minutes in event["alarms"]:
            due = start.timestamp() - minutes * 60
            key = reminder_key(event, minutes)
            if since < due <= now and key not in fired:
                fired.add(key)
                notify(event, start, minutes)
    state["fired"] = [key for key in fired if is_recent_key(key)]


def remind() -> dict[str, Any]:
    """Notify about reminders that came due since the last run."""
    settings = read_json(SETTINGS)
    # No settings: the calendar menu was never set up
    if settings is None or settings.get("reminders") is False:
        return {}
    state = read_json(REMINDER_STATE) or {}
    now = time.time()
    fetch_reminder_events(settings, state, now)
    fire_due(state, last_run(state, now), now)
    state["last"] = now
    CACHE.mkdir(parents=True, exist_ok=True)
    REMINDER_STATE.write_text(json.dumps(state))
    return {}


def time_until(start: dt.datetime, minutes: int) -> str:
    if minutes <= 0:
        return "now"
    if minutes < 60:
        return f"in {minutes} min"
    return f"at {start:%H:%M}"


def reminder_text(event: Event, start: dt.datetime, minutes: int) -> str:
    """The notification's body: when, and where."""
    if event["allDay"]:
        when = "today" if start.date() == dt.date.today() else start.strftime("%A, %-d %B")
    else:
        end = dt.datetime.fromisoformat(event["end"])
        when = f"{time_until(start, minutes)} · {start:%H:%M}–{end:%H:%M}"
    parts = [when, event.get("location")]
    return " · ".join(part for part in parts if part)


def notify(event: Event, start: dt.datetime, minutes: int) -> None:
    body = reminder_text(event, start, minutes)
    subprocess.run(
        ["notify-send", "-a", "Calendar", "-i", "x-office-calendar", "-u", "normal", event["title"], body],
        check=False,
    )


# ---------- Commands ----------


def read_stdin_json() -> Any:
    return json.load(sys.stdin)


def login(url: str, user: str) -> dict[str, Any]:
    """Checks the app password on stdin, then stores it in the keyring."""
    password = sys.stdin.read().rstrip("\n")
    result = {"calendars": calendars(url, (user, password))}
    store = ["secret-tool", "store", f"--label={KEYRING_LABEL}", *keyring_attributes(url, user)]
    stored = subprocess.run(store, input=password, text=True, check=False)
    if stored.returncode != 0:
        raise Fail("Signed in, but the keyring refused to store the password")
    return result


def logout(url: str, user: str) -> dict[str, Any]:
    subprocess.run(["secret-tool", "clear", *keyring_attributes(url, user)], check=False)
    return {}


def account_command(command: str, url: str, user: str) -> Any:
    if command == "login":
        return login(url, user)
    if command == "logout":
        return logout(url, user)
    auth = (user, stored_password(url, user))
    if command == "calendars":
        return {"calendars": calendars(url, auth)}
    form = read_stdin_json()
    if command == "create":
        return create(url, auth, cast(EventForm, form))
    if command == "update":
        return update(url, auth, cast(EventForm, form))
    return delete(url, auth, cast(DeleteForm, form))


def main(argv: list[str]) -> Any:
    command = argv[1] if len(argv) > 1 else ""
    if command == "events":
        return events(cast(EventsSpec, read_stdin_json()))
    if command == "remind":
        return remind()
    if command not in COMMANDS_WITH_ACCOUNT or len(argv) < 4:
        raise Fail(USAGE)
    url, user = argv[2:4]
    return account_command(command, url, user)


if __name__ == "__main__":
    try:
        print(json.dumps(main(sys.argv)))
    except Fail as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
