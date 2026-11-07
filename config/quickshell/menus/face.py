# pyright: strict
"""The profile picture on the lock screen (Machine Settings, settings.qml):
pick an image in the file chooser portal, then crop it square and scale it
to ~/.face, which stays out of git (config/hypr/hyprlock.conf shows it).

  face.py    prints "saved", nothing if cancelled; errors on stderr
"""

import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402
from portal import choose_files  # noqa: E402

SIZE = 512
FACE = Path.home() / ".face"


def choose_picture() -> str | None:
    """The picked image's path, None if cancelled."""
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    uris = choose_files(bus, "Select a profile picture", "_Use", mime_types=["image/*"])
    if not uris:
        return None
    path, _hostname = GLib.filename_from_uri(uris[0])
    return path


def save_square(source: str, target: Path) -> None:
    """Crops and scales the image to a SIZE square PNG, written next to the
    target first so a failed run leaves the old picture."""
    temp = target.with_name(f"{target.name}.new")
    square = f"{SIZE}x{SIZE}"
    subprocess.run(
        [
            "magick",
            # The first frame of an animation
            f"{source}[0]",
            "-auto-orient",
            # ^: fill the square, cropped to it below
            "-thumbnail",
            f"{square}^",
            "-gravity",
            "center",
            "-extent",
            square,
            f"PNG:{temp}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    temp.replace(target)


def main() -> None:
    source = choose_picture()
    if source is None:
        return
    save_square(source, FACE)
    print("saved")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        stderr = str(error.stderr).strip()
        sys.exit(stderr or "ImageMagick couldn't read the picture")
    except (GLib.Error, OSError) as error:
        sys.exit(str(error))
