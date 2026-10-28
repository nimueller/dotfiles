# pyright: strict
import json
import unittest

from helpers import load

updates = load("config/quickshell/menus/updates.py")

DAY = 86400


def lock(*modified: int) -> str:
    nodes: dict[str, object] = {"root": {"inputs": {}}}
    for i, m in enumerate(modified):
        nodes[f"input{i}"] = {"locked": {"lastModified": m}}
    return json.dumps({"nodes": nodes, "root": "root"})


class FlakeAge(unittest.TestCase):
    def test_newest_input_counts(self) -> None:
        self.assertEqual(updates.flake_age(lock(10 * DAY, 20 * DAY), 23 * DAY + 5), 3)

    def test_less_than_a_day_is_zero(self) -> None:
        self.assertEqual(updates.flake_age(lock(DAY), DAY + 3600), 0)

    def test_a_clock_behind_is_not_negative(self) -> None:
        self.assertEqual(updates.flake_age(lock(5 * DAY), DAY), 0)

    def test_broken_or_empty_lock(self) -> None:
        self.assertIsNone(updates.flake_age("not json", 0))
        self.assertIsNone(updates.flake_age(json.dumps({"nodes": {"root": {}}}), 0))
        self.assertIsNone(updates.flake_age(json.dumps({}), 0))


class CountLines(unittest.TestCase):
    def test_blank_lines_dont_count(self) -> None:
        self.assertEqual(updates.count_lines("a 1 -> 2\n\nb 3 -> 4\n"), 2)
        self.assertEqual(updates.count_lines(""), 0)


if __name__ == "__main__":
    unittest.main()
