# pyright: strict
import unittest

from helpers import load

cleanup = load("config/quickshell/menus/cleanup.py")


class Sizes(unittest.TestCase):
    def test_paccache_summary(self) -> None:
        output = "==> finished dry run: 89 candidates (disk space saved: 794.79 MiB)\n"
        self.assertEqual(cleanup.parse_paccache(output), int(794.79 * 1024**2))

    def test_paccache_with_nothing_to_do(self) -> None:
        self.assertEqual(cleanup.parse_paccache("==> no candidate packages found for pruning\n"), 0)

    def test_journal_usage(self) -> None:
        output = "Archived and active journals take up 521.4M in the file system.\n"
        self.assertEqual(cleanup.parse_journal(output), int(521.4 * 1024**2))

    def test_plain_bytes(self) -> None:
        self.assertEqual(cleanup.parse_size("512"), 512)

    def test_no_size(self) -> None:
        self.assertEqual(cleanup.parse_size("none"), 0)


class Names(unittest.TestCase):
    def test_removed_flatpak_is_its_app(self) -> None:
        self.assertEqual(cleanup.removed_app("com.brave.Browser-1ec59ab"), "com.brave.Browser")

    def test_old_generations_leave_the_current_ones(self) -> None:
        links = ["home-manager", "home-manager-14-link", "home-manager-15-link", "profile", "profile-11-link"]
        self.assertEqual(
            cleanup.old_generations(links, ["home-manager-15-link", "profile-11-link"]),
            ["home-manager-14-link"],
        )

    def test_only_generations_count_as_old(self) -> None:
        self.assertEqual(cleanup.old_generations(["profile", "channels"], []), [])


if __name__ == "__main__":
    unittest.main()
