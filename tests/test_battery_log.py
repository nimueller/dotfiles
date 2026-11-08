# pyright: strict
import tempfile
import time
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

from helpers import load

battery_log = load("config/quickshell/menus/battery-log.py")


def line(sample_time: int) -> str:
    return f"{sample_time},50,10.000,5.00,d"


class InOrder(unittest.TestCase):
    def test_samples_in_order_are_kept(self) -> None:
        lines = [line(60), line(120), line(180)]
        self.assertEqual(battery_log.in_order(lines), lines)

    def test_samples_a_clock_ahead_stamped_are_dropped(self) -> None:
        # Booted at 100 with the clock an hour ahead, corrected after two samples
        lines = [line(60), line(3700), line(3760), line(160), line(220)]
        self.assertEqual(battery_log.in_order(lines), [line(60), line(160), line(220)])

    def test_repeated_samples_are_kept_once(self) -> None:
        lines = [line(60), line(60), line(120), line(120)]
        self.assertEqual(battery_log.in_order(lines), [line(60), line(120)])


class CleanSamples(unittest.TestCase):
    def test_old_and_out_of_order_samples_are_removed(self) -> None:
        now = int(time.time())
        old = now - battery_log.KEEP_DAYS * battery_log.DAY - 60
        lines = [line(old), line(now - 120), line(now + 3600), line(now - 60)]
        with tempfile.TemporaryDirectory() as folder:
            samples = Path(folder) / "samples.csv"
            samples.write_text("".join(f"{text}\n" for text in lines))
            with mock.patch.object(battery_log, "SAMPLES", samples):
                battery_log.clean_samples()
                self.assertEqual(battery_log.last_sample_time(), now - 60)
            self.assertEqual(samples.read_text(), f"{line(now - 120)}\n{line(now - 60)}\n")


class CountCpu(unittest.TestCase):
    def log_with_last_sample(self, sample_time: float) -> Any:
        # Without __init__: that takes the lock and reads the real files
        log = battery_log.BatteryLog.__new__(battery_log.BatteryLog)
        log.apps = {}
        log.dirty = False
        log.last = battery_log.Sample(sample_time, {})
        return log

    def test_counts_the_time_since_the_last_sample(self) -> None:
        log = self.log_with_last_sample(3600)
        log.count_cpu(3660, {})
        self.assertEqual(log.apps, {"3600": {"seconds": 60, "apps": {}}})

    def test_nothing_when_the_clock_went_back(self) -> None:
        log = self.log_with_last_sample(7200)
        log.count_cpu(3660, {})
        self.assertEqual(log.apps, {})

    def test_nothing_after_a_suspend(self) -> None:
        log = self.log_with_last_sample(3600)
        log.count_cpu(3600 + battery_log.GAP + 1, {})
        self.assertEqual(log.apps, {})


if __name__ == "__main__":
    unittest.main()
