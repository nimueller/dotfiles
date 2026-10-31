#!/usr/bin/env python3
# pyright: strict
"""What can go from the disk, for the cleanup menu (Cleanup.qml).

  cleanup.py scan
  cleanup.py clean <id>

scan prints one JSON object, biggest first, without what's empty or what
this machine doesn't have:

  {"free": 24700000000, "items": [{"id": "nix", "title": "Old Nix generations",
   "detail": "…", "bytes": 11500000000, "blocked": ""}]}

blocked says why it can't go right now (a running program), for the menu.
clean prints {"ok": true} or {"error": "…"}.

There is no searching for "junk": this is a fixed list of places that are
either the trash or come back by themselves, and each goes through the tool
that owns it. A cache of a running program stays. Two limits matter:
- pacman: paccache keeps the last version of everything, and all cached
  versions of what ships kernel modules: an older kernel package can be the
  way back into a machine whose new kernel doesn't boot.
- nix: the current generations stay, older ones can't be rolled back to.
"""

import json
import re
import shutil
import subprocess
import sys
from collections.abc import Callable, Iterable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

HOME = Path.home()
TRASH = HOME / ".local/share/Trash"
FLATPAK_REMOVED = HOME / ".local/share/flatpak/.removed"
FLATPAK_APPS = HOME / ".var/app"
GRADLE = [HOME / ".gradle" / name for name in ("caches", "jdks", "wrapper")]
NIX_PROFILES = HOME / ".local/state/nix/profiles"
JOURNAL_KEEP = 100 * 1024**2
UNITS = {"": 1, "B": 1, "K": 1024, "M": 1024**2, "G": 1024**3, "T": 1024**4}


def run(*command: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, capture_output=True, text=True, check=False)


def lines(output: str) -> list[str]:
    return [line.strip() for line in output.splitlines() if line.strip()]


def parse_size(text: str) -> int:
    """Bytes of "521.4M" or "794.79 MiB", 0 without a size"""
    match = re.match(r"([\d.]+)\s*([KMGT]?)", text)
    return int(float(match[1]) * UNITS[match[2]]) if match else 0


def disk_usage(paths: Iterable[Path]) -> int:
    existing = [str(path) for path in paths if path.exists()]
    if not existing:
        return 0
    total = run("du", "-scB1", "--", *existing).stdout.splitlines()
    return int(total[-1].split()[0]) if total else 0


def remove_contents(folder: Path) -> None:
    for entry in folder.iterdir():
        if entry.is_dir() and not entry.is_symlink():
            shutil.rmtree(entry, ignore_errors=True)
        else:
            entry.unlink(missing_ok=True)


def privileged(*command: str) -> str:
    """Through polkit's password prompt: the error, "" if it worked"""
    result = run("pkexec", *command)
    if result.returncode in (126, 127):
        return "Cancelled"
    return result.stderr.strip() if result.returncode else ""


def running_flatpaks() -> set[str]:
    if not shutil.which("flatpak"):
        return set()
    return set(lines(run("flatpak", "ps", "--columns=application").stdout))


# Trash -----------------------------------------------------------------------


def scan_trash() -> tuple[int, str, str]:
    return disk_usage([TRASH]), "Deleted for good", ""


def clean_trash() -> str:
    result = run("gio", "trash", "--empty")
    return result.stderr.strip() if result.returncode else ""


# Flatpak ---------------------------------------------------------------------


def removed_app(folder: str) -> str:
    """.removed/com.brave.Browser-1ec59ab… → com.brave.Browser"""
    return folder.rsplit("-", 1)[0]


def split_running[T](folders: Iterable[T], app: Callable[[T], str]) -> tuple[list[T], list[str]]:
    """Those whose app isn't running, and the names of those that are"""
    running = running_flatpaks()
    free: list[T] = []
    busy: list[str] = []
    for folder in folders:
        if app(folder) in running:
            busy.append(app(folder))
        else:
            free.append(folder)
    return free, sorted(set(busy))


def app_caches() -> list[Path]:
    return sorted(FLATPAK_APPS.glob("*/cache"))


def scan_app_caches() -> tuple[int, str, str]:
    free, busy = split_running(app_caches(), lambda cache: cache.parent.name)
    detail = "Apps fill them again as needed"
    blocked = f"Close {', '.join(busy)}" if busy and not free else ""
    if busy and free:
        detail = f"Skips {', '.join(busy)}: running"
    size = disk_usage(free) or disk_usage(app_caches())
    return size, detail, blocked


def clean_app_caches() -> str:
    for cache in split_running(app_caches(), lambda cache: cache.parent.name)[0]:
        remove_contents(cache)
    return ""


def removed_flatpaks() -> list[Path]:
    return sorted(FLATPAK_REMOVED.glob("*"))


def scan_flatpak() -> tuple[int, str, str]:
    free, busy = split_running(removed_flatpaks(), lambda path: removed_app(path.name))
    blocked = f"Close {', '.join(busy)}" if busy and not free else ""
    size = disk_usage(free) or disk_usage(removed_flatpaks())
    return size, "Old versions, and runtimes nothing uses", blocked


def clean_flatpak() -> str:
    # Flatpak keeps a replaced version here only while it still runs
    for folder in split_running(removed_flatpaks(), lambda path: removed_app(path.name))[0]:
        shutil.rmtree(folder, ignore_errors=True)
    run("flatpak", "uninstall", "--unused", "--noninteractive", "-y")
    return ""


# Gradle ----------------------------------------------------------------------


def scan_gradle() -> tuple[int, str, str]:
    blocked = "A build is running" if run("pgrep", "-f", "GradleDaemon").returncode == 0 else ""
    return disk_usage(GRADLE), "Downloaded again by the next build", blocked


def clean_gradle() -> str:
    for folder in GRADLE:
        shutil.rmtree(folder, ignore_errors=True)
    return ""


# pacman ----------------------------------------------------------------------


def paccache_args() -> list[str]:
    kernels = lines(run("pacman", "-Qqo", "/usr/lib/modules").stdout)
    return ["-k1", *(["-i", ",".join(kernels)] if kernels else [])]


def parse_paccache(output: str) -> int:
    match = re.search(r"disk space saved: ([^)]+)\)", output)
    return parse_size(match[1]) if match else 0


def scan_pacman() -> tuple[int, str, str]:
    output = run("paccache", "-d", *paccache_args()).stdout
    return parse_paccache(output), "Keeps the newest of each, and every kernel", ""


def clean_pacman() -> str:
    return privileged("/usr/bin/paccache", "-r", *paccache_args())


# Journal ---------------------------------------------------------------------


def parse_journal(output: str) -> int:
    match = re.search(r"take up ([\d.]+\s*[KMGT]?)", output)
    return parse_size(match[1]) if match else 0


def scan_journal() -> tuple[int, str, str]:
    used = parse_journal(run("journalctl", "--disk-usage").stdout)
    return max(0, used - JOURNAL_KEEP), f"Keeps the newest {JOURNAL_KEEP // 1024**2} MB", ""


def clean_journal() -> str:
    return privileged("/usr/bin/journalctl", f"--vacuum-size={JOURNAL_KEEP // 1024**2}M")


# Nix -------------------------------------------------------------------------


def old_generations(links: Iterable[str], current: Iterable[str]) -> list[str]:
    """Numbered links of a profile (profile-9-link) that aren't current ones"""
    keep = set(current)
    return sorted(link for link in links if re.search(r"-\d+-link$", link) and link not in keep)


def nix_sizes(paths: list[str]) -> int:
    total = 0
    for start in range(0, len(paths), 500):
        output = run("nix-store", "--query", "--size", *paths[start : start + 500]).stdout
        total += sum(int(line) for line in lines(output))
    return total


def scan_nix() -> tuple[int, str, str]:
    profiles = [path.name for path in NIX_PROFILES.iterdir()] if NIX_PROFILES.exists() else []
    current_links = [p for p in profiles if not p.endswith("-link")]
    current = [str(NIX_PROFILES / p) for p in current_links]
    old = [
        str(NIX_PROFILES / link)
        for link in old_generations(profiles, [(NIX_PROFILES / p).readlink().name for p in current_links])
    ]
    dead = set(lines(run("nix-store", "--gc", "--print-dead").stdout))
    keep = set(lines(run("nix-store", "--query", "--requisites", *current).stdout)) if current else set[str]()
    stale = set(lines(run("nix-store", "--query", "--requisites", *old).stdout)) if old else set[str]()
    detail = f"{len(old)} old, no rollback to them afterwards" if old else "Nothing uses it any more"
    return nix_sizes(sorted((dead | stale) - keep)), detail, ""


def clean_nix() -> str:
    result = run("nix-collect-garbage", "-d")
    return result.stderr.strip()[-200:] if result.returncode else ""


# -----------------------------------------------------------------------------


@dataclass(frozen=True)
class Place:
    title: str
    tool: str
    scan: Callable[[], tuple[int, str, str]]  # bytes, detail, blocked
    clean: Callable[[], str]  # the error, "" if it worked


PLACES = {
    "trash": Place("Trash", "gio", scan_trash, clean_trash),
    "nix": Place("Unused Nix packages", "nix-collect-garbage", scan_nix, clean_nix),
    "pacman": Place("Package cache", "paccache", scan_pacman, clean_pacman),
    "app-cache": Place("App caches", "du", scan_app_caches, clean_app_caches),
    "flatpak": Place("Flatpak leftovers", "flatpak", scan_flatpak, clean_flatpak),
    "gradle": Place("Gradle caches", "du", scan_gradle, clean_gradle),
    "journal": Place("System logs", "journalctl", scan_journal, clean_journal),
}


def scan_place(item: tuple[str, Place]) -> dict[str, str | int] | None:
    key, place = item
    if not shutil.which(place.tool):
        return None
    try:
        size, detail, blocked = place.scan()
    except (OSError, ValueError):
        return None
    if not size:
        return None
    return {"id": key, "title": place.title, "detail": detail, "bytes": size, "blocked": blocked}


def scan() -> dict[str, object]:
    with ThreadPoolExecutor() as pool:
        found = [item for item in pool.map(scan_place, PLACES.items()) if item]
    found.sort(key=lambda item: int(item["bytes"]), reverse=True)
    return {"free": shutil.disk_usage(HOME).free, "items": found}


def clean(key: str) -> dict[str, object]:
    try:
        error = PLACES[key].clean()
    except OSError as e:
        error = str(e)
    return {"error": error} if error else {"ok": True}


def main() -> None:
    args = sys.argv[1:]
    if args == ["scan"]:
        print(json.dumps(scan()))
    elif len(args) == 2 and args[0] == "clean" and args[1] in PLACES:
        print(json.dumps(clean(args[1])))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
