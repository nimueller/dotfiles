#!/usr/bin/env python3
# pyright: strict
"""Waiting updates, for the bar's update chip and the system menu (Updates.qml).

  updates.py

Prints one JSON object:

  {"pacman": 12, "aur": 2, "flatpak": 1, "aurHelper": "yay",
   "flakeAge": 3, "flakeStale": false,
   "security": [{"package": "linux", "issue": "AVG-2908", "severity": "High"}],
   "news": [{"title": "…", "link": "https://archlinux.org/news/…", "date": "2026-10-21"}],
   "lastUpgrade": 11, "upgradeStale": false}

A count is null when its tool is missing or failed (no AUR helper, no
Flatpak, checkupdates offline). flakeAge is the age of the dotfiles'
flake.lock in days: the time since its newest input was updated, null
without the file. CI updates it every week, so a lock older than
FLAKE_STALE_DAYS means this checkout hasn't been pulled (and switched).

What makes the waiting updates worth the bar's chip:
- security: the waiting pacman updates that fix an issue of the Arch
  security tracker (any severity), the installed version still affected;
- news: Arch's news since the last full upgrade, which often ask for a
  manual step before the next one;
- upgradeStale: the last full upgrade that went through (lastUpgrade,
  days, from pacman.log) is more than UPGRADE_STALE_DAYS old.
Without a full upgrade in the log, news and lastUpgrade are empty and null.

The three checks ask the network and take about a second each, so they run
at the same time, as do the downloads of the tracker and the news. Those
are kept for CACHE_MAX_AGE in ~/.cache/quickshell-updates; offline the old
copy is used.
"""

import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import cast

# config/quickshell/menus/updates.py, linked into ~/.config
FLAKE_LOCK = Path(__file__).resolve().parents[3] / "flake.lock"
FLAKE_STALE_DAYS = 14
UPGRADE_STALE_DAYS = 14
AUR_HELPERS = ["paru", "yay"]
PACMAN_LOG = Path("/var/log/pacman.log")
ISSUES_URL = "https://security.archlinux.org/issues/all.json"
NEWS_URL = "https://archlinux.org/feeds/news/"
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "quickshell-updates"
CACHE_MAX_AGE = 6 * 3600


def count_lines(output: str) -> int:
    return sum(1 for line in output.splitlines() if line.strip())


def parse_updates(output: str) -> dict[str, tuple[str, str]]:
    """checkupdates: "name old -> new" → {name: (old, new)}"""
    updates: dict[str, tuple[str, str]] = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[2] == "->":
            updates[parts[0]] = (parts[1], parts[3])
    return updates


def flake_age(lock: str, now: float) -> int | None:
    """Whole days since the newest locked input"""
    try:
        nodes = json.loads(lock)["nodes"]
        newest = max(node["locked"]["lastModified"] for node in nodes.values() if "locked" in node)
    except (ValueError, KeyError, TypeError):
        return None
    return max(0, int((now - newest) // 86400))


def last_upgrade(log: str) -> float | None:
    """When the last full upgrade in pacman.log (pacman -Syu, also through
    yay or paru) started that got through: its "starting full system
    upgrade" followed by "transaction completed" before pacman's next
    command. One that failed, e.g. on a download, upgraded nothing."""
    last: float | None = None
    started: float | None = None
    for line in log.splitlines():
        if line.endswith("[PACMAN] starting full system upgrade"):
            try:
                started = datetime.strptime(line[1 : line.index("]")], "%Y-%m-%dT%H:%M:%S%z").timestamp()
            except ValueError:
                started = None
        elif "] [PACMAN] Running " in line:
            started = None
        elif line.endswith("[ALPM] transaction completed") and started is not None:
            last, started = started, None
    return last


def vercmp(a: str, b: str) -> int:
    """pacman's version comparison: < 0, 0 or > 0"""
    result = subprocess.run(["vercmp", a, b], capture_output=True, text=True, check=False)
    try:
        return int(result.stdout)
    except ValueError:
        return 0


def security_fixes(
    updates: dict[str, tuple[str, str]], issues: str, compare: Callable[[str, str], int] = vercmp
) -> list[dict[str, str]]:
    """The waiting updates that fix a tracker issue: the installed version
    is older than the fixed one, the new one isn't"""
    try:
        groups: object = json.loads(issues)
    except ValueError:
        return []
    fixes: list[dict[str, str]] = []
    for group in cast(list[object], groups) if isinstance(groups, list) else []:
        if not isinstance(group, dict):
            continue
        fields = cast(dict[str, object], group)
        fixed, packages = fields.get("fixed"), fields.get("packages")
        if not isinstance(fixed, str) or not fixed or not isinstance(packages, list):
            continue
        for package in cast(list[object], packages):
            if not isinstance(package, str) or package not in updates:
                continue
            old, new = updates[package]
            if compare(old, fixed) < 0 <= compare(new, fixed):
                issue, severity = str(fields.get("name", "")), str(fields.get("severity", ""))
                fixes.append({"package": package, "issue": issue, "severity": severity})
    return fixes


def news_since(rss: str, since: float) -> list[dict[str, str]]:
    """The items of Arch's news feed published after `since`, newest first"""
    try:
        root = ET.fromstring(rss)
    except ET.ParseError:
        return []
    news: list[tuple[float, dict[str, str]]] = []
    for item in root.iter("item"):
        try:
            published = parsedate_to_datetime(item.findtext("pubDate") or "")
        except (TypeError, ValueError):
            continue
        if published.timestamp() > since:
            entry = {
                "title": (item.findtext("title") or "").strip(),
                "link": (item.findtext("link") or "").strip(),
                "date": published.date().isoformat(),
            }
            news.append((published.timestamp(), entry))
    return [entry for _, entry in sorted(news, key=lambda n: -n[0])]


def fetch(url: str, name: str) -> str:
    """The download, kept in CACHE for CACHE_MAX_AGE; the old copy when
    offline, "" without one"""
    cache = CACHE / name
    try:
        if cache.is_file() and time.time() - cache.stat().st_mtime < CACHE_MAX_AGE:
            return cache.read_text()
        with urllib.request.urlopen(url, timeout=15) as response:
            data: bytes = response.read()
        CACHE.mkdir(parents=True, exist_ok=True)
        cache.write_bytes(data)
        return data.decode()
    except (OSError, UnicodeDecodeError):
        try:
            return cache.read_text()
        except OSError:
            return ""


def read(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except OSError:
        return ""


def main(args: list[str]) -> int:
    if args:
        print(__doc__, file=sys.stderr)
        return 2

    aur_helper = next((h for h in AUR_HELPERS if shutil.which(h)), None)
    # The command and the exit codes that mean it worked: checkupdates
    # exits with 2 when there are none (1 is an error), yay and paru with 1,
    # like pacman -Qu
    commands = {
        "pacman": (["checkupdates"], (0, 2)) if shutil.which("checkupdates") else None,
        "aur": ([aur_helper, "-Qua"], (0, 1)) if aur_helper else None,
        "flatpak": (["flatpak", "remote-ls", "--updates", "--columns=application"], (0,))
        if shutil.which("flatpak")
        else None,
    }
    running = {
        name: subprocess.Popen(command[0], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        for name, command in commands.items()
        if command
    }
    with ThreadPoolExecutor() as pool:
        issues = pool.submit(fetch, ISSUES_URL, "issues.json")
        feed = pool.submit(fetch, NEWS_URL, "news.xml")

        result: dict[str, object] = {}
        pacman: dict[str, tuple[str, str]] = {}
        for name, command in commands.items():
            process = running.get(name)
            if not process or not command:
                result[name] = None
                continue
            output, _ = process.communicate()
            if process.returncode not in command[1]:
                result[name] = None
            elif name == "pacman":
                pacman = parse_updates(output)
                result[name] = len(pacman)
            else:
                result[name] = count_lines(output)

        now = time.time()
        upgraded = last_upgrade(read(PACMAN_LOG))
        result["security"] = security_fixes(pacman, issues.result()) if pacman else []
        result["news"] = news_since(feed.result(), upgraded) if upgraded is not None else []

    try:
        age = flake_age(FLAKE_LOCK.read_text(), now)
    except OSError:
        age = None
    result["aurHelper"] = aur_helper
    result["flakeAge"] = age
    result["flakeStale"] = age is not None and age > FLAKE_STALE_DAYS
    days = None if upgraded is None else max(0, int((now - upgraded) // 86400))
    result["lastUpgrade"] = days
    result["upgradeStale"] = days is not None and days > UPGRADE_STALE_DAYS
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
