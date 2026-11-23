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


class ReadBattery(unittest.TestCase):
    def read(self, files: dict[str, str]) -> Any:
        with tempfile.TemporaryDirectory() as folder:
            for name, value in files.items():
                (Path(folder) / name).write_text(f"{value}\n")
            return battery_log.read_battery(Path(folder))

    def test_full_capacity_from_energy_full(self) -> None:
        sample = self.read(
            {
                "energy_now": "18470000",
                "power_now": "29870000",
                "energy_full": "26760000",
                "capacity": "69",
                "status": "Charging",
            }
        )
        self.assertEqual(sample.full, 26.76)

    def test_full_capacity_from_charge_full(self) -> None:
        sample = self.read(
            {
                "charge_now": "2000000",
                "current_now": "1000000",
                "charge_full": "4000000",
                "voltage_now": "7500000",
                "capacity": "50",
                "status": "Discharging",
            }
        )
        self.assertEqual(sample.full, 30.0)

    def test_no_full_capacity(self) -> None:
        sample = self.read({"energy_now": "18470000", "power_now": "0", "capacity": "69", "status": "Full"})
        self.assertIsNone(sample.full)


class SampleLine(unittest.TestCase):
    def test_full_capacity_is_the_sixth_field(self) -> None:
        sample = battery_log.Battery(percent=69, energy=18.47, power=29.87, state="c", full=26.76)
        self.assertEqual(battery_log.sample_line(1795454280, sample), "1795454280,69,18.470,29.87,c,26.760\n")

    def test_full_capacity_empty_when_unknown(self) -> None:
        sample = battery_log.Battery(percent=69, energy=18.47, power=29.87, state="c", full=None)
        self.assertEqual(battery_log.sample_line(1795454280, sample), "1795454280,69,18.470,29.87,c,\n")

    def test_old_and_new_lines_keep_their_order(self) -> None:
        lines = [line(60), f"{line(120)},26.760"]
        self.assertEqual(battery_log.in_order(lines), lines)


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
