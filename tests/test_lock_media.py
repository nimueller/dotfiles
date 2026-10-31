# pyright: strict
import unittest

from helpers import load

lock_media = load("pkgs/scripts/lock-media.py")


def line(instance: str, status: str, title: str, length: str = "240000000") -> str:
    return "\t".join([instance, status, title, "Artist", "file:///tmp/art", "60000000", length])


class Choose(unittest.TestCase):
    def test_playing_first(self) -> None:
        out = "\n".join([line("a.instance1", "Paused", "Old"), line("b.instance2", "Playing", "Now")])
        player = lock_media.choose(lock_media.parse(out))
        self.assertEqual((player.name, player.title, player.position, player.length), ("b.instance2", "Now", 60, 240))

    def test_paused_with_a_track(self) -> None:
        out = "\n".join([line("brave.instance3", "Stopped", ""), line("a.instance1", "Paused", "Old")])
        self.assertEqual(lock_media.choose(lock_media.parse(out)).title, "Old")

    def test_nothing(self) -> None:
        out = "\n".join([line("brave.instance3", "Playing", ""), line("playerctld", "Playing", "Mirror"), "garbage"])
        self.assertIsNone(lock_media.choose(lock_media.parse(out)))


class Show(unittest.TestCase):
    def test_time(self) -> None:
        self.assertEqual(lock_media.time(83), "1:23")
        self.assertEqual(lock_media.time(3765), "1:02:45")

    def test_position(self) -> None:
        player = lock_media.parse(line("a", "Playing", "T"))[0]
        text = lock_media.position(player)
        self.assertTrue(text.startswith("1:00  ") and text.endswith("  4:00"))
        self.assertEqual(text.count("━"), lock_media.BAR)
        self.assertIn(f'<span foreground="{lock_media.DONE}">{"━" * 4}</span>', text)

    def test_no_length(self) -> None:
        self.assertEqual(lock_media.position(lock_media.parse(line("a", "Playing", "T", ""))[0]), "")

    def test_live(self) -> None:
        player = lock_media.parse(line("a", "Playing", "T", "9223372036854775807"))[0]
        live = f'<span foreground="{lock_media.LIVE_COLOR}">●  Live</span>'
        self.assertEqual(lock_media.position(player), f"{live}  1:00")

    def test_image_type(self) -> None:
        self.assertEqual(lock_media.image_type(b"\x89PNG\r\n"), "png")
        self.assertEqual(lock_media.image_type(b"\xff\xd8\xff\xe0"), "jpg")
        self.assertEqual(lock_media.image_type(b"RIFF\x00\x00\x00\x00WEBPVP8 "), "webp")
        self.assertIsNone(lock_media.image_type(b"<html>"))

    def test_blank(self) -> None:
        png = lock_media.blank_png()
        self.assertEqual(lock_media.image_type(png), "png")
        self.assertEqual(png[16:24], b"\x00\x00\x00\x01\x00\x00\x00\x01")  # 1×1


if __name__ == "__main__":
    unittest.main()
