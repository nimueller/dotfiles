# pyright: strict
"""How long the lock screen still refuses every password, after too many
wrong ones (config/hypr/hyprlock.conf shows it below the password):

  lock-lockout     "󰌾   Too many tries, wait 42 s" and the way out over a
                   TTY on a second line, as Pango markup; nothing when
                   not locked

pam_faillock only tells the time left in whole minutes, and only right after
a try. Its tally file belongs to the user, so the time can be worked out
here, the way pam_faillock does it: the options from the preauth line of
/etc/pam.d/hyprlock (system/pam-hyprlock) over those of faillock.conf.
Without such a line (the package's file, which includes `login`) the
system's tally in /run/faillock counts, with faillock.conf alone.
Built with writePython3Bin (pkgs/default.nix), so the file has no shebang.
"""

import getpass
import struct
import sys
import time
from dataclasses import dataclass
from pathlib import Path

PAM = Path("/etc/pam.d/hyprlock")
CONF = Path("/etc/security/faillock.conf")
# struct tally in pam_faillock's faillock.h: source[52], reserved, status, time
RECORD = struct.Struct("=52sHHQ")
VALID = 0x1


@dataclass
class Options:
    # pam_faillock's defaults
    dir: str = "/run/faillock"
    deny: int = 3
    fail_interval: int = 900
    unlock_time: int = 600


def settings(text: str) -> dict[str, str]:
    """faillock.conf: "key = value" lines, # starts a comment"""
    values: dict[str, str] = {}
    for line in text.splitlines():
        key, sep, value = line.split("#", 1)[0].partition("=")
        if sep:
            values[key.strip()] = value.strip()
    return values


def preauth(text: str) -> dict[str, str] | None:
    """The key=value arguments of the pam_faillock preauth line of a PAM file"""
    for line in text.splitlines():
        words = line.split("#", 1)[0].split()
        if "pam_faillock.so" in words and "preauth" in words:
            return dict(word.split("=", 1) for word in words if "=" in word)
    return None


def options(conf: dict[str, str], args: dict[str, str]) -> Options:
    values = conf | args
    result = Options()
    if "dir" in values:
        result.dir = values["dir"]
    for name in ("deny", "fail_interval", "unlock_time"):
        if values.get(name, "").isdigit():
            setattr(result, name, int(values[name]))
    return result


def failures(data: bytes) -> list[int]:
    """The times of the valid records of a tally file"""
    count = len(data) // RECORD.size
    records = (RECORD.unpack_from(data, i * RECORD.size) for i in range(count))
    return [when for _, _, status, when in records if status & VALID]


def left(times: list[int], opts: Options, now: float) -> int:
    """Seconds until the next try counts again, as in check_tally()"""
    if not times or not opts.deny or not opts.unlock_time:
        return 0
    latest = max(times)
    recent = sum(1 for when in times if latest - when < opts.fail_interval)
    if recent < opts.deny:
        return 0
    return max(0, int(latest + opts.unlock_time - now + 0.999))


def text(seconds: int) -> str:
    if seconds <= 0:
        return ""
    wait = f"{seconds} s" if seconds < 60 else f"{seconds // 60}:{seconds % 60:02} min"
    # the way out quieter, in Catppuccin Macchiato subtext0
    way_out = '<span foreground="#a5adcb">or Ctrl+Alt+F3, log in, pkill -USR1 hyprlock</span>'
    return f"󰌾   Too many tries, wait {wait}\n{way_out}"


def read(path: Path) -> str:
    try:
        return path.read_text()
    except OSError:
        return ""


def main(args: list[str]) -> int:
    if args:
        print(__doc__, file=sys.stderr)
        return 2
    opts = options(settings(read(CONF)), preauth(read(PAM)) or {})
    try:
        data = (Path(opts.dir) / getpass.getuser()).read_bytes()
    except OSError:
        return 0  # no tally: no failures since the boot
    print(text(left(failures(data), opts, time.time())))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
