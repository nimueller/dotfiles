# pyright: strict
import unittest
from datetime import date, datetime, timedelta, timezone

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


class Schedule(unittest.TestCase):
    def test_night_between_sunset_and_sunrise(self) -> None:
        def at(h: int, m: int) -> bool:
            return night_light.schedule(datetime(2026, 10, 28, h, m, tzinfo=CET), BERLIN)["night"]

        self.assertTrue(at(6, 30))
        self.assertFalse(at(12, 0))
        self.assertFalse(at(16, 30))
        self.assertTrue(at(17, 0))

    def test_times_are_local(self) -> None:
        state = night_light.schedule(datetime(2026, 10, 28, 12, 0, tzinfo=CET), BERLIN)
        self.assertEqual(state["place"], "Berlin")
        self.assertRegex(str(state["sunset"]), r"^16:(3\d|4\d)$")

    def test_fallback_without_location(self) -> None:
        state = night_light.schedule(datetime(2026, 10, 28, 19, 30, tzinfo=CET), None)
        self.assertEqual(
            (state["night"], state["sunset"], state["sunrise"], state["place"]), (True, "19:00", "07:00", None)
        )
        self.assertFalse(night_light.schedule(datetime(2026, 10, 28, 7, 0, tzinfo=CET), None)["night"])

    def test_polar_night_is_night_all_day(self) -> None:
        north: dict[str, object] = {"name": "North", "lat": 78.2, "lon": 15.6}
        state = night_light.schedule(datetime(2026, 12, 21, 12, 0, tzinfo=CET), north)
        self.assertEqual((state["night"], state["sunset"]), (True, None))


if __name__ == "__main__":
    unittest.main()
