# pyright: strict
import json
import tempfile
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from helpers import load

night_light = load("config/quickshell/menus/night-light.py")

BERLIN: dict[str, object] = {"name": "Berlin", "lat": 52.52, "lon": 13.405}
CET = timezone(timedelta(hours=1))


class SunTimes(unittest.TestCase):
    def assertNear(self, actual: datetime, hours: int, minutes: int) -> None:
        expected = actual.replace(hour=hours, minute=minutes, second=0, microsecond=0)
        self.assertLess(abs((actual - expected).total_seconds()), 180, actual)

    def test_berlin_midsummer(self) -> None:
        # 04:43 and 21:33 CEST
        sunrise, sunset = night_light.sun_times(date(2026, 6, 21), 52.52, 13.405)
        self.assertNear(sunrise, 2, 43)
        self.assertNear(sunset, 19, 33)

    def test_berlin_midwinter(self) -> None:
        # 08:16 and 15:54 CET
        sunrise, sunset = night_light.sun_times(date(2026, 12, 21), 52.52, 13.405)
        self.assertNear(sunrise, 7, 16)
        self.assertNear(sunset, 14, 54)

    def test_polar(self) -> None:
        self.assertEqual(night_light.sun_times(date(2026, 12, 21), 78.2, 15.6), night_light.POLAR_NIGHT)
        self.assertEqual(night_light.sun_times(date(2026, 6, 21), 78.2, 15.6), night_light.MIDNIGHT_SUN)


SUN = night_light.options(None)


def times(start: str, end: str) -> dict[str, object]:
    return night_light.options({"nightLight": {"schedule": "times", "from": start, "until": end}})


class Schedule(unittest.TestCase):
    def test_night_between_sunset_and_sunrise(self) -> None:
        def at(h: int, m: int) -> bool:
            return night_light.schedule(datetime(2026, 10, 28, h, m, tzinfo=CET), BERLIN, SUN)["night"]

        self.assertTrue(at(6, 30))
        self.assertFalse(at(12, 0))
        self.assertFalse(at(16, 30))
        self.assertTrue(at(17, 0))

    def test_times_are_local(self) -> None:
        state = night_light.schedule(datetime(2026, 10, 28, 12, 0, tzinfo=CET), BERLIN, SUN)
        self.assertEqual(state["place"], "Berlin")
        self.assertRegex(str(state["from"]), r"^16:(3\d|4\d)$")

    def test_fallback_without_location(self) -> None:
        state = night_light.schedule(datetime(2026, 10, 28, 19, 30, tzinfo=CET), None, SUN)
        self.assertEqual(
            (state["night"], state["from"], state["until"], state["place"]), (True, "19:00", "07:00", None)
        )
        self.assertFalse(night_light.schedule(datetime(2026, 10, 28, 7, 0, tzinfo=CET), None, SUN)["night"])

    def test_polar_night_is_night_all_day(self) -> None:
        north: dict[str, object] = {"name": "North", "lat": 78.2, "lon": 15.6}
        state = night_light.schedule(datetime(2026, 12, 21, 12, 0, tzinfo=CET), north, SUN)
        self.assertEqual((state["night"], state["from"]), (True, None))

    def test_set_times_across_midnight(self) -> None:
        opts = times("22:30", "06:00")

        def at(h: int, m: int) -> bool:
            return bool(night_light.schedule(datetime(2026, 10, 28, h, m, tzinfo=CET), BERLIN, opts)["night"])

        self.assertEqual([at(22, 29), at(22, 30), at(3, 0), at(6, 0)], [False, True, True, False])
        state = night_light.schedule(datetime(2026, 10, 28, 12, 0, tzinfo=CET), BERLIN, opts)
        self.assertEqual((state["from"], state["until"], state["place"]), ("22:30", "06:00", None))

    def test_set_times_within_the_day(self) -> None:
        opts = times("13:00", "15:00")

        def at(h: int) -> bool:
            return bool(night_light.schedule(datetime(2026, 10, 28, h, 0, tzinfo=CET), None, opts)["night"])

        self.assertEqual([at(12), at(13), at(14), at(15), at(23)], [False, True, True, False, False])

    def test_off_is_never_night(self) -> None:
        opts = night_light.options({"nightLight": {"schedule": "off"}})
        state = night_light.schedule(datetime(2026, 10, 28, 23, 0, tzinfo=CET), BERLIN, opts)
        self.assertEqual((state["night"], state["from"], state["schedule"]), (False, None, "off"))


class Options(unittest.TestCase):
    def test_defaults(self) -> None:
        self.assertEqual(night_light.options(None), night_light.DEFAULTS)
        self.assertEqual(night_light.options({"nightLight": "sun"}), night_light.DEFAULTS)

    def test_invalid_values_are_left_out(self) -> None:
        given = {"schedule": "always", "from": "25:00", "until": "7", "temperature": 200}
        self.assertEqual(night_light.options({"nightLight": given}), night_light.DEFAULTS)

    def test_valid_values(self) -> None:
        given = {"schedule": "times", "from": "8:15", "until": "23:59", "temperature": 3400.0}
        self.assertEqual(
            night_light.options({"nightLight": given}),
            {"schedule": "times", "from": "8:15", "until": "23:59", "temperature": 3400},
        )


class Location(unittest.TestCase):
    def test_machine_settings_line(self) -> None:
        line = '-- settings: {"location": {"name": "Berlin", "lat": 52.52, "lon": 13.405}}'
        lua = f"-- BEGIN settings\n{line}\n-- END settings\n"
        self.assertEqual(night_light.place_in(night_light.machine_settings(lua)), BERLIN)

    def test_without_a_place(self) -> None:
        self.assertIsNone(night_light.machine_settings("hl.env('A', 'b')\n"))
        self.assertIsNone(night_light.place_in(None))
        self.assertIsNone(night_light.place_in({"location": None}))
        self.assertIsNone(night_light.place_in({"location": {"name": "Nowhere"}}))
        self.assertIsNone(night_light.place_in(["location"]))

    def test_machine_first_then_calendar(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            calendar = Path(tmp) / "calendar.json"
            calendar.write_text(json.dumps({"location": BERLIN}))
            with mock.patch.object(night_light, "CALENDAR", calendar):
                north = {"name": "North", "lat": 78.2, "lon": 15.6}
                self.assertEqual(night_light.location({"location": north}), (north, "machine"))
                self.assertEqual(night_light.location({}), (BERLIN, "calendar"))
                calendar.unlink()
                self.assertEqual(night_light.location(None), (None, None))


if __name__ == "__main__":
    unittest.main()
