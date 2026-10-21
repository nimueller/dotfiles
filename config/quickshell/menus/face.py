"""The profile picture on the lock screen (Machine Settings, settings.qml):
pick an image in the file chooser portal, then crop it square and scale it
to ~/.face, which stays out of git (config/hypr/hyprlock.conf shows it).

  face.py    prints "saved", nothing if cancelled; errors on stderr
"""

import os
import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402
from portal import choose_files  # noqa: E402

SIZE = 512


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    uris = choose_files(bus, "Select a profile picture", "_Use", mime_types=["image/*"])
    if not uris:
        return
    source = GLib.filename_from_uri(uris[0])[0]
    face = os.path.expanduser("~/.face")
    temp = f"{face}.new"
    # [0]: the first frame of an animation; ^ fills the square, then cropped to it
    subprocess.run(
        [
            "magick",
            f"{source}[0]",
            "-auto-orient",
            "-thumbnail",
            f"{SIZE}x{SIZE}^",
            "-gravity",
            "center",
            "-extent",
            f"{SIZE}x{SIZE}",
            f"PNG:{temp}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    os.replace(temp, face)
    print("saved")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(e.stderr.strip() or "ImageMagick couldn't read the picture")
    except (GLib.Error, OSError) as e:
        sys.exit(str(e))
