# pyright: strict
"""The file chooser portal for the shell's Python helpers (kdeconnect.py,
face.py): Nautilus' file chooser (config/xdg-desktop-portal)."""

import os

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

PORTAL = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
REQUEST_PATH = "/org/freedesktop/portal/desktop/request"
RESPONSE_SUCCESS = 0
FILTER_BY_MIME_TYPE = 1
NO_TIMEOUT = -1


def request_handle(bus: Gio.DBusConnection, token: str) -> str:
    """The object path the portal answers on: the bus name without its
    leading ":" and with "_" for ".", then the token."""
    unique_name = bus.get_unique_name() or ""
    sender = unique_name.removeprefix(":").replace(".", "_")
    return f"{REQUEST_PATH}/{sender}/{token}"


def chooser_options(
    token: str,
    title: str,
    accept: str,
    multiple: bool,
    mime_types: list[str] | None,
) -> dict[str, GLib.Variant]:
    options = {
        "handle_token": GLib.Variant("s", token),
        "multiple": GLib.Variant("b", multiple),
        "accept_label": GLib.Variant("s", accept),
    }
    if mime_types:
        patterns = [(FILTER_BY_MIME_TYPE, mime_type) for mime_type in mime_types]
        # One filter, named like the dialog: (name, [(kind, pattern)])
        options["filters"] = GLib.Variant("a(sa(us))", [(title, patterns)])
    return options


def choose_files(
    bus: Gio.DBusConnection,
    title: str,
    accept: str,
    multiple: bool = False,
    mime_types: list[str] | None = None,
) -> list[str]:
    """URIs of the files picked, [] if cancelled. A title that starts with
    "Select" floats the window (config/hypr/windowrules.lua)."""
    token = f"dotfiles{os.getpid()}"
    loop = GLib.MainLoop()
    uris: list[str] = []

    def on_response(
        _bus: Gio.DBusConnection,
        _sender: str | None,
        _path: str,
        _interface: str,
        _signal: str,
        parameters: GLib.Variant,
    ) -> None:
        code, results = parameters.unpack()
        if code == RESPONSE_SUCCESS:
            uris.extend(results.get("uris", []))
        loop.quit()

    # Subscribed before the call, so the answer can't come first
    bus.signal_subscribe(
        PORTAL,
        "org.freedesktop.portal.Request",
        "Response",
        request_handle(bus, token),
        None,
        Gio.DBusSignalFlags.NONE,
        on_response,
    )
    options = chooser_options(token, title, accept, multiple, mime_types)
    bus.call_sync(
        PORTAL,
        PORTAL_PATH,
        "org.freedesktop.portal.FileChooser",
        "OpenFile",
        GLib.Variant("(ssa{sv})", ("", title, options)),
        None,
        Gio.DBusCallFlags.NONE,
        NO_TIMEOUT,
        None,
    )
    # pygobject-stubs leave MainLoop.run's return type unknown
    loop.run()  # pyright: ignore[reportUnknownMemberType]
    return uris
