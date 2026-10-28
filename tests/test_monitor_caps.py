# pyright: strict
import unittest

from helpers import load

monitor_caps = load("config/quickshell/menus/monitor-caps.py")

# Shortened output of `modetest -c`
MODETEST = """\
Connectors:
id	encoder	status		name		size (mm)	modes	encoders
107	106	connected	DP-1          	600x340		42	106
  props:
	8 vrr_capable:
		flags: immutable range
		values: 0 1
		value: 1
115	0	disconnected	HDMI-A-1          	0x0		0	114
  props:
	8 vrr_capable:
		flags: immutable range
		values: 0 1
		value: 0
"""


class Modetest(unittest.TestCase):
    def test_vrr_by_connector(self) -> None:
        self.assertEqual(monitor_caps.parse_modetest(MODETEST), {"DP-1": "1", "HDMI-A-1": "0"})

    def test_nothing_without_output(self) -> None:
        self.assertEqual(monitor_caps.parse_modetest(""), {})


if __name__ == "__main__":
    unittest.main()
