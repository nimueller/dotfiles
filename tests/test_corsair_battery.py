# pyright: strict
import unittest

from helpers import load

corsair = load("config/quickshell/menus/corsair-battery.py")

# The Bragi parts of two receivers' report descriptors. A headset's: input
# report 1 and output report 2 of 63 bytes, after a keyboard collection with
# a report id of its own, and followed by a second vendor collection.
HEADSET = bytes.fromhex(
    "05010906a101851105089503750119012903150025019102c0"
    "0642ff0901a1018501150026ff007508953f090181028502953f09019102c0"
    "0642ff0902a1018503150026ff007508953f09018102c0"
)
# A mouse's receiver: no report ids, 64 bytes each way
MOUSE = bytes.fromhex("0642ff0901a101150026ff007508954009018102954009019102c0")
# The mouse's other vendor interface, which only sends events
EVENTS_ONLY = bytes.fromhex("0642ff0902a101150026ff007508954009028102c0")


class Descriptor(unittest.TestCase):
    def test_headset_uses_report_ids(self) -> None:
        interface = corsair.find_bragi_interface(HEADSET)
        self.assertEqual(interface, corsair.BragiInterface(1, 2, 63))

    def test_mouse_uses_none(self) -> None:
        interface = corsair.find_bragi_interface(MOUSE)
        self.assertEqual(interface, corsair.BragiInterface(0, 0, 64))

    def test_other_interfaces_are_skipped(self) -> None:
        self.assertIsNone(corsair.find_bragi_interface(EVENTS_ONLY))
        keyboard_only = HEADSET[:25]
        self.assertIsNone(corsair.find_bragi_interface(keyboard_only))


class Request(unittest.TestCase):
    def test_report_id_first_then_padded(self) -> None:
        interface = corsair.BragiInterface(1, 2, 63)
        request = corsair.get_property_request(interface, corsair.BATTERY_LEVEL)
        self.assertEqual(request[:4], bytes([0x02, 0x09, 0x02, 0x0F]))
        self.assertEqual(len(request), 64)

    def test_zero_without_report_ids(self) -> None:
        interface = corsair.BragiInterface(0, 0, 64)
        request = corsair.get_property_request(interface, corsair.BATTERY_STATUS)
        self.assertEqual(request[:4], bytes([0x00, 0x09, 0x02, 0x10]))
        self.assertEqual(len(request), 65)


class Answer(unittest.TestCase):
    HEADSET = corsair.BragiInterface(1, 2, 63)
    MOUSE = corsair.BragiInterface(0, 0, 64)

    def test_value_little_endian(self) -> None:
        answer = bytes.fromhex("01010200b603000000")
        self.assertEqual(corsair.parse_answer(self.HEADSET, answer), 950)
        answer = bytes.fromhex("0102002602000000")
        self.assertEqual(corsair.parse_answer(self.MOUSE, answer), 550)

    def test_refusal(self) -> None:
        # The receiver itself (index 0) has no battery: status 5
        answer = bytes.fromhex("0002054000000000")
        self.assertIsNone(corsair.parse_answer(self.MOUSE, answer))
        answer = bytes.fromhex("0102050000000000")
        self.assertIsNone(corsair.parse_answer(self.MOUSE, answer))

    def test_event_is_no_answer(self) -> None:
        answer = bytes.fromhex("0101010f00000000")
        self.assertIsNone(corsair.parse_answer(self.MOUSE, answer))

    def test_too_short(self) -> None:
        self.assertIsNone(corsair.parse_answer(self.MOUSE, bytes.fromhex("0102")))


class Names(unittest.TestCase):
    def test_model_from_receiver(self) -> None:
        name = corsair.model_name("CORSAIR VOID Wireless Gaming Receiver")
        self.assertEqual(name, "VOID Wireless")

    def test_shared_receiver_names_nothing(self) -> None:
        name = corsair.model_name("CORSAIR SLIPSTREAM WIRELESS USB Receiver")
        self.assertEqual(name, "")

    def test_states(self) -> None:
        self.assertEqual(corsair.battery_state(1), "charging")
        self.assertEqual(corsair.battery_state(2), "discharging")
        self.assertEqual(corsair.battery_state(7), "unknown")
        self.assertEqual(corsair.battery_state(None), "unknown")


if __name__ == "__main__":
    unittest.main()
