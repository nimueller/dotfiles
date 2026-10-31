# pyright: strict
import queue
import unittest
from unittest import mock

from helpers import load

rotate = load("pkgs/scripts/auto-rotate.py")


class Sensor(unittest.TestCase):
    def test_without_monitor_sensor_the_loop_ends(self) -> None:
        events: queue.Queue[str | None] = queue.Queue()
        with mock.patch.object(rotate.subprocess, "Popen", side_effect=FileNotFoundError):
            rotate.watch_sensor(events)
        self.assertIsNone(events.get_nowait())


class Orientation(unittest.TestCase):
    def test_monitor_sensor_lines(self) -> None:
        self.assertEqual(rotate.orientation("=== Has accelerometer (orientation: normal, tilt: vertical)"), "normal")
        self.assertEqual(rotate.orientation("    Accelerometer orientation changed: left-up"), "left-up")
        self.assertEqual(rotate.orientation("    Accelerometer orientation changed: bottom-up\n"), "bottom-up")

    def test_flat_and_other_lines(self) -> None:
        self.assertIsNone(rotate.orientation("    Accelerometer orientation changed: undefined"))
        self.assertIsNone(rotate.orientation("    Tilt changed: tilted-down"))
        self.assertIsNone(rotate.orientation("+++ iio-sensor-proxy appeared"))


class Turn(unittest.TestCase):
    def test_turns_from_the_base(self) -> None:
        self.assertEqual(rotate.turn(0, rotate.TRANSFORMS["left-up"]), 1)
        self.assertEqual(rotate.turn(3, rotate.TRANSFORMS["left-up"]), 0)
        self.assertEqual(rotate.turn(1, rotate.TRANSFORMS["bottom-up"]), 3)

    def test_flipped_stays_flipped(self) -> None:
        self.assertEqual(rotate.turn(4, 1), 5)
        self.assertEqual(rotate.turn(7, 1), 4)


class Rule(unittest.TestCase):
    def test_monitor_as_it_is_with_the_transform(self) -> None:
        monitor: dict[str, object] = {
            "description": 'Panel "A"',
            "width": 2880,
            "height": 1920,
            "refreshRate": 120.0,
            "x": 0,
            "y": 0,
            "scale": 2,
        }
        self.assertEqual(
            rotate.monitor_rule(monitor, 1),
            'hl.monitor({ output = "desc:Panel \\"A\\"", mode = "2880x1920@120.0", '
            'position = "0x0", scale = 2, transform = 1 })',
        )


if __name__ == "__main__":
    unittest.main()
