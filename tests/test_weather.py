# pyright: strict
import io
import os
import time
import unittest
import zipfile
from datetime import UTC, datetime
from unittest import mock

from helpers import load

weather = load("config/quickshell/menus/weather.py")

CATALOGUE = """\
ID    ICAO NAME                 LAT    LON     ELEV
----- ---- -------------------- -----  ------- -----
01001 ENJA JAN MAYEN             70.56   -8.40    10
10637 EDDF FRANKFURT/M           50.03    8.36   111
 E564 ---- FRANKENFELD-HEDERN    52.46    9.24    18
"""

KML = """\
<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>
<kml:kml xmlns:dwd="https://opendata.dwd.de/weather/lib/pointforecast_dwd_extension_V1_0.xsd"
         xmlns:kml="http://www.opengis.net/kml/2.2">
  <kml:Document>
    <kml:ExtendedData>
      <dwd:ProductDefinition>
        <dwd:IssueTime>2026-11-11T15:00:00.000Z</dwd:IssueTime>
        <dwd:ForecastTimeSteps>
          <dwd:TimeStep>2026-11-11T22:00:00.000Z</dwd:TimeStep>
          <dwd:TimeStep>2026-11-11T23:00:00.000Z</dwd:TimeStep>
          <dwd:TimeStep>2026-11-12T00:00:00.000Z</dwd:TimeStep>
        </dwd:ForecastTimeSteps>
      </dwd:ProductDefinition>
    </kml:ExtendedData>
    <kml:Placemark>
      <kml:name>10637</kml:name>
      <kml:ExtendedData>
        <dwd:Forecast dwd:elementName="TTT"><dwd:value>  283.15  273.15  -</dwd:value></dwd:Forecast>
        <dwd:Forecast dwd:elementName="ww"><dwd:value>  61.00  3.00  3.00</dwd:value></dwd:Forecast>
        <dwd:Forecast dwd:elementName="R101"><dwd:value>  40.00  -  2.00</dwd:value></dwd:Forecast>
        <dwd:Forecast dwd:elementName="Rad1h"><dwd:value>  0.00  10.00  0.00</dwd:value></dwd:Forecast>
      </kml:ExtendedData>
    </kml:Placemark>
  </kml:Document>
</kml:kml>
"""

# The first columns of a station's reports, newest first
REPORT_NAMES = [
    "surface observations",
    "Parameter description",
    "cloud_cover_total",
    "dry_bulb_temperature_at_2_meter_above_ground",
    "present_weather",
    "horizontal_visibility",
]
REPORT = "\n".join(
    [
        ";".join(REPORT_NAMES),
        "10637;Unit;%;Grad C;CODE_TABLE;km",
        "Datum;Uhrzeit (UTC);Wolkenbedeckung;Temperatur (2m);aktuelles Wetter;Sichtweite",
        "11.11.26;18:00;---;---;---;---",
        "11.11.26;17:00;100;8,2;5;6,1",
        "11.11.26;16:00;100;8;4;2,6",
    ]
)

LISTING = """\
<a href="10637-BEOB.csv">10637-BEOB.csv</a>                                     11-Nov-2026 17:43:02                7346
<a href="10641-BEOB.csv">10641-BEOB.csv</a>                                     11-Nov-2026 15:43:17                4448
"""


def kmz(kml: str) -> bytes:
    data = io.BytesIO()
    with zipfile.ZipFile(data, "w") as archive:
        archive.writestr("MOSMIX_L_2026111115_10637.kml", kml.encode("latin-1"))
    return data.getvalue()


def utc(text: str) -> datetime:
    return datetime.fromisoformat(text).replace(tzinfo=UTC)


class Stations(unittest.TestCase):
    def test_degrees_and_minutes(self) -> None:
        self.assertAlmostEqual(weather.degrees("50.03"), 50.05)
        self.assertAlmostEqual(weather.degrees("-8.40"), -8 - 40 / 60)
        self.assertAlmostEqual(weather.degrees("-0.30"), -0.5)

    def test_catalogue(self) -> None:
        stations = weather.parse_catalogue(CATALOGUE)
        self.assertEqual([s.id for s in stations], ["01001", "10637", "E564"])
        self.assertEqual(stations[1].name, "Frankfurt/M")
        self.assertAlmostEqual(stations[1].lat, 50.05)
        self.assertAlmostEqual(stations[1].lon, 8.6)

    def test_nearest_first(self) -> None:
        stations = weather.parse_catalogue(CATALOGUE)
        nearest = weather.by_distance(stations, 50.1, 8.7)
        self.assertEqual([s.id for _, s in nearest], ["10637", "E564", "01001"])
        self.assertLess(nearest[0][0], 10)

    def test_distance(self) -> None:
        # A degree of latitude is about 111 km
        self.assertAlmostEqual(weather.distance_km(50, 8, 51, 8), 111.2, places=1)


class Forecast(unittest.TestCase):
    def setUp(self) -> None:
        os.environ["TZ"] = "Europe/Berlin"
        time.tzset()

    def tearDown(self) -> None:
        del os.environ["TZ"]
        time.tzset()

    def test_hours_without_values_are_left_out(self) -> None:
        issued, hours = weather.parse_forecast(kmz(KML))
        self.assertEqual(issued, utc("2026-11-11T15:00"))
        self.assertEqual([h.time for h in hours], [utc("2026-11-11T22:00"), utc("2026-11-11T23:00")])
        self.assertAlmostEqual(hours[0].temp, 10)
        self.assertEqual(hours[0].code, 61)
        self.assertEqual(hours[1].rain, None)

    def test_night_is_an_hour_without_sunlight(self) -> None:
        _, hours = weather.parse_forecast(kmz(KML))
        self.assertEqual([h.is_night for h in hours], [True, False])

    def test_hourly_in_local_time(self) -> None:
        _, hours = weather.parse_forecast(kmz(KML))
        hourly = weather.hourly_json(hours)
        self.assertEqual(hourly[0], {"time": "2026-11-11T23:00", "temp": 10, "code": 61, "rain": 40, "night": True})

    def test_daily_by_local_day(self) -> None:
        hours = [
            weather.Hour(utc("2026-11-11T21:00"), 10.4, 3, 20, True),
            weather.Hour(utc("2026-11-11T22:00"), 4.6, 61, None, True),
            weather.Hour(utc("2026-11-11T23:00"), 2, 3, None, True),
        ]
        daily = weather.daily_json(hours)
        self.assertEqual(daily["2026-11-11"], {"code": 61, "max": 10, "min": 5, "rain": 20})
        self.assertEqual(daily["2026-11-12"], {"code": 3, "max": 2, "min": 2, "rain": None})


class Report(unittest.TestCase):
    def test_newest_with_a_temperature(self) -> None:
        report = weather.parse_report(REPORT)
        assert report is not None
        at, values = report
        self.assertEqual(at, utc("2026-11-11T17:00"))
        self.assertEqual(values["temp"], 8.2)
        self.assertEqual(values["visibility"], 6.1)
        self.assertEqual(values["code"], 45)
        self.assertEqual(values["windSpeed"], None)

    def test_without_any_temperature(self) -> None:
        headers_and_empty_row = "".join(REPORT.splitlines(keepends=True)[:4])
        self.assertIsNone(weather.parse_report(headers_and_empty_row))

    def test_codes(self) -> None:
        self.assertEqual(weather.report_code(8, 100), 63)
        # Gusts and no report say nothing about the sky: the cloud cover does
        self.assertEqual(weather.report_code(31, 10), 0)
        self.assertEqual(weather.report_code(None, 50), 2)
        self.assertEqual(weather.report_code(None, 80), 3)
        self.assertIsNone(weather.report_code(None, None))

    def test_listing(self) -> None:
        changed = weather.parse_reports_listing(LISTING)
        self.assertEqual(changed["10637"], utc("2026-11-11T17:43"))
        self.assertEqual(set(changed), {"10637", "10641"})

    def test_only_recent_stations_within_reach(self) -> None:
        stations = weather.parse_catalogue(CATALOGUE)
        nearest = weather.by_distance(stations, 50.1, 8.7)
        changed = {"10637": utc("2026-11-11T17:43"), "E564": utc("2026-11-11T17:43")}
        with mock.patch.object(weather.time, "time", return_value=utc("2026-11-11T18:00").timestamp()):
            nearby = weather.reporting_nearby(nearest, changed)
        self.assertEqual([s.id for _, s in nearby], ["10637"])

    def test_night_from_the_forecast(self) -> None:
        hours = [weather.Hour(utc("2026-11-11T17:00"), 8, 3, None, True)]
        self.assertTrue(weather.is_night_at(utc("2026-11-11T17:00"), hours))
        self.assertTrue(weather.is_night_at(utc("2026-11-11T12:00"), hours))
        self.assertFalse(weather.is_night_at(utc("2026-11-11T12:00"), []))


if __name__ == "__main__":
    unittest.main()
