# pyright: strict
import unittest

from helpers import load

backlight = load("config/quickshell/menus/backlight.py")


class Scale(unittest.TestCase):
    def test_linear_backlight_is_bent(self) -> None:
        # Half the percent is a sixteenth of the power with exponent 4
        self.assertEqual(backlight.to_raw(50, 1600, 4), 100)
        self.assertEqual(backlight.to_percent(100, 1600, 4), 50)

    def test_non_linear_backlight_as_it_is(self) -> None:
        self.assertEqual(backlight.to_raw(50, 1000, 1), 500)
        self.assertEqual(backlight.to_percent(500, 1000, 1), 50)

    def test_never_below_the_minimum(self) -> None:
        self.assertEqual(backlight.to_raw(0, 1000, 4), 20)
        self.assertEqual(backlight.to_raw(-10, 1000, 1), 20)

    def test_clamped_at_full(self) -> None:
        self.assertEqual(backlight.to_raw(150, 1000, 4), 1000)

    def test_round_trip(self) -> None:
        for percent in range(40, 101):
            self.assertEqual(backlight.to_percent(backlight.to_raw(percent, 96000, 4), 96000, 4), percent)


if __name__ == "__main__":
    unittest.main()
