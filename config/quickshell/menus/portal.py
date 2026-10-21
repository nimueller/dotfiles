"""The file chooser portal for the shell's Python helpers (kdeconnect.py,
face.py): Nautilus' file chooser (config/xdg-desktop-portal)."""

import os

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402


def choose_files(bus, title, accept, multiple=False, mime_types=None):
    """URIs of the files picked, [] if cancelled. A title that starts with
    "Select" floats the window (config/hypr/windowrules.lua)."""
    token = f"dotfiles{os.getpid()}"
    sender = bus.get_unique_name()[1:].replace(".", "_")
    handle = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
    loop = GLib.MainLoop()
    uris = []

    def response(_bus, _sender, _path, _iface, _signal, params):
        code, results = params.unpack()
        if code == 0:
            uris.extend(results.get("uris", []))
        loop.quit()

    bus.signal_subscribe(
        "org.freedesktop.portal.Desktop",
        "org.freedesktop.portal.Request",
        "Response",
        handle,
        None,
        Gio.DBusSignalFlags.NONE,
        response,
    )
    options = {
        "handle_token": GLib.Variant("s", token),
        "multiple": GLib.Variant("b", multiple),
        "accept_label": GLib.Variant("s", accept),
    }
    if mime_types:
        # (name, [(1 = MIME type, pattern)])
        options["filters"] = GLib.Variant("a(sa(us))", [(title, [(1, t) for t in mime_types])])
    bus.call_sync(
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.FileChooser",
        "OpenFile",
        GLib.Variant("(ssa{sv})", ("", title, options)),
        None,
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    )
    loop.run()
    return uris
