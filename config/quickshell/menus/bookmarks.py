"""Keeps the fixed folders in Files' sidebar: Downloads, Documents, Videos,
Templates, Public, Pictures, Music and Nextcloud stay its first bookmarks, in
this order. Removing one in Files puts it back; other bookmarks can be added
and removed as usual and come after them. Run by daemon.qml, with the
system's Python like drives.py.
"""

import os

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BOOKMARKS = os.path.join(GLib.get_user_config_dir(), "gtk-3.0", "bookmarks")


def fixed():
    """The fixed folders' bookmark lines, of those that exist."""
    special = [
        GLib.UserDirectory.DIRECTORY_DOWNLOAD,
        GLib.UserDirectory.DIRECTORY_DOCUMENTS,
        GLib.UserDirectory.DIRECTORY_VIDEOS,
        GLib.UserDirectory.DIRECTORY_TEMPLATES,
        GLib.UserDirectory.DIRECTORY_PUBLIC_SHARE,
        GLib.UserDirectory.DIRECTORY_PICTURES,
        GLib.UserDirectory.DIRECTORY_MUSIC,
    ]
    paths = [GLib.get_user_special_dir(d) for d in special]
    paths.append(os.path.join(GLib.get_home_dir(), "Nextcloud"))
    home = GLib.get_home_dir()
    return [
        f"{GLib.filename_to_uri(p, None)} {os.path.basename(p)}" for p in paths if p and p != home and os.path.isdir(p)
    ]


def keep(*_):
    try:
        with open(BOOKMARKS) as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        lines = []
    first = fixed()
    uris = {line.split(" ", 1)[0] for line in first}
    wanted = first + [line for line in lines if line.split(" ", 1)[0] not in uris]
    if wanted != lines:
        os.makedirs(os.path.dirname(BOOKMARKS), exist_ok=True)
        with open(BOOKMARKS + ".tmp", "w") as f:
            f.write("".join(f"{line}\n" for line in wanted))
        os.replace(BOOKMARKS + ".tmp", BOOKMARKS)


if __name__ == "__main__":
    keep()
    monitor = Gio.File.new_for_path(BOOKMARKS).monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, None)
    monitor.connect("changed", keep)
    GLib.MainLoop().run()
