#!/usr/bin/env python3
"""CalDAV client for the quickshell calendar menu (Python standard library only).

  calendar-dav.py login URL USER       app password on stdin: check it, store it
                                       in the keyring, print the calendars
  calendar-dav.py calendars URL USER   print the calendars
  calendar-dav.py events URL USER START END HREF...
                                       events from START to END (ISO dates, END
                                       exclusive) in the given calendars, with
                                       recurring events expanded by the server
  calendar-dav.py logout URL USER      forget the stored password

URL is the Nextcloud address (https://cloud.example.com) or a DAV root. The
password lives in the Secret Service keyring (secret-tool); it is never
written to a file or passed on a command line. Output is JSON on stdout;
on failure {"error": "..."} and exit status 1.
"""

import base64
import datetime as dt
import json
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo

NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav", "a": "http://apple.com/ns/ical/"}


class Fail(Exception):
    pass


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


def request(method, url, auth, body, depth):
    req = urllib.request.Request(url, data=body.encode(), method=method)
    token = base64.b64encode(f"{auth[0]}:{auth[1]}".encode()).decode()
    req.add_header("Authorization", f"Basic {token}")
    req.add_header("Content-Type", "application/xml; charset=utf-8")
    req.add_header("Depth", str(depth))
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return ET.fromstring(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise Fail("Wrong username or app password") from None
        raise Fail(f"Server answered {e.code} {e.reason}") from None
    except urllib.error.URLError as e:
        raise Fail(f"Can't reach the server ({e.reason})") from None
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
    return request("PROPFIND", url, auth, body, depth)


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
    tree = propfind(home, auth, "<d:resourcetype/><d:displayname/><a:calendar-color/><c:supported-calendar-component-set/>", 1)
    return parse_calendars(root, tree)


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
        out.append({
            "href": href,
            "name": (name.text if name is not None else None) or urllib.parse.unquote(href.rstrip("/").rsplit("/", 1)[-1]),
            "color": ((color.text or "") if color is not None else "")[:7] or "#8aadf4",
        })
    return out


def events(auth, start, end, hrefs):
    def utc(day):
        return dt.datetime.combine(day, dt.time()).astimezone().astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    s, e = utc(start), utc(end)
    body = (
        '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-data>'
        f'<c:expand start="{s}" end="{e}"/></c:calendar-data></d:prop><c:filter><c:comp-filter name="VCALENDAR">'
        f'<c:comp-filter name="VEVENT"><c:time-range start="{s}" end="{e}"/></c:comp-filter></c:comp-filter>'
        "</c:filter></c:calendar-query>"
    )
    out = []
    for href in hrefs:
        tree = request("REPORT", href, auth, body, 1)
        for data in tree.iter(f"{{{NS['c']}}}calendar-data"):
            out += parse_ics(data.text or "", href)
    return out


def unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text).splitlines()


def unescape(value):
    return re.sub(r"\\(.)", lambda m: "\n" if m.group(1) in "nN" else m.group(1), value)


def split_property(line):
    """'DTSTART;TZID="Europe/Berlin":2026…' -> ('DTSTART', {'TZID': …}, '2026…')"""
    quoted, colon = False, -1
    for i, ch in enumerate(line):
        if ch == '"':
            quoted = not quoted
        elif ch == ":" and not quoted:
            colon = i
            break
    head, value = line[:colon], line[colon + 1:]
    name, *params = head.split(";")
    params = dict(p.split("=", 1) for p in params if "=" in p)
    return name.upper(), {k.upper(): v.strip('"') for k, v in params.items()}, value


def parse_time(params, value):
    """(datetime or date, all_day)"""
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
        return dt.date(int(value[:4]), int(value[4:6]), int(value[6:8])), True
    t = dt.datetime.strptime(value.rstrip("Z")[:15], "%Y%m%dT%H%M%S")
    if value.endswith("Z"):
        return t.replace(tzinfo=dt.timezone.utc), False
    try:
        return t.replace(tzinfo=ZoneInfo(params["TZID"])), False
    except (KeyError, ValueError, LookupError):
        return t.astimezone(), False  # floating time or unknown zone: local


def parse_duration(value):
    m = re.fullmatch(r"([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", value)
    if not m:
        return dt.timedelta()
    sign, w, d, h, mi, s = m.groups()
    delta = dt.timedelta(weeks=int(w or 0), days=int(d or 0), hours=int(h or 0), minutes=int(mi or 0), seconds=int(s or 0))
    return -delta if sign == "-" else delta


def parse_ics(text, href):
    out, event, nested = [], None, 0
    for line in unfold(text):
        if line == "BEGIN:VEVENT":
            event, nested = {}, 0
        elif event is None:
            continue
        elif line == "END:VEVENT":
            if "DTSTART" in event and event.get("STATUS", ({}, ""))[1].upper() != "CANCELLED":
                out.append(to_json(event, href))
            event = None
        elif line.startswith("BEGIN:"):
            nested += 1  # VALARM etc.
        elif line.startswith("END:"):
            nested -= 1
        elif nested == 0 and ":" in line:
            name, params, value = split_property(line)
            event.setdefault(name, (params, value))
    return out


def to_json(event, href):
    start, all_day = parse_time(*event["DTSTART"])
    if "DTEND" in event:
        end = parse_time(*event["DTEND"])[0]
    elif "DURATION" in event:
        end = start + parse_duration(event["DURATION"][1])
    else:
        end = start + (dt.timedelta(days=1) if all_day else dt.timedelta())
    return {
        "calendar": href,
        "title": unescape(event.get("SUMMARY", ({}, ""))[1]) or "(No title)",
        "location": unescape(event.get("LOCATION", ({}, ""))[1]),
        "allDay": all_day,
        "start": start.isoformat(),
        "end": end.isoformat(),
    }


def main(argv):
    if len(argv) < 4 or argv[1] not in ("login", "calendars", "events", "logout"):
        raise Fail("usage: calendar-dav.py login|calendars|events|logout URL USER [START END HREF...]")
    command, url, user = argv[1:4]
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
    start, end = dt.date.fromisoformat(argv[4]), dt.date.fromisoformat(argv[5])
    return {"events": events(auth, start, end, argv[6:])}


if __name__ == "__main__":
    try:
        print(json.dumps(main(sys.argv)))
    except Fail as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
