# pyright: strict
import unittest

from helpers import load

screenshot = load("config/quickshell/menus/screenshot.py")


class Text(unittest.TestCase):
    def test_markup_is_escaped(self) -> None:
        self.assertEqual(screenshot.markup("a < b && c > d"), "a &lt; b &amp;&amp; c &gt; d")

    def test_long_text_is_cut(self) -> None:
        self.assertEqual(screenshot.preview("x" * 301), "x" * 300 + "…")
        self.assertEqual(screenshot.preview("short"), "short")

    def test_url(self) -> None:
        self.assertTrue(screenshot.is_url("https://example.org/a?b=c"))
        self.assertFalse(screenshot.is_url("see https://example.org"))
        self.assertFalse(screenshot.is_url("https://example.org\nmore"))


class Export(unittest.TestCase):
    def test_layer_crop_and_scale(self) -> None:
        self.assertEqual(
            screenshot.magick_args("shot.png", "layer.png", "10x20+1+2", "50", "copy"),
            ["shot.png", "layer.png", "-composite", "-crop", "10x20+1+2", "+repage", "-resize", "50%"],
        )

    def test_text_is_read_at_full_size(self) -> None:
        self.assertEqual(
            screenshot.magick_args("shot.png", "-", "10x20+1+2", "50", "text"),
            ["shot.png", "-crop", "10x20+1+2", "+repage"],
        )


if __name__ == "__main__":
    unittest.main()
