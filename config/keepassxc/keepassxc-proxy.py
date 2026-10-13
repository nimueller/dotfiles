#!/usr/bin/env python3
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

SOCKET = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"),
    "app",
    "org.keepassxc.KeePassXC",
    "org.keepassxc.KeePassXC.BrowserServer",
)


def read_message(stream):
    header = stream.read(4)
    if len(header) < 4:
        return None
    (length,) = struct.unpack("=I", header)
    return stream.read(length)


def write_message(stream, data):
    stream.write(struct.pack("=I", len(data)) + data)
    stream.flush()


def main():
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(SOCKET)
    stdin, stdout = sys.stdin.buffer, sys.stdout.buffer
    selector = selectors.DefaultSelector()
    selector.register(stdin, selectors.EVENT_READ, "browser")
    selector.register(sock, selectors.EVENT_READ, "keepassxc")
    decoder = json.JSONDecoder()
    pending = ""
    while True:
        for key, _ in selector.select():
            if key.data == "browser":
                message = read_message(stdin)
                if message is None:
                    return  # the browser closed the connection
                sock.sendall(message)
            else:
                data = sock.recv(1 << 20)
                if not data:
                    return  # KeePassXC quit
                # A read may hold part of a message or several of them
                pending += data.decode()
                while pending.strip():
                    try:
                        obj, end = decoder.raw_decode(pending.lstrip())
                    except json.JSONDecodeError:
                        break
                    pending = pending.lstrip()[end:]
                    write_message(stdout, json.dumps(obj).encode())


if __name__ == "__main__":
    main()
