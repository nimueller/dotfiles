# pyright: strict
"""Keeps the fixed folders in Files' sidebar: Downloads, Documents, Videos,
Templates, Public, Pictures, Music and Nextcloud stay its first bookmarks, in
this order. Removing one in Files puts it back; other bookmarks can be added
and removed as usual and come after them. Run by daemon.qml, with the
system's Python like drives.py.
"""

from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BOOKMARKS = Path(GLib.get_user_config_dir()) / "gtk-3.0" / "bookmarks"
SPECIAL_FOLDERS = [
    GLib.UserDirectory.DIRECTORY_DOWNLOAD,
    GLib.UserDirectory.DIRECTORY_DOCUMENTS,
    GLib.UserDirectory.DIRECTORY_VIDEOS,
    GLib.UserDirectory.DIRECTORY_TEMPLATES,
    GLib.UserDirectory.DIRECTORY_PUBLIC_SHARE,
    GLib.UserDirectory.DIRECTORY_PICTURES,
    GLib.UserDirectory.DIRECTORY_MUSIC,
]
OTHER_FOLDERS = ["Nextcloud"]


def fixed_folders() -> list[Path]:
    """The fixed folders that exist. An unset special folder is the home
    folder (or None), which isn't one of them."""
    home = Path(GLib.get_home_dir())
    special = [GLib.get_user_special_dir(folder) for folder in SPECIAL_FOLDERS]
    candidates = [Path(path) for path in special if path is not None]
    candidates += [home / name for name in OTHER_FOLDERS]
    return [folder for folder in candidates if folder != home and folder.is_dir()]


def bookmark_line(folder: Path) -> str:
    uri = GLib.filename_to_uri(str(folder), None)
    return f"{uri} {folder.name}"


def bookmark_uri(line: str) -> str:
    """A bookmark line is the URI, then optionally a space and a label."""
    return line.split(" ", 1)[0]


def read_bookmarks() -> list[str]:
    try:
        return BOOKMARKS.read_text().splitlines()
    except FileNotFoundError:
        return []


def write_bookmarks(lines: list[str]) -> None:
    BOOKMARKS.parent.mkdir(parents=True, exist_ok=True)
    temp = BOOKMARKS.with_name(f"{BOOKMARKS.name}.tmp")
    temp.write_text("".join(f"{line}\n" for line in lines))
    temp.replace(BOOKMARKS)


def keep_fixed_first(*_signal_arguments: object) -> None:
    """Puts the fixed folders first, followed by the other bookmarks as they
    were. Also the file monitor's callback."""
    current = read_bookmarks()
    fixed = [bookmark_line(folder) for folder in fixed_folders()]
    fixed_uris = {bookmark_uri(line) for line in fixed}
    others = [line for line in current if bookmark_uri(line) not in fixed_uris]
    wanted = fixed + others
    if wanted != current:
        write_bookmarks(wanted)


def main() -> None:
    keep_fixed_first()
    bookmarks = Gio.File.new_for_path(str(BOOKMARKS))
    monitor = bookmarks.monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, None)
    monitor.connect("changed", keep_fixed_first)
    # pygobject-stubs leave MainLoop.run's return type unknown
    GLib.MainLoop().run()  # pyright: ignore[reportUnknownMemberType]


if __name__ == "__main__":
    main()
