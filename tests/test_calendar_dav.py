# pyright: strict
import datetime as dt
import time
import unittest
import xml.etree.ElementTree as ET
from typing import Any

from helpers import load

calendar_dav = load("config/quickshell/menus/calendar-dav.py")

ROOT = "https://cloud.example.com/remote.php/dav/"
HOME = "/remote.php/dav/calendars/someone/"

CALENDAR_HOME = f"""<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:a="http://apple.com/ns/ical/">
  <d:response>
    <d:href>{HOME}</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>{HOME}personal/</d:href>
    <d:propstat><d:prop>
      <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
      <d:displayname>Personal</d:displayname>
      <a:calendar-color>#ff8800ff</a:calendar-color>
      <c:supported-calendar-component-set>
        <c:comp name="VEVENT"/><c:comp name="VTODO"/>
      </c:supported-calendar-component-set>
      <d:current-user-privilege-set>
        <d:privilege><d:read/></d:privilege><d:privilege><d:write/></d:privilege>
      </d:current-user-privilege-set>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>{HOME}shared%20one/</d:href>
    <d:propstat><d:prop>
      <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
      <d:current-user-privilege-set><d:privilege><d:read/></d:privilege></d:current-user-privilege-set>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
    <d:propstat><d:prop><d:displayname/><a:calendar-color/></d:prop>
      <d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>{HOME}deck/</d:href>
    <d:propstat><d:prop>
      <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
      <c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>
"""

FEED = """BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
BEGIN:VEVENT
UID:weekly
SUMMARY:Weekly
DTSTART:20260105T100000Z
DTEND:20260105T110000Z
RRULE:FREQ=WEEKLY;COUNT=3
BEGIN:VALARM
ACTION:DISPLAY
TRIGGER:-PT15M
END:VALARM
BEGIN:VALARM
ACTION:EMAIL
TRIGGER;RELATED=END:PT5M
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:holiday
SUMMARY:Holiday
DTSTART;VALUE=DATE:20260107
END:VEVENT
BEGIN:VEVENT
UID:cancelled
SUMMARY:Cancelled
STATUS:CANCELLED
DTSTART:20260108T100000Z
DTEND:20260108T110000Z
END:VEVENT
BEGIN:VEVENT
UID:floating
LOCATION:Room 1
DTSTART:20260109T090000
DURATION:PT30M
COLOR:red
END:VEVENT
END:VCALENDAR
"""


class DavRoot(unittest.TestCase):
    def test_host_only(self) -> None:
        self.assertEqual(calendar_dav.dav_root("cloud.example.com"), ROOT)

    def test_trailing_slash(self) -> None:
        self.assertEqual(calendar_dav.dav_root(" https://cloud.example.com/ "), ROOT)

    def test_dav_root_kept(self) -> None:
        self.assertEqual(calendar_dav.dav_root("http://host/dav"), "http://host/dav/")


class ParseCalendars(unittest.TestCase):
    def test_calendars_of_the_home(self) -> None:
        tree = ET.fromstring(CALENDAR_HOME)
        found: list[dict[str, Any]] = calendar_dav.parse_calendars(ROOT, tree)
        self.assertEqual(
            found,
            [
                {
                    "href": "https://cloud.example.com/remote.php/dav/calendars/someone/personal/",
                    "name": "Personal",
                    "color": "#ff8800",
                    "writable": True,
                },
                # No name or color: from the href, and the default color
                {
                    "href": "https://cloud.example.com/remote.php/dav/calendars/someone/shared%20one/",
                    "name": "shared one",
                    "color": calendar_dav.DEFAULT_COLOR,
                    "writable": False,
                },
            ],
        )


def by_title(events: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for event in events:
        grouped.setdefault(event["title"], []).append(event)
    return grouped


class Expand(unittest.TestCase):
    def setUp(self) -> None:
        source = {"calendar": "feed"}
        events = calendar_dav.expand(FEED, dt.date(2026, 1, 1), dt.date(2026, 1, 31), source)
        self.events = by_title(events)

    def test_recurrences_expanded(self) -> None:
        weekly = self.events["Weekly"]
        self.assertEqual(len(weekly), 3)
        self.assertTrue(all(event["recurring"] for event in weekly))

    def test_only_start_related_alarms(self) -> None:
        self.assertEqual(self.events["Weekly"][0]["alarms"], [15])

    def test_all_day_lasts_a_day(self) -> None:
        (holiday,) = self.events["Holiday"]
        self.assertTrue(holiday["allDay"])
        self.assertEqual((holiday["start"], holiday["end"]), ("2026-01-07", "2026-01-08"))
        self.assertFalse(holiday["recurring"])

    def test_cancelled_left_out(self) -> None:
        self.assertNotIn("Cancelled", self.events)

    def test_floating_time_with_duration(self) -> None:
        (floating,) = self.events[calendar_dav.NO_TITLE]
        start = dt.datetime.fromisoformat(floating["start"])
        end = dt.datetime.fromisoformat(floating["end"])
        self.assertIsNotNone(start.tzinfo)
        self.assertEqual(end - start, dt.timedelta(minutes=30))
        self.assertEqual((floating["location"], floating["color"]), ("Room 1", "red"))
        self.assertEqual(floating["calendar"], "feed")


class Alarms(unittest.TestCase):
    def test_set_alarms_replaces_start_related_only(self) -> None:
        events = calendar_dav.parse_calendar(FEED).walk("VEVENT")
        weekly = events[0]
        calendar_dav.set_alarms(weekly, [30, 5, 30], "Weekly")
        minutes = [minutes for _alarm, minutes in calendar_dav.start_alarms(weekly)]
        self.assertEqual(minutes, [5, 30])
        # The e-mail alarm relative to the end stays
        self.assertEqual(len(weekly.walk("VALARM")), 3)


class ApplyFields(unittest.TestCase):
    def test_all_day_end_is_inclusive_in_the_form(self) -> None:
        event = calendar_dav.new_component(calendar_dav.icalendar.Event)
        form = {"title": "Trip", "start": "2026-03-02", "end": "2026-03-04", "allDay": True, "alarms": [60]}
        calendar_dav.apply_fields(event, form)
        self.assertEqual(event["dtstart"].dt, dt.date(2026, 3, 2))
        self.assertEqual(event["dtend"].dt, dt.date(2026, 3, 5))
        self.assertEqual(str(event["summary"]), "Trip")
        self.assertNotIn("LOCATION", event)

    def test_end_before_start_becomes_start(self) -> None:
        event = calendar_dav.new_component(calendar_dav.icalendar.Event)
        form = {"title": "x", "start": "2026-03-02T10:00", "end": "2026-03-02T09:00", "location": "Here"}
        calendar_dav.apply_fields(event, form)
        self.assertEqual(event["dtend"].dt, event["dtstart"].dt)
        self.assertEqual(str(event["location"]), "Here")


class Reminders(unittest.TestCase):
    def event(self, **fields: Any) -> dict[str, Any]:
        base: dict[str, Any] = {
            "title": "Meeting",
            "allDay": False,
            "start": "2026-03-02T10:00:00+01:00",
            "end": "2026-03-02T11:30:00+01:00",
            "location": "",
            "alarms": [15],
            "uid": "a",
        }
        return base | fields

    def test_text_soon(self) -> None:
        event = self.event(location="Room 1")
        start = dt.datetime.fromisoformat(event["start"])
        text = calendar_dav.reminder_text(event, start, 15)
        self.assertEqual(text, "in 15 min · 10:00–11:30 · Room 1")

    def test_text_now_and_later(self) -> None:
        event = self.event()
        start = dt.datetime.fromisoformat(event["start"])
        self.assertTrue(calendar_dav.reminder_text(event, start, 0).startswith("now · "))
        self.assertTrue(calendar_dav.reminder_text(event, start, 90).startswith("at 10:00 · "))

    def test_text_all_day_today(self) -> None:
        today = dt.date.today()
        event = self.event(allDay=True, start=today.isoformat())
        start = calendar_dav.event_start(event)
        self.assertEqual(calendar_dav.reminder_text(event, start, 0), "today")

    def test_last_run_after_a_pause(self) -> None:
        now = time.time()
        self.assertEqual(calendar_dav.last_run({}, now), now - calendar_dav.FIRST_RUN)
        self.assertEqual(calendar_dav.last_run({"last": now - 120}, now), now - 120)
        self.assertEqual(calendar_dav.last_run({"last": now - 7200}, now), now - calendar_dav.CATCH_UP)

    def test_old_fired_keys_dropped(self) -> None:
        today = dt.date.today()
        old = f"uid|{today - dt.timedelta(days=5)}T10:00|15"
        recent = f"a|b|{today}T10:00|15"
        self.assertFalse(calendar_dav.is_recent_key(old))
        self.assertTrue(calendar_dav.is_recent_key(recent))

    def test_sources_only_enabled(self) -> None:
        settings = {
            "nextcloud": {
                "url": "cloud",
                "user": "someone",
                "calendars": [{"href": "a", "enabled": True}, {"href": "b", "enabled": False}],
            },
            "ics": [{"id": "x", "url": "u", "enabled": True}, {"id": "y", "url": "v"}],
        }
        self.assertEqual(
            calendar_dav.sources(settings),
            {"nextcloud": {"url": "cloud", "user": "someone", "calendars": ["a"]}, "ics": [{"id": "x", "url": "u"}]},
        )
        self.assertEqual(calendar_dav.sources({}), {"nextcloud": None, "ics": []})


if __name__ == "__main__":
    unittest.main()
