# pyright: strict
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from helpers import load

log = load("config/quickshell/menus/device-battery-log.py")

HOUR = 3600
DAY = 86400
NOW = 1_800_000_000.0


def sample(hours_ago: float, percent: float, state: str = "d", key: str = "Mouse") -> object:
    return log.Sample(NOW - hours_ago * HOUR, key, percent, state)


class Samples(unittest.TestCase):
    def test_round_trip(self) -> None:
        samples = [sample(2, 80), sample(1, 79.5, "c", "Keyboard, wireless")]
        text = log.format_samples(samples)
        self.assertEqual(log.parse_samples(text), [log.Sample(NOW - 2 * HOUR, "Mouse", 80, "d"), samples[1]])

    def test_broken_lines_are_left_out(self) -> None:
        text = "1800000000,d,80,Mouse\n\0\0\0\nnot,a,number,Mouse\n"
        self.assertEqual(log.parse_samples(text), [log.Sample(NOW, "Mouse", 80, "d")])

    def test_parse_devices(self) -> None:
        text = '[{"key": "Mouse", "percent": 49, "state": "draining"}]'
        self.assertEqual(log.parse_devices(text, NOW), [log.Sample(NOW, "Mouse", 49, "d")])

    def test_unknown_state_is_an_error(self) -> None:
        with self.assertRaises(KeyError):
            log.parse_devices('[{"key": "Mouse", "percent": 49, "state": "flying"}]', NOW)

    def test_only_changes_are_new(self) -> None:
        history = [sample(5, 80), sample(1, 79)]
        devices = [sample(0, 79), sample(0, 50, "c", "Keyboard")]
        self.assertEqual(log.new_samples(history, devices), [devices[1]])

    def test_state_change_is_new(self) -> None:
        history = [sample(1, 79)]
        devices = [sample(0, 79, "c")]
        self.assertEqual(log.new_samples(history, devices), devices)

    def test_old_samples_go(self) -> None:
        old = sample(61 * 24, 90)
        kept = sample(59 * 24, 80)
        self.assertEqual(log.recent([old, kept], NOW), [kept])


class Estimate(unittest.TestCase):
    def test_pace_since_unplugged(self) -> None:
        samples = [sample(30, 90, "c"), sample(24, 100), sample(12, 90), sample(1, 76)]
        estimate = log.estimate(samples, NOW)
        # 24 % in 24 hours: 1 % an hour, 76 hours left
        self.assertEqual(estimate.measured, "now")
        self.assertAlmostEqual(estimate.left, 76 * HOUR)
        self.assertAlmostEqual(estimate.pace * HOUR, 1)

    def test_not_while_charging(self) -> None:
        samples = [sample(24, 100), sample(12, 90), sample(1, 76, "c")]
        self.assertIsNone(log.estimate(samples, NOW))

    def test_not_while_unknown(self) -> None:
        samples = [sample(24, 100), sample(1, 76, "u")]
        self.assertIsNone(log.estimate(samples, NOW))

    def test_too_little_yet(self) -> None:
        samples = [sample(2, 100), sample(1, 95)]
        self.assertIsNone(log.estimate(samples, NOW))

    def test_too_little_used_yet(self) -> None:
        samples = [sample(10, 100), sample(1, 99)]
        self.assertIsNone(log.estimate(samples, NOW))

    def test_pace_of_the_charge_before(self) -> None:
        before = [sample(100, 100), sample(52, 52)]  # 1 % an hour
        samples = [*before, sample(50, 60, "c"), sample(1, 100)]
        estimate = log.estimate(samples, NOW)
        self.assertEqual(estimate.measured, "before")
        self.assertAlmostEqual(estimate.left, 100 * HOUR)

    def test_rise_is_a_charge_elsewhere(self) -> None:
        samples = [sample(100, 100), sample(20, 20), sample(10, 90), sample(0, 80)]
        estimate = log.estimate(samples, NOW)
        # Since the rise to 90: 10 % in 10 hours
        self.assertEqual(estimate.measured, "now")
        self.assertAlmostEqual(estimate.pace * HOUR, 1)

    def test_small_rise_is_the_same_charge(self) -> None:
        samples = [sample(20, 100), sample(10, 88), sample(5, 90), sample(0, 80)]
        estimate = log.estimate(samples, NOW)
        self.assertAlmostEqual(estimate.pace * HOUR, 1)

    def test_estimates_by_key(self) -> None:
        samples = [sample(24, 100), sample(1, 76), sample(24, 100, key="Keyboard")]
        found = log.estimates(samples, ["Mouse", "Keyboard", "Headset"], NOW)
        self.assertEqual(list(found), ["Mouse"])


class Record(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory()
        state = Path(self.folder.name)
        patches = [
            mock.patch.object(log, "STATE", state),
            mock.patch.object(log, "SAMPLES", state / "samples.csv"),
            mock.patch.object(log, "LOCK", state / "lock"),
        ]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        self.samples = state / "samples.csv"

    def tearDown(self) -> None:
        self.folder.cleanup()

    def test_appends_changes(self) -> None:
        log.record([log.Sample(NOW, "Mouse", 80, "d")], NOW)
        log.record([log.Sample(NOW + 60, "Mouse", 80, "d")], NOW + 60)
        log.record([log.Sample(NOW + 120, "Mouse", 79, "d")], NOW + 120)
        self.assertEqual(self.samples.read_text(), "1800000000,d,80,Mouse\n1800000120,d,79,Mouse\n")

    def test_drops_old_samples(self) -> None:
        self.samples.write_text(f"{int(NOW - 61 * DAY)},d,90,Mouse\n{int(NOW - DAY)},d,85,Mouse\n")
        log.record([log.Sample(NOW, "Mouse", 80, "d")], NOW)
        self.assertEqual(self.samples.read_text(), f"{int(NOW - DAY)},d,85,Mouse\n1800000000,d,80,Mouse\n")


if __name__ == "__main__":
    unittest.main()
