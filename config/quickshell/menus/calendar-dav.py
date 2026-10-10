#!/usr/bin/env quickshell-calendar-python
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
                                       start, end}: new event on Nextcloud
  calendar-dav.py update URL USER      stdin {href, etag, title, location, allDay,
                                       start, end}: change a (non-recurring)
                                       event, keeping everything else in it
  calendar-dav.py delete URL USER      stdin {href, etag}: delete an event

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
from pathlib import Path
from zoneinfo import ZoneInfo

import icalendar
import recurring_ical_events

NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav", "a": "http://apple.com/ns/ical/"}
ICS_CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell-calendar" / "ics"
ICS_MAX_AGE = 6 * 3600
USER_AGENT = "quickshell-calendar/1.0"


class Fail(Exception):
    pass


# Nextcloud / CalDAV ---------------------------------------------------------


def dav_root(url):
    url = url.strip().rstrip("/")
    if not re.match(r"https?://", url):
        url = "https://" + url
    if "/remote.php/dav" not in url and not url.endswith("/dav"):
        url += "/remote.php/dav"
    return url + "/"


def keyring_attrs(url, user):
    return ["service", "quickshell-calendar", "url", dav_root(url), "user", user]


def stored_password(url, user):
    r = subprocess.run(["secret-tool", "lookup", *keyring_attrs(url, user)], capture_output=True, text=True)
    if r.returncode or not r.stdout:
        raise Fail("No app password stored, sign in again in the settings")
    return r.stdout.rstrip("\n")


def http(method, url, auth=None, body=b"", headers=None):
    """(status, response headers, body); raises Fail for errors."""
    req = urllib.request.Request(url, data=body or None, method=method)
    req.add_header("User-Agent", USER_AGENT)
    if auth:
        token = base64.b64encode(f"{auth[0]}:{auth[1]}".encode()).decode()
        req.add_header("Authorization", f"Basic {token}")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, r.headers, r.read()
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise Fail("Wrong username or app password") from None
        if e.code == 412:
            raise Fail("The event changed on the server, reload and try again") from None
        raise Fail(f"Server answered {e.code} {e.reason}") from None
    except urllib.error.URLError as e:
        raise Fail(f"Can't reach the server ({e.reason})") from None
    except TimeoutError:
        raise Fail("The server took too long to answer") from None


def dav(method, url, auth, body, depth):
    headers = {"Content-Type": "application/xml; charset=utf-8", "Depth": str(depth)}
    _, _, data = http(method, url, auth, body.encode(), headers)
    try:
        return ET.fromstring(data)
    except ET.ParseError:
        raise Fail("The server's answer isn't CalDAV, check the address") from None


def found(response, path):
    """Element at `path` inside a response's successful propstat, or None."""
    for propstat in response.findall("d:propstat", NS):
        if " 200 " in propstat.findtext("d:status", "", NS) + " ":
            el = propstat.find(f"d:prop/{path}", NS)
            if el is not None:
                return el
    return None


def propfind(url, auth, props, depth=0):
    body = (
        '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" '
        f'xmlns:a="http://apple.com/ns/ical/"><d:prop>{props}</d:prop></d:propfind>'
    )
    return dav("PROPFIND", url, auth, body, depth)


def follow(base, tree, path, what):
    for response in tree.findall("d:response", NS):
        el = found(response, path)
        if el is not None and el.text:
            return urllib.parse.urljoin(base, el.text.strip())
    raise Fail(f"The server didn't tell the {what}, check the address")


def calendars(url, auth):
    root = dav_root(url)
    principal = follow(root, propfind(root, auth, "<d:current-user-principal/>"), "d:current-user-principal/d:href", "user")
    home = follow(root, propfind(principal, auth, "<c:calendar-home-set/>"), "c:calendar-home-set/d:href", "calendar home")
    props = "<d:resourcetype/><d:displayname/><a:calendar-color/><c:supported-calendar-component-set/><d:current-user-privilege-set/>"
    return parse_calendars(root, propfind(home, auth, props, 1))


def parse_calendars(root, tree):
    out = []
    for response in tree.findall("d:response", NS):
        kind = found(response, "d:resourcetype")
        if kind is None or kind.find("c:calendar", NS) is None:
            continue
        comps = found(response, "c:supported-calendar-component-set")
        if comps is not None and "VEVENT" not in [c.get("name") for c in comps.findall("c:comp", NS)]:
            continue  # tasks only, e.g. Deck boards
        href = urllib.parse.urljoin(root, response.findtext("d:href", "", NS))
        name = found(response, "d:displayname")
        color = found(response, "a:calendar-color")
        privileges = found(response, "d:current-user-privilege-set")
        granted = {el.tag.split("}")[-1] for el in privileges.iter()} if privileges is not None else {"write"}
        out.append({
            "href": href,
            "name": (name.text if name is not None else None) or urllib.parse.unquote(href.rstrip("/").rsplit("/", 1)[-1]),
            "color": ((color.text or "") if color is not None else "")[:7] or "#8aadf4",
            "writable": bool(granted & {"write", "write-content", "all", "bind"}),
        })
    return out


def utc_stamp(day):
    return dt.datetime.combine(day, dt.time()).astimezone().astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def caldav_events(auth, start, end, href):
    """Events of one Nextcloud calendar. Fetches the event objects that touch
    the range and expands recurrences locally, like the ICS feeds."""
    body = (
        '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><d:getetag/><c:calendar-data/>'
        '</d:prop><c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">'
        f'<c:time-range start="{utc_stamp(start)}" end="{utc_stamp(end)}"/></c:comp-filter></c:comp-filter>'
        "</c:filter></c:calendar-query>"
    )
    out = []
    for response in dav("REPORT", href, auth, body, 1).findall("d:response", NS):
        data = found(response, "c:calendar-data")
        if data is None or not data.text:
            continue
        etag = found(response, "d:getetag")
        source = {
            "calendar": href,
            "href": urllib.parse.urljoin(href, response.findtext("d:href", "", NS)),
            "etag": etag.text if etag is not None else "",
        }
        out += expand(data.text, start, end, source)
    return out


def apply_fields(ev, event):
    """Title, place and times from the menu's form onto a VEVENT; times in
    the local zone, all-day `end` is the last day (inclusive)."""
    for key in ("summary", "location", "dtstart", "dtend", "duration"):
        ev.pop(key, None)
    ev.add("summary", event["title"])
    if event.get("location"):
        ev.add("location", event["location"])
    if event.get("allDay"):
        start = dt.date.fromisoformat(event["start"][:10])
        end = dt.date.fromisoformat(event["end"][:10])
        ev.add("dtstart", start)
        ev.add("dtend", max(end, start) + dt.timedelta(days=1))  # DTEND is exclusive
    else:
        zone = local_zone()
        start = dt.datetime.fromisoformat(event["start"]).replace(tzinfo=zone)
        end = dt.datetime.fromisoformat(event["end"]).replace(tzinfo=zone)
        ev.add("dtstart", start)
        ev.add("dtend", max(end, start))


def create(url, auth, event):
    """PUT a new event into a Nextcloud calendar."""
    if not event["calendar"].startswith(dav_root(url)):
        raise Fail("That calendar doesn't belong to this account")
    cal = icalendar.Calendar()
    cal.add("prodid", "-//quickshell//calendar menu//EN")
    cal.add("version", "2.0")
    ev = icalendar.Event()
    uid = str(uuid.uuid4())
    ev.add("uid", uid)
    ev.add("dtstamp", dt.datetime.now(dt.timezone.utc))
    apply_fields(ev, event)
    cal.add_component(ev)
    cal.add_missing_timezones()
    href = event["calendar"].rstrip("/") + f"/{uid}.ics"
    headers = {"Content-Type": "text/calendar; charset=utf-8", "If-None-Match": "*"}
    http("PUT", href, auth, cal.to_ical(), headers)
    return {"href": href}


def update(url, auth, event):
    """Change title, place and times of an existing event. Everything else in
    it (description, reminders, attendees, ...) stays; the If-Match ETag makes
    the server refuse if it was changed elsewhere meanwhile."""
    if not event["href"].startswith(dav_root(url)):
        raise Fail("That event doesn't belong to this account")
    _, headers, data = http("GET", event["href"], auth)
    try:
        cal = icalendar.Calendar.from_ical(data)
    except ValueError as e:
        raise Fail(f"Couldn't read the event ({e})") from None
    vevents = cal.walk("VEVENT")
    if len(vevents) != 1 or vevents[0].get("rrule") is not None:
        raise Fail("Recurring events can only be changed in Nextcloud")
    etag = event.get("etag") or headers.get("ETag", "")
    if headers.get("ETag") and etag and headers.get("ETag") != etag:
        raise Fail("The event changed on the server, reload and try again")
    ev = vevents[0]
    apply_fields(ev, event)
    for key in ("dtstamp", "last-modified"):
        ev.pop(key, None)
    now = dt.datetime.now(dt.timezone.utc)
    ev.add("dtstamp", now)
    ev.add("last-modified", now)
    sequence = int(ev.pop("sequence", 0))
    ev.add("sequence", sequence + 1)
    cal.add_missing_timezones()
    put_headers = {"Content-Type": "text/calendar; charset=utf-8"}
    if etag:
        put_headers["If-Match"] = etag
    http("PUT", event["href"], auth, cal.to_ical(), put_headers)
    return {"href": event["href"]}


def delete(url, auth, event):
    if not event["href"].startswith(dav_root(url)):
        raise Fail("That event doesn't belong to this account")
    http("DELETE", event["href"], auth, headers={"If-Match": event["etag"]} if event.get("etag") else {})
    return {}


def local_zone():
    try:
        name = os.path.realpath("/etc/localtime").split("zoneinfo/", 1)[1]
        return ZoneInfo(name)
    except (IndexError, KeyError, ValueError):
        return dt.datetime.now().astimezone().tzinfo


# ICS subscriptions -----------------------------------------------------------


def ics_text(url):
    """The feed, cached for ICS_MAX_AGE; a stale copy if it can't be fetched."""
    url = re.sub(r"^webcal://", "https://", url.strip(), flags=re.I)
    ICS_CACHE.mkdir(parents=True, exist_ok=True)
    cached = ICS_CACHE / (hashlib.sha1(url.encode()).hexdigest() + ".ics")
    if cached.exists() and time.time() - cached.stat().st_mtime < ICS_MAX_AGE:
        return cached.read_text(errors="replace")
    try:
        _, _, data = http("GET", url)
    except Fail:
        if cached.exists():
            return cached.read_text(errors="replace")
        raise
    text = data.decode("utf-8", errors="replace")
    if "BEGIN:VCALENDAR" not in text:
        raise Fail("That address isn't an ICS calendar")
    cached.write_text(text)
    return text


# Events ---------------------------------------------------------------------


def as_local(value, all_day):
    if all_day:
        return value.isoformat()
    if value.tzinfo is None:
        value = value.astimezone()  # floating time: local
    return value.isoformat()


def expand(text, start, end, source):
    try:
        cal = icalendar.Calendar.from_ical(text)
    except ValueError as e:
        raise Fail(f"Couldn't read the calendar data ({e})") from None
    # Expanded occurrences all carry a RECURRENCE-ID, so look at the source
    recurring = {
        str(c.get("uid")) for c in cal.walk("VEVENT")
        if c.get("rrule") is not None or c.get("rdate") is not None or c.get("recurrence-id") is not None
    }
    out = []
    for ev in recurring_ical_events.of(cal).between(start, end):
        if str(ev.get("status", "")).upper() == "CANCELLED":
            continue
        begin = ev.get("dtstart").dt
        all_day = not isinstance(begin, dt.datetime)
        if ev.get("dtend") is not None:
            finish = ev.get("dtend").dt
        elif ev.get("duration") is not None:
            finish = begin + ev.get("duration").dt
        else:
            finish = begin + (dt.timedelta(days=1) if all_day else dt.timedelta())
        out.append({
            **source,
            "uid": str(ev.get("uid", "")),
            "title": str(ev.get("summary", "")) or "(No title)",
            "location": str(ev.get("location", "")),
            "allDay": all_day,
            "start": as_local(begin, all_day),
            "end": as_local(finish, all_day),
            "recurring": str(ev.get("uid", "")) in recurring,
        })
    return out


def events(spec):
    start, end = dt.date.fromisoformat(spec["start"]), dt.date.fromisoformat(spec["end"])
    out, errors = [], {}
    nc = spec.get("nextcloud")
    if nc and nc.get("calendars"):
        try:
            auth = (nc["user"], stored_password(nc["url"], nc["user"]))
            for href in nc["calendars"]:
                try:
                    out += caldav_events(auth, start, end, href)
                except Fail as e:
                    errors[href] = str(e)
                    if "password" in str(e):
                        break
        except Fail as e:
            errors["nextcloud"] = str(e)
    for feed in spec.get("ics", []):
        try:
            out += expand(ics_text(feed["url"]), start, end, {"calendar": feed["id"]})
        except Fail as e:
            errors[feed["id"]] = str(e)
    return {"events": out, "errors": errors}


def main(argv):
    command = argv[1] if len(argv) > 1 else ""
    if command == "events":
        return events(json.load(sys.stdin))
    if command not in ("login", "calendars", "logout", "create", "update", "delete") or len(argv) < 4:
        raise Fail("usage: calendar-dav.py login|calendars|logout|create|update|delete URL USER, or events")
    url, user = argv[2:4]
    if command == "login":
        password = sys.stdin.read().rstrip("\n")
        result = {"calendars": calendars(url, (user, password))}
        store = ["secret-tool", "store", "--label=Nextcloud calendar (quickshell)", *keyring_attrs(url, user)]
        if subprocess.run(store, input=password, text=True).returncode:
            raise Fail("Signed in, but the keyring refused to store the password")
        return result
    if command == "logout":
        subprocess.run(["secret-tool", "clear", *keyring_attrs(url, user)])
        return {}
    auth = (user, stored_password(url, user))
    if command == "calendars":
        return {"calendars": calendars(url, auth)}
    if command == "create":
        return create(url, auth, json.load(sys.stdin))
    if command == "update":
        return update(url, auth, json.load(sys.stdin))
    return delete(url, auth, json.load(sys.stdin))


if __name__ == "__main__":
    try:
        print(json.dumps(main(sys.argv)))
    except Fail as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
