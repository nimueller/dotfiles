# pyright: strict
"""Whether the system needs a reboot after an update, and how urgently:

  reboot-check     prints one line: reboot now, reboot later, or none needed

Runs at the end of every update (the `upgrade` alias in
config/zsh/init-content.zsh, Updates.qml in the bar).

- now: something that runs already breaks. The running kernel was replaced,
  so its modules are gone and nothing new can load one (a USB stick, a
  filesystem). Or the NVIDIA driver's libraries no longer match the loaded
  kernel module, so a program that starts on the GPU fails.
- later: an update since boot only takes effect with one, but nothing breaks
  until then: firmware, microcode, systemd, glibc, D-Bus, Mesa.
- none: everything else is picked up by restarting the program.

Built with writePython3Bin (pkgs/default.nix), so the file has no shebang.
"""

import os
import platform
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

MODULES = Path("/usr/lib/modules")
NVIDIA_MODULE_VERSION = Path("/sys/module/nvidia/version")
NVIDIA_LIBRARIES = "nvidia-utils"
PACMAN_LOG = Path("/var/log/pacman.log")
PROC_STAT = Path("/proc/stat")
LOG_TIME_FORMAT = "%Y-%m-%dT%H:%M:%S%z"
# pacman.log: "[time] [ALPM] upgraded name (old -> new)"
CHANGES = ("upgraded", "downgraded", "reinstalled", "installed")

# Packages whose update only takes effect at boot (or would mean restarting
# nearly everything); a name ending in "*" stands for its split packages too
LATER_PACKAGES = [
    "linux-firmware*",
    "intel-ucode",
    "amd-ucode",
    "systemd",
    "systemd-libs",
    "glibc",
    "dbus",
    "dbus-broker",
    "mesa",
    "lib32-mesa",
    "vulkan-intel",
    "vulkan-radeon",
]

RED = "\033[1;31m"
YELLOW = "\033[1;33m"
GREEN = "\033[1;32m"
RESET = "\033[0m"


@dataclass
class Verdict:
    urgency: str  # "now", "later" or "none"
    reasons: list[str]


def boot_time(stat: str) -> float | None:
    """/proc/stat's "btime <seconds since the epoch>" """
    for line in stat.splitlines():
        key, _, value = line.partition(" ")
        if key == "btime":
            return float(value)
    return None


def changed_since(log: str, since: float) -> list[str]:
    """The packages pacman.log has upgraded, installed or reinstalled after
    `since`, each once, in the order of the log"""
    packages: list[str] = []
    for line in log.splitlines():
        package = changed_package(line, since)
        if package is not None and package not in packages:
            packages.append(package)
    return packages


def changed_package(line: str, since: float) -> str | None:
    """The package of one "[ALPM] upgraded …" line newer than `since`"""
    stamp, separator, rest = line.partition("] [ALPM] ")
    if separator == "":
        return None
    words = rest.split()
    if len(words) < 2 or words[0] not in CHANGES:
        return None
    try:
        when = datetime.strptime(stamp.lstrip("["), LOG_TIME_FORMAT).timestamp()
    except ValueError:
        # The format before pacman 5.2, years older than any boot
        return None
    if when <= since:
        return None
    return words[1]


def needs_later(package: str) -> bool:
    for pattern in LATER_PACKAGES:
        if pattern.endswith("*") and package.startswith(pattern[:-1]):
            return True
        if package == pattern:
            return True
    return False


def installed_version(package: str) -> str | None:
    """pacman -Q's version without the package release: "615.78.08" of
    "nvidia-utils 615.78.08-1" """
    result = subprocess.run(["pacman", "-Q", package], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return None
    version = result.stdout.split()[-1]
    return version.rsplit("-", 1)[0]


def now_reasons(kernel: str, modules: Path, loaded_nvidia: str | None, nvidia_libraries: str | None) -> list[str]:
    reasons: list[str] = []
    if not (modules / kernel).is_dir():
        reasons.append(f"the running kernel {kernel} was replaced")
    has_nvidia = loaded_nvidia is not None and nvidia_libraries is not None
    if has_nvidia and loaded_nvidia != nvidia_libraries:
        reasons.append(f"the NVIDIA driver is {nvidia_libraries}, the loaded module {loaded_nvidia}")
    return reasons


def verdict(now: list[str], changed: list[str]) -> Verdict:
    if now:
        return Verdict("now", now)
    later = [package for package in changed if needs_later(package)]
    if later:
        return Verdict("later", later)
    return Verdict("none", [])


def message(result: Verdict, colors: bool) -> str:
    texts = {
        "now": (RED, "Reboot now: " + "; ".join(result.reasons)),
        "later": (YELLOW, "Reboot when convenient, updated since boot: " + ", ".join(result.reasons)),
        "none": (GREEN, "No reboot needed"),
    }
    color, text = texts[result.urgency]
    if colors:
        return f"{color}{text}{RESET}"
    return text


def read(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except OSError:
        # Missing: no NVIDIA module loaded, or not Arch; checked without it
        return ""


def main(args: list[str]) -> int:
    if args:
        print(__doc__, file=sys.stderr)
        return 2

    loaded_nvidia = read(NVIDIA_MODULE_VERSION).strip() or None
    nvidia_libraries = installed_version(NVIDIA_LIBRARIES) if loaded_nvidia else None
    now = now_reasons(platform.release(), MODULES, loaded_nvidia, nvidia_libraries)

    booted = boot_time(read(PROC_STAT))
    changed = changed_since(read(PACMAN_LOG), booted) if booted is not None else []

    colors = sys.stdout.isatty() and os.environ.get("NO_COLOR", "") == ""
    print(message(verdict(now, changed), colors))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
