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
from pathlib import Path

INTERVAL = 60
GAP = 3 * INTERVAL  # longer between two samples: suspended, not counted
KEEP_DAYS = 30
FLUSH = 600
TICK = os.sysconf("SC_CLK_TCK")
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "battery-history"
SAMPLES = STATE / "samples.csv"
APPS = STATE / "apps.json"
INTERPRETERS = {"python", "python3", "node", "bash", "sh", "zsh", "perl", "ruby", "bun", "deno"}
GENERIC = {"electron", "bwrap", "zypak-helper"}  # named after the parent
STATES = {"Charging": "c", "Discharging": "d", "Full": "f", "Not charging": "n"}


def battery():
    for d in sorted(Path("/sys/class/power_supply").glob("BAT*")):
        try:
            if (d / "type").read_text().strip() != "Battery":
                continue

            def num(name, d=d):
                f = d / name
                return int(f.read_text()) if f.exists() else None

            energy, power = num("energy_now"), num("power_now")
            if energy is None:  # charge (µAh) and current (µA) instead
                volts = num("voltage_now") or 0
                energy = (num("charge_now") or 0) * volts // 1_000_000
                power = (num("current_now") or 0) * volts // 1_000_000
            status = (d / "status").read_text().strip()
            return {
                "percent": num("capacity"),
                "energy": energy / 1e6,  # Wh
                "power": abs(power or 0) / 1e6,  # W
                "state": STATES.get(status, "u"),
            }
        except OSError:
            continue
    return None


desktop_names = {}


def flatpak_name(app_id):
    if app_id not in desktop_names:
        name = app_id.rsplit(".", 1)[-1]
        for base in ("/var/lib/flatpak", Path.home() / ".local/share/flatpak"):
            try:
                for line in (Path(base) / f"exports/share/applications/{app_id}.desktop").read_text().splitlines():
                    if line.startswith("Name="):
                        name = line[5:]
                        break
                break
            except OSError:
                continue
        desktop_names[app_id] = name
    return desktop_names[app_id]


def app_of(pid, names):
    if pid not in names:
        names[pid] = None  # against loops
        names[pid] = own_app(pid, names)
    return names[pid]


def own_app(pid, names):
    try:
        cgroup = Path(f"/proc/{pid}/cgroup").read_text().strip().rsplit("/", 1)[-1]
    except OSError:
        cgroup = ""
    if m := re.match(r"app-flatpak-(.+?)-\d+\.scope$", cgroup):
        return flatpak_name(m[1])
    # app-Hyprland-firefox-1234.scope, app-gnome-org.gnome.Nautilus@x.service
    if m := re.match(r"app-(?:[^-]+-)?(.+?)(?:@[^.]*)?(?:-\d+)?\.(?:scope|service)$", cgroup):
        return m[1].rsplit(".", 1)[-1] if "." in m[1] else m[1]
    try:
        argv = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    except OSError:
        argv = [b""]
    if not argv[0]:  # kernel threads have no command line
        return "Kernel"
    name = os.path.basename(argv[0].decode(errors="replace").split(" ")[0])
    if re.sub(r"[\d.]+$", "", name) in INTERPRETERS:
        if len(argv) > 1 and argv[1] and not argv[1].startswith(b"-") and not re.search(rb"\s", argv[1]):
            name = os.path.basename(argv[1].decode(errors="replace"))
    if name in GENERIC:
        try:
            stat = Path(f"/proc/{pid}/stat").read_text()
            parent = app_of(int(stat[stat.rindex(")") + 2 :].split()[1]), names)
        except (OSError, ValueError):
            parent = None
        if parent and parent not in ("Hyprland", "systemd"):
            return parent
    name = name.removeprefix(".").removesuffix("-wrapped")
    return {"qs": "Quickshell", "quickshell": "Quickshell"}.get(name, name) or None


def cpu_times():
    """{pid: (start time, ticks)} of every process."""
    out = {}
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        try:
            stat = Path(f"/proc/{entry.name}/stat").read_text()
        except OSError:
            continue
        f = stat[stat.rindex(")") + 2 :].split()
        out[int(entry.name)] = (f[19], int(f[11]) + int(f[12]))
    return out


def load_apps():
    try:
        return json.loads(APPS.read_text())
    except (OSError, ValueError):
        return {}


def save(path, text):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(text)
    tmp.replace(path)


def prune(apps):
    cutoff = time.time() - KEEP_DAYS * 86400
    for hour in [h for h in apps if int(h) < cutoff - 3600]:
        del apps[hour]
    try:
        lines = SAMPLES.read_text().splitlines()
    except OSError:
        return
    kept = [line for line in lines if float(line.split(",", 1)[0]) >= cutoff]
    if len(kept) < len(lines):
        save(SAMPLES, "".join(f"{line}\n" for line in kept))


def main():
    STATE.mkdir(parents=True, exist_ok=True)
    apps = load_apps()
    prune(apps)
    pruned = time.strftime("%Y-%m-%d")
    flushed = time.time()
    dirty = False
    last = None  # (time, state, cpu times)

    def flush():
        save(APPS, json.dumps(apps, separators=(",", ":")))

    def stop(*_):
        if dirty:
            flush()
        sys.exit(0)

    signal.signal(signal.SIGUSR1, lambda *_: flush())
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGHUP, stop)
    while True:
        now = time.time()
        bat = battery()
        if bat and bat["percent"] is not None:
            with SAMPLES.open("a") as f:
                f.write(f"{int(now)},{bat['percent']},{bat['energy']:.3f},{bat['power']:.2f},{bat['state']}\n")

            if bat["state"] == "d":
                times = cpu_times()
                if last and last[1] == "d" and now - last[0] <= GAP:
                    hour = apps.setdefault(str(int(now // 3600 * 3600)), {"seconds": 0, "apps": {}})
                    hour["seconds"] += round(now - last[0])
                    used, names = {}, {}
                    for pid, (start, ticks) in times.items():
                        before = last[2].get(pid)
                        delta = ticks - before[1] if before and before[0] == start else ticks
                        if delta > 0 and (name := app_of(pid, names)):
                            used[name] = used.get(name, 0) + delta / TICK
                    for name, seconds in used.items():
                        hour["apps"][name] = round(hour["apps"].get(name, 0) + seconds, 2)
                    dirty = True
                last = (now, "d", times)
            else:
                last = None

        if time.strftime("%Y-%m-%d") != pruned:
            prune(apps)
            pruned = time.strftime("%Y-%m-%d")
            dirty = True
        if dirty and time.time() - flushed >= FLUSH:
            flush()
            flushed = time.time()
            dirty = False
        time.sleep(INTERVAL - time.time() % INTERVAL)


if __name__ == "__main__":
    main()
