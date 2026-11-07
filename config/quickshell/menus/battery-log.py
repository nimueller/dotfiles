# pyright: strict
"""Battery log for the battery history (battery-history.qml), run by
daemon.qml in laptop mode. Once a minute it appends the charge, energy,
power draw and state to samples.csv, and while on battery it adds up the
CPU time of every app since the last sample in apps.json, by hour (written
every 10 minutes, on exit and on SIGUSR1, which the history sends when it
opens). Both in ~/.local/state/battery-history,
kept for 30 days.

Apps: a Flatpak or systemd scope/service by its name (all of Brave's
processes are one app), else the program (argv[0]; for interpreters the
script), kernel threads as "Kernel". The CPU time says what kept the
processor busy; the screen, Wi-Fi and the rest draw power too.
"""

import json
import os
import re
import signal
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from types import FrameType
from typing import NamedTuple, NoReturn, TypedDict, cast

INTERVAL = 60
GAP = 3 * INTERVAL  # longer between two samples: suspended, not counted
KEEP_DAYS = 30
DAY = 86400
HOUR = 3600
FLUSH = 600
TICK = os.sysconf("SC_CLK_TCK")
MICRO = 1_000_000
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "battery-history"
SAMPLES = STATE / "samples.csv"
APPS = STATE / "apps.json"
POWER_SUPPLY = Path("/sys/class/power_supply")
FLATPAK_INSTALLATIONS = [Path("/var/lib/flatpak"), Path.home() / ".local/share/flatpak"]
INTERPRETERS = {"python", "python3", "node", "bash", "sh", "zsh", "perl", "ruby", "bun", "deno"}
GENERIC = {"electron", "bwrap", "zypak-helper"}  # named after the parent
NOT_AN_APP_PARENT = {"Hyprland", "systemd"}
RENAMED = {"qs": "Quickshell", "quickshell": "Quickshell"}
KERNEL = "Kernel"
STATES = {"Charging": "c", "Discharging": "d", "Full": "f", "Not charging": "n"}
UNKNOWN_STATE = "u"
DISCHARGING = "d"

# Fields of /proc/<pid>/stat after the command's ")", counted from 0
STAT_PARENT = 1
STAT_USER_TIME = 11
STAT_SYSTEM_TIME = 12
STAT_START_TIME = 19

FLATPAK_SCOPE = re.compile(r"app-flatpak-(.+?)-\d+\.scope$")
# app-Hyprland-firefox-1234.scope, app-gnome-org.gnome.Nautilus@x.service
APP_UNIT = re.compile(r"app-(?:[^-]+-)?(.+?)(?:@[^.]*)?(?:-\d+)?\.(?:scope|service)$")
VERSION_SUFFIX = re.compile(r"[\d.]+$")
WHITESPACE = re.compile(rb"\s")


@dataclass
class Battery:
    percent: int | None
    energy: float  # Wh
    power: float  # W
    state: str  # a letter of STATES


class ProcessTime(NamedTuple):
    start: str  # tells a process from a later one with the same PID
    ticks: int


class Hour(TypedDict):
    seconds: int
    apps: dict[str, float]


@dataclass
class Sample:
    time: float
    cpu: dict[int, ProcessTime]


# ---------- Battery ----------


def read_number(folder: Path, name: str) -> int | None:
    path = folder / name
    if not path.exists():
        return None
    return int(path.read_text())


def read_battery(folder: Path) -> Battery:
    energy = read_number(folder, "energy_now")  # µWh
    power = read_number(folder, "power_now")  # µW
    if energy is None:
        # Some batteries report charge (µAh) and current (µA) instead
        volts = read_number(folder, "voltage_now") or 0
        energy = (read_number(folder, "charge_now") or 0) * volts // MICRO
        power = (read_number(folder, "current_now") or 0) * volts // MICRO
    status = (folder / "status").read_text().strip()
    return Battery(
        percent=read_number(folder, "capacity"),
        energy=energy / MICRO,
        power=abs(power or 0) / MICRO,
        state=STATES.get(status, UNKNOWN_STATE),
    )


def battery() -> Battery | None:
    """The first battery that can be read."""
    for folder in sorted(POWER_SUPPLY.glob("BAT*")):
        try:
            if (folder / "type").read_text().strip() != "Battery":
                continue
            return read_battery(folder)
        except OSError:
            continue
    return None


# ---------- Apps ----------

desktop_names: dict[str, str] = {}


def desktop_file_name(app_id: str) -> str | None:
    """The Name= of an installed Flatpak's desktop file."""
    for installation in FLATPAK_INSTALLATIONS:
        desktop_file = installation / f"exports/share/applications/{app_id}.desktop"
        try:
            lines = desktop_file.read_text().splitlines()
        except OSError:
            continue
        names = [line.removeprefix("Name=") for line in lines if line.startswith("Name=")]
        return names[0] if names else None
    return None


def flatpak_name(app_id: str) -> str:
    if app_id not in desktop_names:
        fallback = app_id.rsplit(".", 1)[-1]
        desktop_names[app_id] = desktop_file_name(app_id) or fallback
    return desktop_names[app_id]


def unit_app(pid: int) -> str | None:
    """The app of the systemd scope or service the process runs in."""
    try:
        cgroup_path = Path(f"/proc/{pid}/cgroup").read_text().strip()
    except OSError:
        return None
    unit = cgroup_path.rsplit("/", 1)[-1]
    if match := FLATPAK_SCOPE.match(unit):
        return flatpak_name(match[1])
    if match := APP_UNIT.match(unit):
        # org.gnome.Nautilus -> Nautilus
        return match[1].rsplit(".", 1)[-1]
    return None


def command_line(pid: int) -> list[bytes]:
    try:
        return Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    except OSError:
        return [b""]


def program_name(argv: list[bytes]) -> str:
    """argv[0]'s file name; for an interpreter the script's, when its
    first argument looks like one."""
    program = argv[0].decode(errors="replace").split(" ")[0]
    name = os.path.basename(program)
    is_interpreter = VERSION_SUFFIX.sub("", name) in INTERPRETERS
    if not is_interpreter or len(argv) < 2:
        return name
    script = argv[1]
    looks_like_script = script != b"" and not script.startswith(b"-") and not WHITESPACE.search(script)
    if looks_like_script:
        return os.path.basename(script.decode(errors="replace"))
    return name


def stat_fields(pid: int) -> list[str]:
    """The fields of /proc/<pid>/stat after the command, which may itself
    hold spaces and parentheses."""
    stat = Path(f"/proc/{pid}/stat").read_text()
    after_command = stat[stat.rindex(")") + 2 :]
    return after_command.split()


def parent_app(pid: int, names: dict[int, str | None]) -> str | None:
    try:
        parent = int(stat_fields(pid)[STAT_PARENT])
    except (OSError, ValueError):
        return None
    app = app_of(parent, names)
    if app in NOT_AN_APP_PARENT:
        return None
    return app


def own_app(pid: int, names: dict[int, str | None]) -> str | None:
    unit = unit_app(pid)
    if unit is not None:
        return unit
    argv = command_line(pid)
    if argv[0] == b"":
        # Kernel threads have no command line
        return KERNEL
    name = program_name(argv)
    if name in GENERIC:
        parent = parent_app(pid, names)
        if parent:
            return parent
    name = name.removeprefix(".").removesuffix("-wrapped")
    return RENAMED.get(name, name) or None


def app_of(pid: int, names: dict[int, str | None]) -> str | None:
    """The app a process belongs to, cached in names for one sample."""
    if pid not in names:
        # Set first, so a loop of parents ends
        names[pid] = None
        names[pid] = own_app(pid, names)
    return names[pid]


def cpu_times() -> dict[int, ProcessTime]:
    """The CPU time of every process."""
    times: dict[int, ProcessTime] = {}
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        try:
            fields = stat_fields(pid)
        except OSError:
            continue
        ticks = int(fields[STAT_USER_TIME]) + int(fields[STAT_SYSTEM_TIME])
        times[pid] = ProcessTime(fields[STAT_START_TIME], ticks)
    return times


def seconds_by_app(before: dict[int, ProcessTime], now: dict[int, ProcessTime]) -> dict[str, float]:
    """The CPU seconds each app used between two samples. A process that
    is new (or a new one with a reused PID) counts all its time."""
    used: dict[str, float] = {}
    names: dict[int, str | None] = {}
    for pid, process in now.items():
        previous = before.get(pid)
        if previous is not None and previous.start == process.start:
            delta = process.ticks - previous.ticks
        else:
            delta = process.ticks
        if delta <= 0:
            continue
        name = app_of(pid, names)
        if name:
            used[name] = used.get(name, 0) + delta / TICK
    return used


# ---------- Files ----------


def load_apps() -> dict[str, Hour]:
    try:
        return cast(dict[str, Hour], json.loads(APPS.read_text()))
    except (OSError, ValueError):
        return {}


def save(path: Path, text: str) -> None:
    temp = path.with_suffix(".tmp")
    temp.write_text(text)
    temp.replace(path)


def sample_line(now: float, sample: Battery) -> str:
    return f"{int(now)},{sample.percent},{sample.energy:.3f},{sample.power:.2f},{sample.state}\n"


def sample_time(line: str) -> float:
    """The time of a sample, 0 for a broken line: after a hard power-off
    the last append can be on disk as NUL bytes only."""
    try:
        return float(line.split(",", 1)[0])
    except ValueError:
        return 0


def prune(apps: dict[str, Hour]) -> None:
    cutoff = time.time() - KEEP_DAYS * DAY
    old_hours = [hour for hour in apps if int(hour) < cutoff - HOUR]
    for hour in old_hours:
        del apps[hour]
    try:
        lines = SAMPLES.read_text().splitlines()
    except OSError:
        return
    kept = [line for line in lines if sample_time(line) >= cutoff]
    if len(kept) < len(lines):
        save(SAMPLES, "".join(f"{line}\n" for line in kept))


# ---------- The log ----------


def today() -> str:
    return time.strftime("%Y-%m-%d")


class BatteryLog:
    def __init__(self) -> None:
        STATE.mkdir(parents=True, exist_ok=True)
        self.apps = load_apps()
        prune(self.apps)
        self.pruned = today()
        self.flushed = time.time()
        self.dirty = False
        # The last sample on battery, None when charging or unknown
        self.last: Sample | None = None

    def flush(self) -> None:
        save(APPS, json.dumps(self.apps, separators=(",", ":")))

    def on_flush_signal(self, _signal: int, _frame: FrameType | None) -> None:
        self.flush()

    def on_stop_signal(self, _signal: int, _frame: FrameType | None) -> NoReturn:
        if self.dirty:
            self.flush()
        sys.exit(0)

    def count_cpu(self, now: float, times: dict[int, ProcessTime]) -> None:
        """Adds the CPU time since the last sample, unless the machine was
        suspended in between."""
        last = self.last
        if last is None or now - last.time > GAP:
            return
        hour_start = str(int(now // HOUR * HOUR))
        hour = self.apps.setdefault(hour_start, {"seconds": 0, "apps": {}})
        hour["seconds"] += round(now - last.time)
        for name, seconds in seconds_by_app(last.cpu, times).items():
            hour["apps"][name] = round(hour["apps"].get(name, 0) + seconds, 2)
        self.dirty = True

    def record(self, now: float) -> None:
        sample = battery()
        if sample is None or sample.percent is None:
            return
        with SAMPLES.open("a") as f:
            f.write(sample_line(now, sample))
        if sample.state != DISCHARGING:
            self.last = None
            return
        times = cpu_times()
        self.count_cpu(now, times)
        self.last = Sample(now, times)

    def prune_daily(self) -> None:
        if today() == self.pruned:
            return
        prune(self.apps)
        self.pruned = today()
        self.dirty = True

    def flush_when_due(self) -> None:
        if not self.dirty or time.time() - self.flushed < FLUSH:
            return
        self.flush()
        self.flushed = time.time()
        self.dirty = False

    def run(self) -> NoReturn:
        while True:
            self.record(time.time())
            self.prune_daily()
            self.flush_when_due()
            time.sleep(INTERVAL - time.time() % INTERVAL)


def main() -> None:
    log = BatteryLog()
    signal.signal(signal.SIGUSR1, log.on_flush_signal)
    signal.signal(signal.SIGTERM, log.on_stop_signal)
    signal.signal(signal.SIGHUP, log.on_stop_signal)
    log.run()


if __name__ == "__main__":
    main()
