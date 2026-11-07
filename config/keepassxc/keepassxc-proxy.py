#!/usr/bin/env python3
# pyright: strict
"""KeePassXC's browser proxy for browsers in Flatpak (Brave, Zen), with the
Python of their runtime: they can't start the host's keepassxc-proxy, which
needs Qt. Between the browser's native messaging (a 4-byte length, then the
JSON message, on stdin and stdout) and KeePassXC's socket (bare JSON
messages), which the sandbox may reach (home-manager/desktop/flatpak.nix).
"""

import json
import os
import selectors
import socket
import struct
import sys
from typing import BinaryIO

SOCKET = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"),
    "app",
    "org.keepassxc.KeePassXC",
    "org.keepassxc.KeePassXC.BrowserServer",
)
# Native messaging's length prefix: 32 bits in the machine's byte order
LENGTH = struct.Struct("=I")
RECEIVE_SIZE = 1 << 20
BROWSER = "browser"
KEEPASSXC = "keepassxc"


def read_message(stream: BinaryIO) -> bytes | None:
    """The browser's next message, None once it closed the connection."""
    header = stream.read(LENGTH.size)
    if len(header) < LENGTH.size:
        return None
    (length,) = LENGTH.unpack(header)
    return stream.read(length)


def write_message(stream: BinaryIO, data: bytes) -> None:
    stream.write(LENGTH.pack(len(data)) + data)
    stream.flush()


class KeePassXCReader:
    """Splits what KeePassXC sends into messages: one read may hold part of
    a message or several of them."""

    def __init__(self) -> None:
        self.decoder = json.JSONDecoder()
        self.pending = ""

    def feed(self, data: bytes) -> list[object]:
        self.pending += data.decode()
        messages: list[object] = []
        while self.pending.strip():
            text = self.pending.lstrip()
            try:
                message, end = self.decoder.raw_decode(text)
            except json.JSONDecodeError:
                # Incomplete: wait for the rest
                break
            messages.append(message)
            self.pending = text[end:]
        return messages


def main() -> None:
    keepassxc = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    keepassxc.connect(SOCKET)
    browser_in = sys.stdin.buffer
    browser_out = sys.stdout.buffer
    selector = selectors.DefaultSelector()
    selector.register(browser_in, selectors.EVENT_READ, BROWSER)
    selector.register(keepassxc, selectors.EVENT_READ, KEEPASSXC)
    reader = KeePassXCReader()
    while True:
        for key, _ in selector.select():
            if key.data == BROWSER:
                message = read_message(browser_in)
                if message is None:
                    return
                keepassxc.sendall(message)
                continue
            data = keepassxc.recv(RECEIVE_SIZE)
            if not data:
                # KeePassXC quit
                return
            for message in reader.feed(data):
                write_message(browser_out, json.dumps(message).encode())


if __name__ == "__main__":
    main()
