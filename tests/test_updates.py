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


def numeric(a: str, b: str) -> int:
    """A stand-in for vercmp on versions like 1.2-1"""
    x, y = [[int(n) for n in v.replace("-", ".").split(".")] for v in (a, b)]
    return (x > y) - (x < y)


def item(title: str, link: str, date: str) -> str:
    return f"<item><title>{title}</title><link>{link}</link><pubDate>{date}</pubDate></item>"


class Critical(unittest.TestCase):
    def test_parse_updates(self) -> None:
        out = "linux 6.19.11-1 -> 6.19.12-1\nfoo 1-1 -> 2-1 [ignored]\n\ngarbage\n"
        self.assertEqual(updates.parse_updates(out), {"linux": ("6.19.11-1", "6.19.12-1"), "foo": ("1-1", "2-1")})

    def test_last_upgrade(self) -> None:
        log = "\n".join(
            [
                "[2026-10-13T16:13:44+0200] [PACMAN] starting full system upgrade",
                "[2026-10-18T22:15:46+0200] [PACMAN] starting full system upgrade",
                "[2026-10-19T10:00:00+0200] [PACMAN] Running 'pacman -S foo'",
            ]
        )
        self.assertEqual(updates.last_upgrade(log), 1792354546)
        self.assertIsNone(updates.last_upgrade("[2026-10-19T10:00:00+0200] [PACMAN] Running 'pacman -S foo'"))

    def test_security_fixes(self) -> None:
        issues = json.dumps(
            [
                {"name": "AVG-1", "packages": ["linux"], "fixed": "6.19.12-1", "severity": "High"},
                {"name": "AVG-2", "packages": ["linux"], "fixed": "6.19.10-1", "severity": "Low"},  # already fixed
                {"name": "AVG-3", "packages": ["mesa"], "fixed": "27.0-1", "severity": "Medium"},  # not yet
                {"name": "AVG-4", "packages": ["vim"], "fixed": None, "severity": "Critical"},
            ]
        )
        waiting = {"linux": ("6.19.11-1", "6.19.12-1"), "mesa": ("26.1-1", "26.2-1"), "vim": ("9.0-1", "9.1-1")}
        fixes = updates.security_fixes(waiting, issues, numeric)
        self.assertEqual(fixes, [{"package": "linux", "issue": "AVG-1", "severity": "High"}])
        self.assertEqual(updates.security_fixes(waiting, "offline", numeric), [])

    def test_news_since(self) -> None:
        rss = "<rss><channel>{}{}<item><title>No date</title></item></channel></rss>".format(
            item("Newer", "https://archlinux.org/news/b/", "Wed, 21 Oct 2026 19:29:36 +0000"),
            item("Older", "https://archlinux.org/news/a/", "Mon, 12 Oct 2026 08:00:00 +0000"),
        )
        news = updates.news_since(rss, 1792354546)
        self.assertEqual(news, [{"title": "Newer", "link": "https://archlinux.org/news/b/", "date": "2026-10-21"}])
        self.assertEqual(len(updates.news_since(rss, 0)), 2)
        self.assertEqual(updates.news_since("<html", 0), [])


if __name__ == "__main__":
    unittest.main()
