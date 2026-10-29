# pyright: strict
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

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


class Record(unittest.TestCase):
    def test_area_scaled_to_even_size(self) -> None:
        args = screenshot.recorder_args("DP-1", "10,20 401x301", "50", False, Path("/v/r.mp4"))
        self.assertEqual(args[:6], ["wf-recorder", "-y", "-o", "DP-1", "-g", "10,20 401x301"])
        self.assertIn("scale=trunc(iw*0.5/2)*2:trunc(ih*0.5/2)*2", args)
        self.assertNotIn("--audio=@DEFAULT_MONITOR@", args)
        self.assertEqual(args[-2:], ["-f", "/v/r.mp4"])

    def test_sound_from_the_speakers(self) -> None:
        args = screenshot.recorder_args("DP-1", "0,0 10x10", "100", True, Path("r.mp4"))
        self.assertIn("--audio=@DEFAULT_MONITOR@", args)
        self.assertIn("scale=trunc(iw*1/2)*2:trunc(ih*1/2)*2", args)

    def test_running_recording(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "recording.json"
            with mock.patch.object(screenshot, "RECORDING", state):
                self.assertIsNone(screenshot.running_recording())
                state.write_text(f'{{"pid": {os.getpid()}}}')
                self.assertEqual(screenshot.running_recording(), os.getpid())
                # A leftover of a crashed recorder goes
                state.write_text("not json")
                self.assertIsNone(screenshot.running_recording())
                self.assertFalse(state.exists())


if __name__ == "__main__":
    unittest.main()
