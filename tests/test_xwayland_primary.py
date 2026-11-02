# pyright: strict
import unittest

from helpers import load

primary = load("config/quickshell/menus/xwayland-primary.py")

LISTING = """Screen 0: minimum 16 x 16, current 5760 x 2160, maximum 32767 x 32767
DP-1 connected primary 3840x2160+0+0 (normal left inverted right x axis y axis) 620mm x 340mm
   3840x2160     59.98*+
DP-2 connected 1920x1080+3840+0 (normal left inverted right x axis y axis) 530mm x 300mm
"""


class MainDescription(unittest.TestCase):
    def test_the_monitor_marked_main(self) -> None:
        lua = '-- settings: {"monitors":[{"desc":"a","main":false},{"desc":"b","main":true}]}\nhl.env("A", "b")\n'
        self.assertEqual(primary.main_description(lua), "b")

    def test_none_marked(self) -> None:
        self.assertIsNone(primary.main_description('-- settings: {"monitors":[{"desc":"a"}]}'))

    def test_no_monitors_saved(self) -> None:
        self.assertIsNone(primary.main_description('-- settings: {"env":[]}'))

    def test_no_settings_line(self) -> None:
        self.assertIsNone(primary.main_description('hl.env("A", "b")\n'))

    def test_broken_settings_line(self) -> None:
        self.assertIsNone(primary.main_description("-- settings: {"))


class OutputName(unittest.TestCase):
    def test_port_of_the_description(self) -> None:
        monitors = [{"name": "DP-2", "description": "a"}, {"name": "DP-1", "description": "b"}]
        self.assertEqual(primary.output_name(monitors, "b"), "DP-1")

    def test_monitor_not_there(self) -> None:
        self.assertIsNone(primary.output_name([{"name": "DP-2", "description": "a"}], "b"))


class IsPrimary(unittest.TestCase):
    def test_primary(self) -> None:
        self.assertTrue(primary.is_primary(LISTING, "DP-1"))

    def test_other_output(self) -> None:
        self.assertFalse(primary.is_primary(LISTING, "DP-2"))

    def test_output_not_there_yet(self) -> None:
        self.assertFalse(primary.is_primary(LISTING, "HDMI-A-1"))

    def test_name_is_no_prefix(self) -> None:
        self.assertFalse(primary.is_primary(LISTING.replace("DP-1 ", "DP-10 "), "DP-1"))


if __name__ == "__main__":
    unittest.main()
