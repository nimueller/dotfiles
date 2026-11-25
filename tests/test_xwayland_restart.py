# pyright: strict
import unittest

from helpers import load

restart = load("config/quickshell/menus/xwayland-restart.py")

XWAYLAND = "4242 (Xwayland) S 1043 4242 1043 0 -1 4194560 2047 0 0 0 12 3 0 0 20 0 5 0"
ZOMBIE = "4242 (Xwayland) Z 1043 4242 1043 0 -1 4227076 2047 0 0 0 12 3 0 0 20 0 1 0"
ODD_NAME = "77 (a) b (c)) R 12 77 12 0 -1 4194304 1 0 0 0 0 0 0 0 20 0 1 0"


class ParseStat(unittest.TestCase):
    def test_name_and_parent(self) -> None:
        process = restart.parse_stat(XWAYLAND)
        self.assertEqual(process.name, "Xwayland")
        self.assertEqual(process.parent, 1043)
        self.assertFalse(process.is_zombie)

    def test_zombie(self) -> None:
        self.assertTrue(restart.parse_stat(ZOMBIE).is_zombie)

    def test_name_with_spaces_and_parentheses(self) -> None:
        process = restart.parse_stat(ODD_NAME)
        self.assertEqual(process.name, "a) b (c)")
        self.assertEqual(process.parent, 12)

    def test_broken(self) -> None:
        with self.assertRaises(ValueError):
            restart.parse_stat("4242 Xwayland S 1043")


class InstancePid(unittest.TestCase):
    INSTANCES = [
        {"instance": "old_1_1", "pid": 900},
        {"instance": "abc_2_2", "pid": 1043},
    ]

    def test_this_instance(self) -> None:
        self.assertEqual(restart.instance_pid(self.INSTANCES, "abc_2_2"), 1043)

    def test_unknown_instance(self) -> None:
        self.assertIsNone(restart.instance_pid(self.INSTANCES, "other"))

    def test_no_instances(self) -> None:
        self.assertIsNone(restart.instance_pid([], "abc_2_2"))


if __name__ == "__main__":
    unittest.main()
