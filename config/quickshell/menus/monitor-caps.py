#!/usr/bin/env python3
# pyright: strict
"""What the connected monitors support, for Machine Settings (settings.qml):
one line each, e.g. "DP-1 vrr=1 wide=1 hdr=0".

  vrr   the kernel's vrr_capable (the driver checked monitor and link)
  wide  BT.2020 in the EDID's colorimetry block
  hdr   PQ (SMPTE ST 2084) in the EDID's HDR metadata block

Hyprland reads wide and hdr from the EDID the same way (libdisplay-info,
whose di-edid-decode this uses); modetest is libdrm's. Without one of the
tools its fields are left out: unknown, so not switched off.
"""

import re
import shutil
import subprocess
from pathlib import Path

DRM = Path("/sys/class/drm")


def parse_modetest(output: str) -> dict[str, str]:
    """vrr_capable by connector from `modetest -c`: {"DP-1": "1"}"""
    vrr: dict[str, str] = {}
    name = ""
    wanted = False
    for line in output.splitlines():
        fields = line.split()
        # "<id> <encoder> connected DP-1 <size> ..."
        if len(fields) > 3 and fields[2] in ("connected", "disconnected"):
            name = fields[3]
        elif "vrr_capable:" in line:
            wanted = True
        elif wanted and fields[:1] == ["value:"] and len(fields) > 1:
            vrr[name] = fields[1]
            wanted = False
    return vrr


def modetest(driver: str) -> str:
    """modetest opens a card by its DRM driver's name, which is the kernel
    module's, or nvidia's plus "-drm" """
    for name in (driver, f"{driver}-drm"):
        result = subprocess.run(["modetest", "-M", name, "-c"], capture_output=True, text=True, check=False)
        if result.returncode == 0:
            return result.stdout
    return ""


def vrr_capable() -> dict[str, str]:
    vrr: dict[str, str] = {}
    for card in DRM.glob("card[0-9]"):
        driver = (card / "device/driver").resolve().name
        vrr |= parse_modetest(modetest(driver))
    return vrr


def edid_caps(connector: Path) -> str:
    with (connector / "edid").open("rb") as data:
        result = subprocess.run(["di-edid-decode"], stdin=data, capture_output=True, check=False)
    edid = result.stdout.decode(errors="replace")
    wide = int("BT2020RGB" in edid)
    hdr = int("SMPTE ST2084" in edid)
    return f" wide={wide} hdr={hdr}"


def main() -> None:
    vrr = vrr_capable() if shutil.which("modetest") else None
    has_edid = shutil.which("di-edid-decode") is not None
    for connector in sorted(DRM.glob("card*-*")):
        status = connector / "status"
        if not status.exists() or status.read_text().strip() != "connected":
            continue
        name = re.sub(r"^card\d+-", "", connector.name)
        line = name
        if vrr is not None:
            line += f" vrr={vrr.get(name, '0')}"
        if has_edid:
            line += edid_caps(connector)
        print(line)


if __name__ == "__main__":
    main()
