# pyright: strict
import tempfile
import unittest
from compression import zstd
from pathlib import Path
from unittest import mock

from helpers import load

logs = load("pkgs/scripts/discord-call-logs.py")

CALL = b"[2026-10-28 14:05:09.123] started\n[2026-10-28 14:05:10.000] Transport stats\n"


class Names(unittest.TestCase):
    def test_named_by_the_first_line(self) -> None:
        name = logs.archive_name(Path("discord-last-webrtc_1"), CALL)
        self.assertEqual(name, "webrtc-2026-10-28_14-05-09-part1.log.zst")

    def test_no_date_no_name(self) -> None:
        self.assertIsNone(logs.archive_name(Path("discord-webrtc_0"), b"nothing\n"))


class Pruning(unittest.TestCase):
    def test_oldest_beyond_the_limit(self) -> None:
        sizes = {"webrtc-2026-01-01": 40, "webrtc-2026-01-02": 40, "webrtc-2026-01-03": 40}
        self.assertEqual(logs.to_remove(sizes, 100), ["webrtc-2026-01-01"])

    def test_all_within_the_limit(self) -> None:
        self.assertEqual(logs.to_remove({"a": 10, "b": 10}, 100), [])


class Keep(unittest.TestCase):
    def test_calls_are_kept_compressed_and_others_skipped(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / "archive"
            archive.mkdir()
            call, quiet = Path(tmp) / "discord-webrtc_0", Path(tmp) / "discord-webrtc_1"
            call.write_bytes(CALL)
            quiet.write_bytes(b"[2026-10-28 14:05:09] audio devices\n")
            with mock.patch.object(logs, "ARCHIVE", archive):
                logs.keep(call)
                logs.keep(quiet)
            kept = list(archive.iterdir())
            self.assertEqual([f.name for f in kept], ["webrtc-2026-10-28_14-05-09-part0.log.zst"])
            self.assertEqual(zstd.decompress(kept[0].read_bytes()), CALL)
            self.assertEqual(kept[0].stat().st_mtime, call.stat().st_mtime)


if __name__ == "__main__":
    unittest.main()
