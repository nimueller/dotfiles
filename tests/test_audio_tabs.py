# pyright: strict
import unittest

from helpers import load

audio_tabs = load("config/quickshell/menus/audio-tabs.py")

WINDOW = audio_tabs.PAIRING_WINDOW


def brave_object(node_id: int, serial: int, binary: str = "brave") -> dict[str, object]:
    props: dict[str, object] = {
        "media.class": "Stream/Output/Audio",
        "application.process.binary": binary,
        "object.serial": serial,
    }
    return {"id": node_id, "type": "PipeWire:Interface:Node", "info": {"props": props}}


class ParseTabs(unittest.TestCase):
    def test_tabs(self) -> None:
        body = b'[{"id": 3, "title": "Video"}, {"id": 7, "title": "Radio"}]'
        self.assertEqual(audio_tabs.parse_tabs(body), {3: "Video", 7: "Radio"})

    def test_no_tabs(self) -> None:
        self.assertEqual(audio_tabs.parse_tabs(b"[]"), {})

    def test_invalid(self) -> None:
        for body in [b"not json", b'{"id": 3}', b'[{"id": "3", "title": "Video"}]', b'[{"id": 3}]', b"\xff"]:
            with self.subTest(body=body):
                self.assertIsNone(audio_tabs.parse_tabs(body))


class BraveStream(unittest.TestCase):
    def test_brave(self) -> None:
        stream = audio_tabs.brave_stream(brave_object(105, 739), 12.0)
        self.assertEqual(stream, audio_tabs.Stream(739, 12.0))

    def test_other_app(self) -> None:
        self.assertIsNone(audio_tabs.brave_stream(brave_object(105, 739, binary="firefox"), 12.0))

    def test_without_props(self) -> None:
        self.assertIsNone(audio_tabs.brave_stream({"id": 105, "info": {}}, 12.0))


class PwDumpChunks(unittest.TestCase):
    def test_chunks(self) -> None:
        lines = ["[\n", '  {"id": 1}\n', "]\n", "[\n", '  {"id": 2, "info": null}\n', "]\n"]
        chunks = list(audio_tabs.pw_dump_chunks(iter(lines)))
        self.assertEqual(chunks, [[{"id": 1}], [{"id": 2, "info": None}]])


class Pairing(unittest.TestCase):
    def setUp(self) -> None:
        self.pairing = audio_tabs.Pairing()

    def stream(self, node_id: int, serial: int, appeared: float | None) -> None:
        self.pairing.add_stream(node_id, audio_tabs.Stream(serial, appeared))

    def test_started_together(self) -> None:
        self.pairing.update_tabs({1: "Video"}, 10.0)
        self.stream(105, 739, 10.5)
        self.pairing.update_tabs({1: "Video", 2: "Radio"}, 30.0)
        self.stream(87, 753, 29.0)
        self.pairing.pair(30.0)
        self.assertEqual(self.pairing.titles(), {"739": "Video", "753": "Radio"})

    def test_two_tabs_at_once_stay_unpaired(self) -> None:
        self.pairing.update_tabs({1: "Video", 2: "Radio"}, 10.0)
        self.stream(105, 739, 10.2)
        self.stream(87, 753, 10.4)
        self.pairing.pair(20.0)
        self.assertEqual(self.pairing.titles(), {})

    def test_last_ones_wait_for_the_window(self) -> None:
        self.stream(105, 739, None)
        self.pairing.update_tabs({1: "Video"}, 10.0)
        self.pairing.pair(10.0 + WINDOW / 2)
        self.assertEqual(self.pairing.titles(), {})
        self.pairing.pair(10.0 + WINDOW * 2)
        self.assertEqual(self.pairing.titles(), {"739": "Video"})

    def test_late_stream_beats_the_one_left_over(self) -> None:
        # A stream from before (a silent page) mustn't take the new tab
        self.stream(105, 739, None)
        self.pairing.update_tabs({1: "Video"}, 10.0)
        self.stream(87, 753, 10.5)
        self.pairing.pair(10.0 + WINDOW * 2)
        self.assertEqual(self.pairing.titles(), {"753": "Video"})

    def test_pair_holds_through_a_pause_and_follows_the_title(self) -> None:
        self.pairing.update_tabs({1: "Song A"}, 10.0)
        self.stream(105, 739, 10.0)
        self.pairing.pair(10.0)
        self.pairing.update_tabs({}, 20.0)
        self.pairing.pair(20.0)
        self.assertEqual(self.pairing.titles(), {"739": "Song A"})
        self.pairing.update_tabs({1: "Song B"}, 30.0)
        self.pairing.pair(30.0)
        self.assertEqual(self.pairing.titles(), {"739": "Song B"})

    def test_repeated_node_keeps_its_start(self) -> None:
        self.stream(105, 739, 10.0)
        self.stream(105, 739, 50.0)
        self.pairing.update_tabs({1: "Video"}, 10.0)
        self.pairing.pair(10.0)
        self.assertEqual(self.pairing.titles(), {"739": "Video"})

    def test_ended_stream_frees_its_tab(self) -> None:
        self.pairing.update_tabs({1: "Video"}, 10.0)
        self.stream(105, 739, 10.0)
        self.pairing.pair(10.0)
        self.pairing.remove_stream(105)
        self.stream(87, 753, 40.0)
        self.pairing.pair(40.0 + WINDOW * 2)
        self.assertEqual(self.pairing.titles(), {"753": "Video"})


if __name__ == "__main__":
    unittest.main()
