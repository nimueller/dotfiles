#!/usr/bin/env python3
# pyright: strict
"""Names Brave's audio streams after their tabs, for the sound menu
(Audio.qml). Run by daemon.qml for the session.

  audio-tabs.py

Brave plays the sound of every tab from one process and calls each stream
"Playback", so the sound menu can't tell two of them apart. The browser
extension in config/brave/extensions/audio-tabs posts the tabs that play
sound, on every change:

  POST http://127.0.0.1:PORT/tabs   [{"id": 12, "title": "Some video"}, ...]

From the first post on, this script watches Brave's streams in PipeWire
(pw-dump --monitor) and pairs a stream with the tab that started playing at
the same time, or with the only tab left over. A pair holds until the stream
ends. It prints one line per change, the titles by the stream's
object.serial:

  {"739": "Some video", "753": "Another video"}

Without the extension nothing is posted, PipeWire isn't watched and nothing
is printed: the sound menu shows the streams as before.
"""

import json
import queue
import signal
import subprocess
import sys
import threading
import time
from collections.abc import Iterator
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, HTTPServer
from types import FrameType
from typing import IO, cast

HOST = "127.0.0.1"
# Also in the extension's manifest.json and background.js
PORT = 48231
TABS_PATH = "/tabs"
# Only extensions may post: a web page can't send another page's Origin
EXTENSION_ORIGIN = "chrome-extension://"
MAX_BODY_BYTES = 64 * 1024

# A stream and a tab started together when this close in seconds: Brave
# shows a tab as playing a moment after its stream starts, or before it
PAIRING_WINDOW = 2.0
# How often the waiting tabs are paired again without any change, in seconds
TICK = 1.0

PW_DUMP_COMMAND = ["pw-dump", "--monitor", "--no-colors"]
BRAVE_BINARY = "brave"
PLAYBACK_CLASS = "Stream/Output/Audio"


@dataclass
class Tab:
    title: str
    # When the tab last started playing; None while it's silent
    audible_since: float | None


@dataclass
class Stream:
    serial: int
    # When it turned up; None for streams that were there before the watch
    appeared: float | None


@dataclass
class Pairing:
    """The audible tabs, Brave's streams, and which stream is which tab's."""

    tabs: dict[int, Tab] = field(default_factory=lambda: {})
    streams: dict[int, Stream] = field(default_factory=lambda: {})  # by node id
    tab_of_stream: dict[int, int] = field(default_factory=lambda: {})  # serial → tab id

    def update_tabs(self, audible: dict[int, str], now: float) -> None:
        """`audible`: the titles of the tabs playing sound now, by tab id."""
        for tab_id, title in audible.items():
            tab = self.tabs.get(tab_id)
            if tab is None:
                self.tabs[tab_id] = Tab(title, now)
                continue
            tab.title = title
            if tab.audible_since is None:
                tab.audible_since = now
        for tab_id, tab in self.tabs.items():
            if tab_id not in audible:
                tab.audible_since = None
        self.forget_unused_tabs()

    def add_stream(self, node_id: int, stream: Stream) -> None:
        """pw-dump repeats a node on every change of it: only its first
        appearance says when it started."""
        if node_id not in self.streams:
            self.streams[node_id] = stream

    def remove_stream(self, node_id: int) -> None:
        stream = self.streams.pop(node_id, None)
        if stream is None:
            return
        self.tab_of_stream.pop(stream.serial, None)
        self.forget_unused_tabs()

    def forget_unused_tabs(self) -> None:
        """Silent tabs without a stream: a paired tab keeps its title while it
        pauses, the others start over when they play again."""
        paired = set(self.tab_of_stream.values())
        for tab_id in list(self.tabs):
            tab = self.tabs[tab_id]
            if tab.audible_since is None and tab_id not in paired:
                del self.tabs[tab_id]

    def pair(self, now: float) -> None:
        self.pair_by_time()
        self.pair_last_ones(now)

    def unpaired_streams(self) -> list[Stream]:
        return [stream for stream in self.streams.values() if stream.serial not in self.tab_of_stream]

    def waiting_tabs(self) -> dict[int, float]:
        """When each audible tab without a stream started playing."""
        paired = set(self.tab_of_stream.values())
        waiting: dict[int, float] = {}
        for tab_id, tab in self.tabs.items():
            if tab.audible_since is not None and tab_id not in paired:
                waiting[tab_id] = tab.audible_since
        return waiting

    def pair_by_time(self) -> None:
        """A tab and a stream that started together, if nothing else did."""
        for tab_id, since in self.waiting_tabs().items():
            streams = [stream for stream in self.unpaired_streams() if started_together(stream.appeared, since)]
            tabs = [other for other in self.waiting_tabs().values() if started_together(since, other)]
            if len(streams) == 1 and len(tabs) == 1:
                self.tab_of_stream[streams[0].serial] = tab_id

    def pair_last_ones(self, now: float) -> None:
        """The only waiting tab with the only stream left over, e.g. one that
        played before the watch began. Only once the tab has waited a while,
        so a stream about to turn up gets its chance to pair by time."""
        waiting = self.waiting_tabs()
        streams = self.unpaired_streams()
        if len(waiting) != 1 or len(streams) != 1:
            return
        [(tab_id, since)] = waiting.items()
        if now - since > PAIRING_WINDOW:
            self.tab_of_stream[streams[0].serial] = tab_id

    def titles(self) -> dict[str, str]:
        return {str(serial): self.tabs[tab_id].title for serial, tab_id in self.tab_of_stream.items()}


def started_together(first: float | None, second: float) -> bool:
    if first is None:
        return False
    return abs(first - second) <= PAIRING_WINDOW


def parse_tabs(body: bytes) -> dict[int, str] | None:
    """The extension's post, as titles by tab id; None if it isn't one."""
    try:
        entries = json.loads(body)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    if not isinstance(entries, list):
        return None
    audible: dict[int, str] = {}
    for entry in cast(list[object], entries):
        if not isinstance(entry, dict):
            return None
        tab = cast(dict[str, object], entry)
        tab_id = tab.get("id")
        title = tab.get("title")
        if not isinstance(tab_id, int) or not isinstance(title, str):
            return None
        audible[tab_id] = title
    return audible


def brave_stream(pw_object: dict[str, object], now: float | None) -> Stream | None:
    """The stream a pw-dump object describes, if it's one of Brave's."""
    info = pw_object.get("info")
    if not isinstance(info, dict):
        return None
    props = cast(dict[str, object], info).get("props")
    if not isinstance(props, dict):
        return None
    props = cast(dict[str, object], props)
    serial = props.get("object.serial")
    is_playback = props.get("media.class") == PLAYBACK_CLASS
    is_brave = props.get("application.process.binary") == BRAVE_BINARY
    if not is_playback or not is_brave or not isinstance(serial, int):
        return None
    return Stream(serial, now)


def pw_dump_chunks(lines: Iterator[str]) -> Iterator[list[dict[str, object]]]:
    """pw-dump --monitor prints one indented JSON array per change; each ends
    with a line that is only "]"."""
    chunk: list[str] = []
    for line in lines:
        chunk.append(line)
        if line.rstrip("\n") != "]":
            continue
        yield cast(list[dict[str, object]], json.loads("".join(chunk)))
        chunk = []


# Events for the main loop, from the server's and the watch's threads
@dataclass
class TabsPosted:
    audible: dict[int, str]


@dataclass
class StreamAdded:
    node_id: int
    stream: Stream


@dataclass
class StreamRemoved:
    node_id: int


@dataclass
class WatchEnded:
    pass


Event = TabsPosted | StreamAdded | StreamRemoved | WatchEnded


def start_watch(events: "queue.Queue[Event]") -> "subprocess.Popen[str]":
    """pw-dump in a thread of its own. The caller ends the process: a
    daemon thread doesn't, and it would outlive this script."""
    process = subprocess.Popen(PW_DUMP_COMMAND, stdout=subprocess.PIPE, text=True)
    assert process.stdout is not None
    threading.Thread(target=watch_streams, args=(events, process.stdout), daemon=True).start()
    return process


def watch_streams(events: "queue.Queue[Event]", output: IO[str]) -> None:
    """Brave's streams coming and going. The first chunk lists what's
    already there: those streams didn't turn up just now."""
    try:
        is_first_chunk = True
        for chunk in pw_dump_chunks(iter(output)):
            appeared = None if is_first_chunk else time.monotonic()
            for pw_object in chunk:
                put_stream_event(events, pw_object, appeared)
            is_first_chunk = False
    finally:
        events.put(WatchEnded())


def put_stream_event(events: "queue.Queue[Event]", pw_object: dict[str, object], appeared: float | None) -> None:
    node_id = pw_object.get("id")
    if not isinstance(node_id, int):
        return
    if pw_object.get("info") is None:
        events.put(StreamRemoved(node_id))
        return
    stream = brave_stream(pw_object, appeared)
    if stream is not None:
        events.put(StreamAdded(node_id, stream))


def tabs_handler(events: "queue.Queue[Event]") -> type[BaseHTTPRequestHandler]:
    class TabsHandler(BaseHTTPRequestHandler):
        def do_POST(self) -> None:
            length = int(self.headers.get("Content-Length") or 0)
            is_allowed = (
                self.path == TABS_PATH
                and self.headers.get("Host") == f"{HOST}:{PORT}"
                and (self.headers.get("Origin") or "").startswith(EXTENSION_ORIGIN)
            )
            if not is_allowed:
                self.send_response(403)
                self.end_headers()
                return
            audible = parse_tabs(self.rfile.read(length)) if 0 < length <= MAX_BODY_BYTES else None
            if audible is None:
                self.send_response(400)
                self.end_headers()
                return
            events.put(TabsPosted(audible))
            self.send_response(204)
            self.end_headers()

        def log_message(self, format: str, *args: object) -> None:
            """No line per request: the extension posts on every change."""

    return TabsHandler


def serve(events: "queue.Queue[Event]") -> None:
    server = HTTPServer((HOST, PORT), tabs_handler(events))
    threading.Thread(target=server.serve_forever, daemon=True).start()


def apply(pairing: Pairing, event: Event, now: float) -> None:
    if isinstance(event, TabsPosted):
        pairing.update_tabs(event.audible, now)
    elif isinstance(event, StreamAdded):
        pairing.add_stream(event.node_id, event.stream)
    elif isinstance(event, StreamRemoved):
        pairing.remove_stream(event.node_id)
    else:
        # Without the watch the pairs go stale: daemon.qml starts this again
        sys.exit("audio-tabs: pw-dump has ended")


def exit_on_terminate(signal_number: int, frame: FrameType | None) -> None:
    """Quickshell ends the script with SIGTERM: exit through main's
    `finally`, which ends pw-dump."""
    sys.exit(0)


def next_event(events: "queue.Queue[Event]", is_watching: bool) -> Event | None:
    """Ticks only while watching: without the extension it just waits."""
    tick = TICK if is_watching else None
    try:
        return events.get(timeout=tick)
    except queue.Empty:
        return None


def main() -> None:
    signal.signal(signal.SIGTERM, exit_on_terminate)
    events: queue.Queue[Event] = queue.Queue()
    serve(events)
    pairing = Pairing()
    watch: subprocess.Popen[str] | None = None
    printed: dict[str, str] = {}
    try:
        while True:
            event = next_event(events, watch is not None)
            if event is not None:
                apply(pairing, event, time.monotonic())
            if isinstance(event, TabsPosted) and watch is None:
                watch = start_watch(events)
            pairing.pair(time.monotonic())
            titles = pairing.titles()
            if titles != printed:
                print(json.dumps(titles, ensure_ascii=False), flush=True)
                printed = titles
    finally:
        if watch is not None:
            watch.terminate()


if __name__ == "__main__":
    main()
