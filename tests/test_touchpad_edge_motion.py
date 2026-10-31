# pyright: strict
import unittest
from typing import Any

from helpers import load

edge = load("system/touchpad-edge-motion.py")

SIZE = 1000
UNITS = 20  # per mm, so 100 for the zone of 5 mm and 26 for a tap
MIDDLE = 500


class Pad:
    """A touchpad: one report per call, like the kernel sends them."""

    def __init__(self) -> None:
        self.tracker: Any = edge.Tracker(SIZE, SIZE, UNITS)
        self.clock = 100.0

    def send(self, *events: tuple[int, int, int]) -> None:
        for event in events:
            self.tracker.event(*event, self.clock)
        self.tracker.event(edge.EV_SYN, edge.SYN_REPORT, 0, self.clock)

    def wait(self, seconds: float) -> None:
        self.clock += seconds

    def tap(self, x: int, y: int, seconds: float = 0.07) -> None:
        self.touch(x, y)
        self.wait(seconds)
        self.lift()

    def touch(self, x: int, y: int, slot: int = 0) -> None:
        self.send(
            (edge.EV_ABS, edge.ABS_MT_SLOT, slot),
            (edge.EV_ABS, edge.ABS_MT_TRACKING_ID, slot + 1),
            (edge.EV_ABS, edge.ABS_MT_POSITION_X, x),
            (edge.EV_ABS, edge.ABS_MT_POSITION_Y, y),
        )

    def lift(self, slot: int = 0) -> None:
        self.send((edge.EV_ABS, edge.ABS_MT_SLOT, slot), (edge.EV_ABS, edge.ABS_MT_TRACKING_ID, -1))

    def slide(self, x: int, y: int, slot: int = 0) -> None:
        self.send(
            (edge.EV_ABS, edge.ABS_MT_SLOT, slot),
            (edge.EV_ABS, edge.ABS_MT_POSITION_X, x),
            (edge.EV_ABS, edge.ABS_MT_POSITION_Y, y),
        )

    def press(self, down: bool = True) -> None:
        self.send((edge.EV_KEY, edge.BTN_LEFT, int(down)))

    def direction(self) -> tuple[int, int]:
        return self.tracker.direction()


class Drag(unittest.TestCase):
    def setUp(self) -> None:
        self.pad = Pad()
        self.pad.touch(MIDDLE, MIDDLE)
        self.pad.press()

    def test_nothing_in_the_middle(self) -> None:
        self.assertEqual(self.pad.direction(), (0, 0))

    def test_every_edge(self) -> None:
        for x, y, expected in (
            (950, MIDDLE, (1, 0)),
            (50, MIDDLE, (-1, 0)),
            (MIDDLE, 950, (0, 1)),
            (MIDDLE, 50, (0, -1)),
        ):
            self.pad.slide(x, y)
            self.assertEqual(self.pad.direction(), expected)
            self.pad.slide(MIDDLE, MIDDLE)
            self.assertEqual(self.pad.direction(), (0, 0))

    def test_corner_goes_diagonally(self) -> None:
        self.pad.slide(950, 50)
        self.assertEqual(self.pad.direction(), (1, -1))

    def test_stops_when_released(self) -> None:
        self.pad.slide(950, MIDDLE)
        self.pad.press(False)
        self.assertEqual(self.pad.direction(), (0, 0))

    def test_stops_when_lifted(self) -> None:
        self.pad.slide(950, MIDDLE)
        self.pad.lift()
        self.assertEqual(self.pad.direction(), (0, 0))

    def test_stops_when_events_got_lost(self) -> None:
        self.pad.slide(950, MIDDLE)
        self.pad.tracker.event(edge.EV_SYN, edge.SYN_DROPPED, 0)
        self.assertEqual(self.pad.direction(), (0, 0))


class Started(unittest.TestCase):
    def test_no_drag_without_the_button(self) -> None:
        pad = Pad()
        pad.touch(MIDDLE, MIDDLE)
        pad.slide(950, MIDDLE)
        self.assertEqual(pad.direction(), (0, 0))

    def test_click_in_the_corner_stays_put(self) -> None:
        pad = Pad()
        pad.touch(950, 950)
        pad.press()
        self.assertEqual(pad.direction(), (0, 0))

    def test_finger_at_the_edge_counts_once_it_came_back(self) -> None:
        pad = Pad()
        pad.touch(950, MIDDLE)
        pad.press()
        pad.slide(MIDDLE, MIDDLE)
        pad.slide(950, MIDDLE)
        self.assertEqual(pad.direction(), (1, 0))

    def test_only_the_edge_it_started_at_is_ignored(self) -> None:
        pad = Pad()
        pad.touch(MIDDLE, 950)
        pad.press()
        pad.slide(950, 950)
        self.assertEqual(pad.direction(), (1, 0))

    def test_thumb_on_the_button_with_a_finger_dragging(self) -> None:
        pad = Pad()
        pad.touch(MIDDLE, 950, slot=0)
        pad.press()
        pad.touch(MIDDLE, MIDDLE, slot=1)
        self.assertEqual(pad.direction(), (0, 0))
        pad.slide(950, MIDDLE, slot=1)
        self.assertEqual(pad.direction(), (1, 0))

    def test_touch_keeps_a_coordinate_the_kernel_doesnt_repeat(self) -> None:
        pad = Pad()
        pad.touch(MIDDLE, 950)
        pad.lift()
        pad.send(
            (edge.EV_ABS, edge.ABS_MT_TRACKING_ID, 2),
            (edge.EV_ABS, edge.ABS_MT_POSITION_X, 300),
        )
        pad.press()
        self.assertEqual(pad.direction(), (0, 0))
        pad.slide(300, MIDDLE)
        pad.slide(300, 950)
        self.assertEqual(pad.direction(), (0, 1))


class TappedDrag(unittest.TestCase):
    def setUp(self) -> None:
        self.pad = Pad()

    def drag(self) -> None:
        """The timing as measured on a Surface Pro X"""
        self.pad.tap(MIDDLE, MIDDLE)
        self.pad.wait(0.07)
        self.pad.touch(MIDDLE, MIDDLE)
        self.pad.slide(950, MIDDLE)

    def test_goes_on_at_the_edge(self) -> None:
        self.drag()
        self.assertEqual(self.pad.direction(), (1, 0))

    def test_ends_with_the_finger(self) -> None:
        self.drag()
        self.pad.lift()
        self.assertEqual(self.pad.direction(), (0, 0))

    def test_moving_after_a_lift_isnt_a_drag(self) -> None:
        self.drag()
        self.pad.lift()
        self.pad.wait(0.07)
        self.pad.touch(MIDDLE, MIDDLE)
        self.pad.slide(950, MIDDLE)
        self.assertEqual(self.pad.direction(), (0, 0))

    def test_tap_long_ago_doesnt_count(self) -> None:
        self.pad.tap(MIDDLE, MIDDLE)
        self.pad.wait(1)
        self.pad.touch(MIDDLE, MIDDLE)
        self.pad.slide(950, MIDDLE)
        self.assertEqual(self.pad.direction(), (0, 0))

    def test_slow_touch_isnt_a_tap(self) -> None:
        self.pad.tap(MIDDLE, MIDDLE, seconds=0.5)
        self.pad.wait(0.07)
        self.pad.touch(MIDDLE, MIDDLE)
        self.pad.slide(950, MIDDLE)
        self.assertEqual(self.pad.direction(), (0, 0))

    def test_short_swipe_isnt_a_tap(self) -> None:
        self.pad.touch(MIDDLE, MIDDLE)
        self.pad.slide(MIDDLE + 100, MIDDLE)
        self.pad.wait(0.07)
        self.pad.lift()
        self.pad.wait(0.07)
        self.pad.touch(MIDDLE, MIDDLE)
        self.pad.slide(950, MIDDLE)
        self.assertEqual(self.pad.direction(), (0, 0))

    def test_two_finger_tap_doesnt_count(self) -> None:
        self.pad.touch(MIDDLE, MIDDLE, slot=0)
        self.pad.touch(MIDDLE + 200, MIDDLE, slot=1)
        self.pad.wait(0.07)
        self.pad.lift(slot=1)
        self.pad.lift(slot=0)
        self.pad.wait(0.07)
        self.pad.touch(MIDDLE, MIDDLE)
        self.pad.slide(950, MIDDLE)
        self.assertEqual(self.pad.direction(), (0, 0))

    def test_touch_at_the_edge_waits_until_it_left(self) -> None:
        self.pad.tap(950, MIDDLE)
        self.pad.wait(0.07)
        self.pad.touch(950, MIDDLE)
        self.assertEqual(self.pad.direction(), (0, 0))
        self.pad.slide(MIDDLE, MIDDLE)
        self.pad.slide(950, MIDDLE)
        self.assertEqual(self.pad.direction(), (1, 0))


if __name__ == "__main__":
    unittest.main()
