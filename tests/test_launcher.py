# pyright: strict
import tempfile
import unittest
from pathlib import Path

from helpers import load

launcher = load("config/quickshell/menus/launcher.py")

ECB = """<?xml version="1.0" encoding="UTF-8"?>
<gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
  <Cube><Cube time="2026-10-28"><Cube currency="USD" rate="1.25"/><Cube currency="GBP" rate="0.8"/></Cube></Cube>
</gesmes:Envelope>"""


class SshHosts(unittest.TestCase):
    def test_hosts_with_includes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ssh = Path(tmp)
            (ssh / "config").write_text("Include config.local\n\nHost *\n    ServerAliveInterval 60\n")
            (ssh / "config.local").write_text(
                "Host server web\n"
                "    HostName server.example.org\n"
                "    User admin\n"
                "Host box # a comment\n"
                "    HostName = 10.0.0.2\n"
                "Host *.example.org !skip\n"
                "Match host other\n"
                "    User nobody\n"
                "Host server\n"
                "    User other\n"
            )
            self.assertEqual(
                launcher.ssh_hosts(ssh / "config"),
                [
                    {"host": "server", "detail": "admin@server.example.org"},
                    {"host": "web", "detail": "admin@server.example.org"},
                    {"host": "box", "detail": "10.0.0.2"},
                ],
            )

    def test_missing_config(self) -> None:
        self.assertEqual(launcher.ssh_hosts(Path("/nonexistent/config")), [])


class Convert(unittest.TestCase):
    def convert(self, query: str) -> str | None:
        result = launcher.convert(query, launcher.parse_rates(ECB))
        return str(result["text"]) if result else None

    def test_units(self) -> None:
        self.assertEqual(self.convert("10 km in mi"), "6.21371 mi")
        self.assertEqual(self.convert("10 in in cm"), "25.4 cm")
        self.assertEqual(self.convert("1,5 kg to lb"), "3.30693 lb")
        self.assertEqual(self.convert("1 GiB in MB"), "1073.74 MB")
        self.assertEqual(self.convert("100 Mbit = MB"), "12.5 MB")
        self.assertEqual(self.convert("2 h as min"), "120 min")
        self.assertEqual(self.convert("1 m3 in l"), "1000 l")

    def test_temperatures(self) -> None:
        self.assertEqual(self.convert("20 c to f"), "68 °F")
        self.assertEqual(self.convert("0 K in °C"), "-273.15 °C")

    def test_currencies(self) -> None:
        self.assertEqual(self.convert("100 usd in eur"), "80.00 EUR")
        self.assertEqual(self.convert("10 € in £"), "8.00 GBP")
        self.assertEqual(self.convert("100 xyz in eur"), None)

    def test_rates_are_asked_for(self) -> None:
        with self.assertRaises(launcher.RatesMissing):
            launcher.convert("5 usd in eur", None)
        # Units don't need them
        self.assertIsNotNone(launcher.convert("5 m in ft", None))

    def test_not_a_conversion(self) -> None:
        self.assertIsNone(self.convert("firefox"))
        self.assertIsNone(self.convert("10 km in kg"))
        self.assertIsNone(self.convert("2 in 1"))

    def test_rates(self) -> None:
        rates = launcher.parse_rates(ECB)
        self.assertEqual(rates.date, "2026-10-28")
        self.assertEqual(rates.rates, {"EUR": 1.0, "USD": 1.25, "GBP": 0.8})

    def test_number(self) -> None:
        self.assertEqual(launcher.number(6.213711922), "6.21371")
        self.assertEqual(launcher.number(1609.344), "1609.34")
        self.assertEqual(launcher.number(0.000123456), "0.000123456")
        self.assertEqual(launcher.number(120.0), "120")
        self.assertEqual(launcher.number(0), "0")
        self.assertEqual(launcher.number(1.5e20), "1.50000e+20")


class Files(unittest.TestCase):
    def test_rank(self) -> None:
        paths = ["/h/a/b/notes-old.md", "/h/x/notes", "/h/notes.md", "/h/my-notes.txt"]
        self.assertEqual(
            launcher.rank_files(paths, "notes"),
            ["/h/x/notes", "/h/notes.md", "/h/a/b/notes-old.md", "/h/my-notes.txt"],
        )

    def test_short_dir(self) -> None:
        home = launcher.HOME
        self.assertEqual(launcher.short_dir(home / "a.txt"), "~")
        self.assertEqual(launcher.short_dir(home / "Documents/a.txt"), "~/Documents")
        self.assertEqual(launcher.short_dir(Path("/etc/hosts")), "/etc")


if __name__ == "__main__":
    unittest.main()
