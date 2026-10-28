#!/usr/bin/env python3
"""Helper of the scanner window (scan.qml), around SANE's scanimage.

  scan.py devices
      The scanners as JSON: [{ device, name, backend, ip }]
  scan.py options DEVICE
      What it offers as JSON: { resolutions, modes, sources, width, height }
      (the area in mm) and the defaults (resolution, mode, source)
  scan.py scan DEVICE DIR PREFIX SOURCE MODE DPI L T W H [COUNT]
      Scan into DIR/PREFIX-NNN.png (the area in mm): all pages in the
      feeder, or COUNT of them. Prints "progress <percent>" and
      "page <file>" as it goes, and "error <message>" if it fails.
  scan.py feeder IP
      "loaded" once the scanner is idle with paper in its feeder, else
      "empty" (from its eSCL status; "unknown" without one)
  scan.py save pdf|ocr|jpg|png FILE PAGE:DEGREES...
      Save the pages (turned by DEGREES): one PDF (`ocr`: with the text
      Tesseract reads, so it can be searched and copied), or one image each
      (FILE then gets -1, -2, … before the extension). Prints the files,
      then notifies.

Only network scanners: sane-airscan (eSCL and WSD) and, if it's installed,
Epson's own backend (epsonscan2, AUR), which gets every page from the feeder
where the eSCL of some models hands over only the first. With every backend
installed, scanimage takes ~10 s to look for scanners instead of ~1 s, and
the escl backend prints printers' web pages as it goes.
"""

import ctypes
import glob
import json
import os
import re
import shutil
import signal
import ssl
import subprocess
import sys
import tempfile
import threading
import urllib.request
from pathlib import Path

CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "qs-scan"
EPSON_CONF = Path.home() / ".epsonscan2/Network/epsonscan2.conf"
A4_HEIGHT = 297.18  # mm
COMMON_DPI = [75, 100, 150, 200, 300, 600, 1200]
IP = r"\d+\.\d+\.\d+\.\d+"


def sane_env():
    """scanimage with only the network backends (see above)"""
    conf = CACHE / "sane"
    conf.mkdir(parents=True, exist_ok=True)
    backends = ["airscan"]
    if glob.glob("/usr/lib/sane/libsane-epsonscan2.so*"):
        backends.append("epsonscan2")
    (conf / "dll.conf").write_text("\n".join(backends) + "\n")
    # The trailing colon: then the system's configuration too (airscan.conf)
    return {**os.environ, "SANE_CONFIG_DIR": f"{conf}:"}, backends


def scanimage(*args, env):
    try:
        return subprocess.run(
            ["scanimage", *args], check=False, env=env, capture_output=True, text=True, timeout=30
        ).stdout
    except subprocess.TimeoutExpired:
        return ""


def list_devices(env):
    # airscan names the address as the type ("ip=…"), epsonscan2 at the end
    # of the device ("epsonscan2:networkscanner:esci2:network:<ip>")
    devices = []
    for line in scanimage("-f", "%d\t%v %m\t%t%n", env=env).splitlines():
        fields = line.split("\t")
        if len(fields) != 3:
            continue
        device, name, kind = fields
        ip = re.search(rf"ip=({IP})", kind) or re.search(rf":({IP})$", device)
        devices.append(
            {
                "device": device,
                "name": re.sub(r"^(eSCL|WSD) ", "", name),
                "backend": device.split(":")[0],
                "ip": ip.group(1) if ip else "",
            }
        )
    return devices


def devices():
    """epsonscan2 doesn't look for scanners in the network itself: it lists
    the addresses in its configuration, one per line, whether they answer or
    not. So that's kept to the Epson scanners airscan finds, and only those
    epsonscan2 devices are listed, first, as they get every page from the
    feeder. Its model is "network scanner": they get airscan's name."""
    env, backends = sane_env()
    found = list_devices(env)
    if "epsonscan2" in backends:
        epson = sorted(
            {d["ip"] for d in found if d["backend"] != "epsonscan2" and d["ip"] and "epson" in d["name"].lower()}
        )
        listed = (
            sorted(set(re.findall(rf"^{IP}$", EPSON_CONF.read_text(), re.MULTILINE))) if EPSON_CONF.exists() else []
        )
        if epson and epson != listed:
            EPSON_CONF.parent.mkdir(parents=True, exist_ok=True)
            EPSON_CONF.write_text("[Network]\n" + "".join(f"{ip}\n" for ip in epson))
            found = list_devices(env)

    names = {d["ip"]: d["name"] for d in found if d["backend"] != "epsonscan2" and d["ip"]}
    result = []
    for d in found:
        if d["backend"] == "epsonscan2":
            if d["ip"] not in names:
                continue
            if "network scanner" in d["name"].lower():
                d["name"] = names[d["ip"]]
        result.append(d)
    result.sort(key=lambda d: d["backend"] != "epsonscan2")
    print(json.dumps(result))


OPTION = re.compile(r"^\s+(--[\w-]+|-[xy]) (.+) \[([^\]]*)\]$")


def parse_options(text):
    """From `scanimage -A`, lines like
    --resolution 100|200|300|600|1200dpi [300]
    --resolution 50..1200dpi (in steps of 1) [200]
    --source Flatbed|ADF [Flatbed]
    -y 0..297.18mm [297.18]"""
    found = {}  # name: (values, default)
    for line in text.splitlines():
        if m := OPTION.match(line):
            name, values, current = m.groups()
            values = re.sub(r"\s*\(in steps of [^)]*\)$", "", values)
            found[name] = (re.sub(r"(dpi|mm)$", "", values), re.sub(r"(dpi|mm)$", "", current))
    if not found:
        return None

    def choices(name):
        values = found.get(name, ("", ""))[0]
        return list(dict.fromkeys(values.split("|"))) if values else []

    def default(name):
        return found.get(name, ("", None))[1]

    def maximum(name):
        return float(found.get(name, ("0", ""))[0].split("..")[-1])

    # A range ("50..1200"): the usual steps in it
    dpi = found.get("--resolution", ("", ""))[0]
    if ".." in dpi:
        low, high = map(float, dpi.split(".."))
        resolutions = [r for r in COMMON_DPI if low <= r <= high]
    else:
        resolutions = [int(r) for r in choices("--resolution") if r.isdigit()]
    resolution = default("--resolution") or ""

    return {
        "resolutions": resolutions,
        "modes": choices("--mode"),
        "sources": choices("--source"),
        "resolution": int(resolution) if resolution.isdigit() else None,
        "mode": default("--mode"),
        "source": default("--source"),
        "width": maximum("-x"),
        # At most A4: Epson offers the 14" of its feeder, which leaves the
        # rest of an A4 page blank
        "height": min(maximum("-y"), A4_HEIGHT),
    }


def options(device):
    env, _ = sane_env()
    found = parse_options(scanimage("-d", device, "-A", env=env))
    print(json.dumps(found or {"error": "The scanner doesn't answer"}))
    if not found:
        sys.exit(1)


def run(*command, **kwargs):
    """True if it worked; the caller reports a failure"""
    return subprocess.run([str(c) for c in command], check=False, **kwargs).returncode == 0


def say(lock, line):
    with lock:
        print(line, flush=True)


def scan(device, folder, prefix, source, mode, dpi, left, top, width, height, count=None):
    env, _ = sane_env()
    Path(folder).mkdir(parents=True, exist_ok=True)
    args = ["-d", device, "--source", source, "--mode", mode, "--resolution", dpi]
    args += ["-l", left, "-t", top, "-x", width, "-y", height]
    args += ["--format=png", f"--batch={folder}/{prefix}-%03d.png", "--batch-print", "--progress"]
    if count:
        args.append(f"--batch-count={count}")
    # Epson's leaves out blank pages by default: the backs of pages printed on
    # one side, which would put the pages out of order with both sides
    if device.startswith("epsonscan2:"):
        args += ["--skip-blankpages", "0"]

    # Stopped by the window (SIGTERM), the scan stops too; killed, the
    # kernel stops it (PR_SET_PDEATHSIG)
    def die_with_parent():
        ctypes.CDLL(None).prctl(1, signal.SIGTERM)

    proc = subprocess.Popen(
        ["scanimage", *args],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        # Before the thread below starts, so the warning about threads doesn't apply
        preexec_fn=die_with_parent,  # noqa: PLW1509
    )
    assert proc.stdout and proc.stderr
    signal.signal(signal.SIGTERM, lambda *_: proc.terminate())
    lock = threading.Lock()

    # The progress, with \r, and the errors come on stderr; text mode reads
    # \r as a line end
    def errors(stderr):
        for line in stderr:
            if m := re.match(r"Progress: ([\d.]+)%", line):
                say(lock, f"progress {m.group(1)}")
            elif "out of documents" in line:
                say(lock, "error The feeder is empty")
            elif line.startswith("scanimage: rounded value"):
                pass  # a note on an option, e.g. a resolution it doesn't offer
            elif m := re.match(r"scanimage: (?:sane_\w+: )?(.*)", line):
                say(lock, f"error {m.group(1)}")

    reader = threading.Thread(target=errors, args=(proc.stderr,))
    reader.start()
    # --batch-print names each page on stdout
    for line in proc.stdout:
        say(lock, f"page {line.strip()}")
    reader.join()
    sys.exit(proc.wait())


def feeder(ip):
    """Only while the scanner is idle: it reports the feeder loaded while it
    pulls a page in, too. Scanners use self-signed certificates."""
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    try:
        with urllib.request.urlopen(f"https://{ip}/eSCL/ScannerStatus", timeout=3, context=context) as reply:
            status = reply.read().decode(errors="replace")
    except OSError:
        print("unknown")
        return
    if "<scan:AdfState>" not in status:
        print("unknown")
    elif "<pwg:State>Idle<" in status and "<scan:AdfState>ScannerAdfLoaded<" in status:
        print("loaded")
    else:
        print("empty")


def notify(*args):
    # Keep waiting for a click on an action for a while, not forever
    try:
        return subprocess.run(
            ["notify-send", "-a", "Scanner", *args], check=False, capture_output=True, text=True, timeout=300
        ).stdout.strip()
    except subprocess.TimeoutExpired:
        return ""


def unused(file):
    """Never over an earlier scan: "Name (2).pdf" (images: "Name (2)-1.jpg")"""
    path, n = Path(file), 1
    candidate = path
    while candidate.exists() or candidate.with_name(f"{candidate.stem}-1{candidate.suffix}").exists():
        n += 1
        candidate = path.with_name(f"{path.stem} ({n}){path.suffix}")
    return candidate


def save(kind, file, *pages):
    target = unused(file)
    target.parent.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=CACHE, prefix="save-") as work:
        # Each page turned, as JPEG for a PDF (a PNG of a colour page at 300
        # dpi makes a PDF ~10× as big); the resolution stays in it, so the
        # PDF's pages get their real size
        turned = []
        for i, arg in enumerate(pages, 1):
            page, degrees = arg.rsplit(":", 1)
            dst = Path(work) / f"{i:03d}.{'png' if kind == 'png' else 'jpg'}"
            if not run("magick", page, "-rotate", degrees, "-quality", "85", dst):
                notify("-u", "critical", "-i", "dialog-error", "Scan not saved", f"ImageMagick couldn't read page {i}")
                sys.exit(1)
            turned.append(dst)

        if kind == "pdf":
            ok = run("magick", *turned, "-compress", "jpeg", "-quality", "85", target)
            written = [target] if ok else []
        elif kind == "ocr":
            (Path(work) / "list.txt").write_text("".join(f"{p}\n" for p in turned))
            base = target.with_suffix("")
            ok = run("tesseract", Path(work) / "list.txt", base, "-l", "deu+eng", "pdf", stderr=subprocess.DEVNULL)
            written = [target] if ok else []
        elif len(turned) == 1:
            written = [Path(shutil.copy(turned[0], target))]
        else:
            written = [
                Path(shutil.copy(p, target.with_name(f"{target.stem}-{i}{target.suffix}")))
                for i, p in enumerate(turned, 1)
            ]

    if not written:
        notify("-u", "critical", "-i", "dialog-error", "Scan not saved", f"Couldn't write {target.name}")
        sys.exit(1)
    for f in written:
        print(f, flush=True)

    # The notification waits for a click: in a process of its own, without
    # the window's stdout, so the window gets its answer now
    subprocess.Popen(
        [sys.executable, __file__, "saved", written[0], str(len(pages))],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def saved(file, count):
    """The notification after save, with Open and Show in folder"""
    what = "1 page" if count == "1" else f"{count} pages"
    action = notify("-e", "-A", "open=Open", "-A", "folder=Show in folder", "Scan saved", f"{Path(file).name} · {what}")
    if action in ("open", "folder"):
        run("xdg-open", file if action == "open" else Path(file).parent)


COMMANDS = {"devices": devices, "options": options, "scan": scan, "feeder": feeder, "save": save, "saved": saved}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    COMMANDS[sys.argv[1]](*sys.argv[2:])
