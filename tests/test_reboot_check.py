# pyright: strict
import tempfile
import unittest
from pathlib import Path

from helpers import load

reboot_check = load("pkgs/scripts/reboot-check.py")

# 2026-11-01T12:00:00+0100
BOOT = 1793530800.0

LOG = """\
[2026-10-31T10:00:00+0100] [PACMAN] Running 'pacman -Syu'
[2026-10-31T10:00:05+0100] [ALPM] upgraded systemd (258.1-1 -> 258.2-1)
[2026-11-01T13:00:00+0100] [PACMAN] Running 'pacman -Syu'
[2026-11-01T13:00:05+0100] [ALPM] upgraded firefox (140.0-1 -> 141.0-1)
[2026-11-01T13:00:06+0100] [ALPM] upgraded linux-firmware-intel (20261001-1 -> 20261101-1)
[2026-11-01T13:00:07+0100] [ALPM] installed glibc-locales (2.42-1)
[2026-11-01T13:00:08+0100] [ALPM] reinstalled firefox (141.0-1)
[2026-11-01T13:00:09+0100] [ALPM-SCRIPTLET] upgraded nothing
[2019-01-01 10:00] [ALPM] upgraded glibc (2.28-1 -> 2.28-2)
"""


class BootTime(unittest.TestCase):
    def test_btime_line(self) -> None:
        self.assertEqual(reboot_check.boot_time("cpu 1 2 3\nbtime 1793530800\nprocesses 9\n"), BOOT)

    def test_missing(self) -> None:
        self.assertIsNone(reboot_check.boot_time(""))


class ChangedSince(unittest.TestCase):
    def test_only_after_boot_each_once(self) -> None:
        self.assertEqual(
            reboot_check.changed_since(LOG, BOOT),
            ["firefox", "linux-firmware-intel", "glibc-locales"],
        )


class Verdict(unittest.TestCase):
    def test_now_wins(self) -> None:
        result = reboot_check.verdict(["the running kernel 1 was replaced"], ["systemd"])
        self.assertEqual(result.urgency, "now")

    def test_later_lists_the_packages(self) -> None:
        result = reboot_check.verdict([], ["firefox", "linux-firmware-intel", "glibc-locales", "systemd"])
        self.assertEqual(result.urgency, "later")
        self.assertEqual(result.reasons, ["linux-firmware-intel", "systemd"])

    def test_none(self) -> None:
        self.assertEqual(reboot_check.verdict([], ["firefox"]).urgency, "none")


class NowReasons(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.modules = Path(directory.name)
        (self.modules / "7.2.11-arch1-1").mkdir()

    def test_running_kernel_present(self) -> None:
        self.assertEqual(reboot_check.now_reasons("7.2.11-arch1-1", self.modules, None, None), [])

    def test_running_kernel_replaced(self) -> None:
        reasons = reboot_check.now_reasons("7.2.10-arch1-1", self.modules, None, None)
        self.assertEqual(len(reasons), 1)

    def test_nvidia_mismatch(self) -> None:
        reasons = reboot_check.now_reasons("7.2.11-arch1-1", self.modules, "615.78.08", "620.10.02")
        self.assertEqual(len(reasons), 1)

    def test_nvidia_matches(self) -> None:
        reasons = reboot_check.now_reasons("7.2.11-arch1-1", self.modules, "615.78.08", "615.78.08")
        self.assertEqual(reasons, [])


class Message(unittest.TestCase):
    def test_plain_without_colors(self) -> None:
        result = reboot_check.Verdict("later", ["systemd"])
        self.assertEqual(reboot_check.message(result, False), "Reboot when convenient, updated since boot: systemd")


if __name__ == "__main__":
    unittest.main()
