#!/usr/bin/env python3
# pyright: strict
"""Stands in for GNOME Disks on the session bus (org.gnome.DiskUtility), so
Files' "Open with Disks" and "Format…" open the shell's partition editor
(disks.qml) instead. Started by D-Bus when Files calls it
(home-manager/desktop/symlinks.nix links the service file), it quits once
nobody has called it for a while.

Files calls org.gtk.Application's CommandLine with the options in its
platform data: {"options": {"block-device": "/dev/sdb1", "format-device": true}}.
That becomes `ipc.sh disks open /dev/sdb1 true`.
"""

import subprocess
from pathlib import Path
from typing import Any

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NAME = "org.gnome.DiskUtility"
PATH = "/org/gnome/DiskUtility"
IPC = Path(__file__).resolve().parent / "ipc.sh"
IDLE_SECONDS = 10
INTERFACE = """
<node>
  <interface name="org.gtk.Application">
    <method name="Activate">
      <arg type="a{sv}" name="platform_data" direction="in"/>
    </method>
    <method name="Open">
      <arg type="as" name="uris" direction="in"/>
      <arg type="s" name="hint" direction="in"/>
      <arg type="a{sv}" name="platform_data" direction="in"/>
    </method>
    <method name="CommandLine">
      <arg type="o" name="path" direction="in"/>
      <arg type="aay" name="arguments" direction="in"/>
      <arg type="a{sv}" name="platform_data" direction="in"/>
      <arg type="i" name="exit_status" direction="out"/>
    </method>
  </interface>
</node>
"""


def open_editor(device: str, format_it: bool) -> None:
    subprocess.run([str(IPC), "disks", "open", device, "true" if format_it else "false"], check=False)


def requested_device(platform_data: dict[str, Any]) -> tuple[str, bool]:
    """The device Files asks for, "" for none, and whether to format it"""
    requested: dict[str, Any] = platform_data.get("options", {})
    device = requested.get("block-device", "")
    if isinstance(device, list):
        # A byte string when it comes as one
        device = bytes(device).rstrip(b"\0").decode()  # pyright: ignore[reportUnknownArgumentType]
    return str(device), bool(requested.get("format-device", False))


class Service:
    def __init__(self, loop: GLib.MainLoop) -> None:
        self.loop = loop
        self.idle = 0
        self.restart_idle()

    def restart_idle(self) -> None:
        if self.idle:
            GLib.source_remove(self.idle)
        self.idle = GLib.timeout_add_seconds(IDLE_SECONDS, self.quit)

    def quit(self) -> bool:
        self.loop.quit()
        return GLib.SOURCE_REMOVE

    def on_call(
        self,
        _bus: Gio.DBusConnection,
        _sender: str,
        _path: str,
        _interface: str,
        method: str,
        parameters: GLib.Variant,
        invocation: Gio.DBusMethodInvocation,
    ) -> None:
        self.restart_idle()
        arguments = parameters.unpack()
        if method == "CommandLine":
            device, format_it = requested_device(arguments[2])
            open_editor(device, format_it)
            invocation.return_value(GLib.Variant("(i)", (0,)))
            return
        open_editor("", False)
        invocation.return_value(None)


def main() -> None:
    loop = GLib.MainLoop()
    service = Service(loop)
    interface = Gio.DBusNodeInfo.new_for_xml(INTERFACE).interfaces[0]

    def on_bus(bus: Gio.DBusConnection, _name: str) -> None:
        bus.register_object(PATH, interface, service.on_call, None, None)

    def on_lost(_bus: Gio.DBusConnection | None, _name: str) -> None:
        loop.quit()

    Gio.bus_own_name(Gio.BusType.SESSION, NAME, Gio.BusNameOwnerFlags.NONE, on_bus, None, on_lost)
    # pygobject-stubs leave MainLoop.run's return type unknown
    loop.run()  # pyright: ignore[reportUnknownMemberType]


if __name__ == "__main__":
    main()
