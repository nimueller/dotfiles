# pyright: strict
import tempfile
import unittest
from pathlib import Path

from helpers import load

charging = load("config/quickshell/menus/charging-batteries.py")


def write_supply(root: Path, **attributes: str) -> Path:
    """A power supply's sysfs folder with these attributes as files"""
    supply = root / "hidpp_battery_0"
    supply.mkdir()
    for name, value in attributes.items():
        (supply / name).write_text(value + "\n")
    return supply


CHARGING = {"type": "Battery", "scope": "Device", "online": "0", "status": "Charging", "capacity": "40"}


class HiddenWhileCharging(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory()
        self.root = Path(self.folder.name)

    def tearDown(self) -> None:
        self.folder.cleanup()

    def test_charging_offline_device_battery(self) -> None:
        supply = write_supply(self.root, **CHARGING)
        self.assertTrue(charging.is_hidden_while_charging(supply))

    def test_out_of_reach_is_unknown(self) -> None:
        supply = write_supply(self.root, **(CHARGING | {"status": "Unknown"}))
        self.assertFalse(charging.is_hidden_while_charging(supply))

    def test_online_is_upowers(self) -> None:
        supply = write_supply(self.root, **(CHARGING | {"online": "1", "status": "Discharging"}))
        self.assertFalse(charging.is_hidden_while_charging(supply))

    def test_system_battery_is_not_a_device(self) -> None:
        supply = write_supply(self.root, **(CHARGING | {"scope": "System"}))
        self.assertFalse(charging.is_hidden_while_charging(supply))

    def test_missing_attributes(self) -> None:
        supply = write_supply(self.root, type="Battery")
        self.assertFalse(charging.is_hidden_while_charging(supply))

    def test_model_name_first(self) -> None:
        supply = write_supply(self.root, model_name="Device D1")
        self.assertEqual(charging.model_of(supply, []), "Device D1")

    def test_input_name_without_model_name(self) -> None:
        supply = write_supply(self.root)
        node = self.root / "input21"
        node.mkdir()
        (node / "name").write_text("Wireless Mouse\n")
        self.assertEqual(charging.model_of(supply, [node]), "Wireless Mouse")


class Kind(unittest.TestCase):
    def test_keyboard_before_mouse(self) -> None:
        inputs = [{"ID_INPUT_MOUSE": "1"}, {"ID_INPUT_KEYBOARD": "1"}]
        self.assertEqual(charging.kind_of(inputs), "keyboard")

    def test_mouse(self) -> None:
        self.assertEqual(charging.kind_of([{"ID_INPUT": "1", "ID_INPUT_MOUSE": "1"}]), "mouse")

    def test_unknown(self) -> None:
        self.assertEqual(charging.kind_of([{"ID_INPUT": "1"}]), "device")
        self.assertEqual(charging.kind_of([]), "device")


class UPowerVersion(unittest.TestCase):
    def test_daemon_version(self) -> None:
        text = "UPower client version 1.91.6\nUPower daemon version 1.91.5\n"
        self.assertEqual(charging.parse_upower_version(text), (1, 91, 5))

    def test_fixed_after_last_unfixed(self) -> None:
        self.assertGreater((1, 91, 6), charging.LAST_UNFIXED_UPOWER)
        self.assertGreater((1, 92), charging.LAST_UNFIXED_UPOWER)
        self.assertFalse((1, 91, 5) > charging.LAST_UNFIXED_UPOWER)

    def test_daemon_not_running(self) -> None:
        self.assertIsNone(charging.parse_upower_version("UPower client version 1.91.5\n"))


class Properties(unittest.TestCase):
    def test_key_value_lines(self) -> None:
        text = 'DEVPATH=/devices/x\nID_INPUT_KEYBOARD=1\nNAME="a=b"\n\n'
        properties = charging.parse_properties(text)
        self.assertEqual(properties["ID_INPUT_KEYBOARD"], "1")
        self.assertEqual(properties["NAME"], '"a=b"')


if __name__ == "__main__":
    unittest.main()
