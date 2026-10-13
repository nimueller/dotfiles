"""KDE Connect for the bar's phone chip and menu (Bar.qml, kdeconnect.qml),
over kdeconnectd's D-Bus interface, with the system's Python like drives.py.

  kdeconnect.py watch           print the paired devices as a JSON line on
                                every change; also mounts reachable phones
                                (SFTP) and keeps a Files sidebar bookmark
                                for their storage while it's mounted
  kdeconnect.py ring ID         make the phone ring
  kdeconnect.py ping ID         send a ping
  kdeconnect.py clipboard ID    send the clipboard
  kdeconnect.py send ID         pick files (file chooser portal) and send them
  kdeconnect.py browse ID       mount the phone and show it in Files
"""

import json
import os
import re
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

SERVICE = "org.kde.kdeconnect"
ROOT = "/modules/kdeconnect"
IFACE = "org.kde.kdeconnect.device"
BOOKMARKS = os.path.join(GLib.get_user_config_dir(), "gtk-3.0", "bookmarks")
RUNTIME_URI = GLib.filename_to_uri(GLib.get_user_runtime_dir(), None)

bus = Gio.bus_get_sync(Gio.BusType.SESSION)


def call(path, iface, method, args=None, timeout=-1):
    reply = bus.call_sync(SERVICE, path, iface, method, args, None, Gio.DBusCallFlags.NONE, timeout, None)
    return reply.unpack()


def props(path, iface):
    try:
        return call(path, "org.freedesktop.DBus.Properties", "GetAll", GLib.Variant("(s)", (iface,)))[0]
    except GLib.Error:
        return {}  # the plugin isn't loaded


def device_path(device_id):
    return f"{ROOT}/devices/{device_id}"


def plugin(device_id, name):
    return f"{device_path(device_id)}/{name}", f"{IFACE}.{name}"


def storage(device_id):
    """The phone's folders in its mount, [(path, name)]: none while the phone
    doesn't let KDE Connect at its files. The mount's top folder itself can't
    be listed."""
    try:
        return list(call(*plugin(device_id, "sftp"), "getDirectories")[0].items())
    except GLib.Error:
        return []


def notify(summary, body="", icon="kdeconnect"):
    bus.call_sync(
        "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
        "Notify",
        GLib.Variant("(susssasa{sv}i)", ("KDE Connect", 0, icon, summary, body, [], {}, -1)),
        None,
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    )


# Watching -------------------------------------------------------------------


def devices():
    """The paired devices, with what the bar and the menu show."""
    try:
        ids = call(ROOT, "org.kde.kdeconnect.daemon", "devices", GLib.Variant("(bb)", (False, True)))[0]
    except GLib.Error:
        return []  # kdeconnectd isn't running
    result = []
    for device_id in ids:
        device = props(device_path(device_id), IFACE)
        battery = props(*plugin(device_id, "battery"))
        network = props(*plugin(device_id, "connectivity_report"))
        mounted = False
        if device.get("isReachable"):
            try:
                mounted = call(*plugin(device_id, "sftp"), "isMounted")[0]
            except GLib.Error:
                pass
        folders = storage(device_id) if mounted else []
        result.append(
            {
                "id": device_id,
                "name": device.get("name", device_id),
                "type": device.get("type", "phone"),
                "reachable": device.get("isReachable", False),
                "battery": battery.get("charge", -1) if battery.get("hasBattery") else -1,
                "charging": battery.get("isCharging", False),
                "network": network.get("cellularNetworkType", ""),
                "signal": network.get("cellularNetworkStrength", -1),
                "mounted": mounted,
                "storage": folders,
            }
        )
    return result


def sync_bookmarks(wanted):
    """Files sidebar bookmarks for the phones' storage folders ({id: [(path,
    label)]}), none for the others. Only touches bookmarks inside KDE
    Connect's mount points."""
    try:
        with open(BOOKMARKS) as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        lines = []
    ours = re.compile(re.escape(RUNTIME_URI) + r"/[0-9A-Za-z_]{16,}(?:/|\s|$)")
    want = [f"{GLib.filename_to_uri(path, None)} {label}" for folders in wanted.values() for path, label in folders]
    kept = [line for line in lines if not ours.match(line) or line in want]
    kept += [line for line in want if line not in kept]
    if kept != lines:
        os.makedirs(os.path.dirname(BOOKMARKS), exist_ok=True)
        with open(BOOKMARKS + ".tmp", "w") as f:
            f.write("".join(f"{line}\n" for line in kept))
        os.replace(BOOKMARKS + ".tmp", BOOKMARKS)


class Watch:
    def __init__(self):
        self.last = None
        self.mount_tried = set()  # reachable devices that were asked to mount once
        self.pending = 0
        # Any change of kdeconnectd: devices, reachability, battery, mounts
        bus.signal_subscribe(SERVICE, None, None, None, None, Gio.DBusSignalFlags.NONE, self.changed)
        Gio.bus_watch_name_on_connection(
            bus, SERVICE, Gio.BusNameWatcherFlags.NONE, lambda *_: self.changed(), lambda *_: self.changed()
        )
        self.update()

    @staticmethod
    def labels(device):
        """The bookmarks of a phone's folders: its name, plus the folder's
        when it has more than one (an SD card)."""
        folders = device["storage"]
        if len(folders) == 1:
            return [(folders[0][0], device["name"])]
        return [(path, f"{device['name']}: {name}") for path, name in folders]

    def changed(self, *_):
        if not self.pending:
            self.pending = GLib.timeout_add(300, self.update)

    def update(self):
        self.pending = 0
        state = devices()
        for device in state:
            if not device["reachable"]:
                self.mount_tried.discard(device["id"])
            elif not device["storage"] and device["id"] not in self.mount_tried:
                # Not mounted, or mounted before the phone allowed access:
                # once per connection, as it fails again until it does
                self.mount_tried.add(device["id"])
                path, iface = plugin(device["id"], "sftp")
                if device["mounted"]:
                    call(path, iface, "unmount")
                bus.call(SERVICE, path, iface, "mount", None, None, Gio.DBusCallFlags.NONE, -1, None, None)
        sync_bookmarks({d["id"]: self.labels(d) for d in state})
        line = json.dumps(state)
        if line != self.last:
            self.last = line
            print(line, flush=True)
        return GLib.SOURCE_REMOVE


# Actions --------------------------------------------------------------------


def choose_files(title):
    """URIs of the files picked in the file chooser portal, [] if cancelled."""
    token = f"kdeconnect{os.getpid()}"
    sender = bus.get_unique_name()[1:].replace(".", "_")
    handle = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
    loop = GLib.MainLoop()
    uris = []

    def response(_bus, _sender, _path, _iface, _signal, params):
        code, results = params.unpack()
        if code == 0:
            uris.extend(results.get("uris", []))
        loop.quit()

    bus.signal_subscribe(
        "org.freedesktop.portal.Desktop",
        "org.freedesktop.portal.Request",
        "Response",
        handle,
        None,
        Gio.DBusSignalFlags.NONE,
        response,
    )
    options = {
        "handle_token": GLib.Variant("s", token),
        "multiple": GLib.Variant("b", True),
        "accept_label": GLib.Variant("s", "_Send"),
    }
    bus.call_sync(
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.FileChooser",
        "OpenFile",
        GLib.Variant("(ssa{sv})", ("", title, options)),
        None,
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    )
    loop.run()
    return uris


def browse(device_id, name):
    path, iface = plugin(device_id, "sftp")
    folders = []
    if call(path, iface, "mountAndWait", timeout=30000)[0]:
        folders = storage(device_id)
        if not folders:
            # Mounted before the phone allowed access: mount again
            call(path, iface, "unmount")
            if call(path, iface, "mountAndWait", timeout=30000)[0]:
                folders = storage(device_id)
    if folders:
        Gio.AppInfo.launch_default_for_uri(GLib.filename_to_uri(folders[0][0], None), None)
        return
    error = call(path, iface, "getMountError")[0] or "The phone didn't share any folders."
    if "Permissions missing" in error or not folders:
        error += " Allow it on the phone: KDE Connect, the computer, Plugin settings, Filesystem expose."
    notify(f"Couldn't open {name}", error, "dialog-error")


def main(action, device_id):
    name = props(device_path(device_id), IFACE).get("name", "the phone")
    if action == "ring":
        call(*plugin(device_id, "findmyphone"), "ring")
    elif action == "ping":
        call(*plugin(device_id, "ping"), "sendPing")
    elif action == "clipboard":
        call(*plugin(device_id, "clipboard"), "sendClipboard")
    elif action == "send":
        # "Select…" so the window rule floats it (config/hypr/windowrules.lua)
        uris = choose_files(f"Select files to send to {name}")
        if uris:
            call(*plugin(device_id, "share"), "shareUrls", GLib.Variant("(as)", (uris,)))
    elif action == "browse":
        browse(device_id, name)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    if sys.argv[1:] == ["watch"]:
        Watch()
        GLib.MainLoop().run()
    elif len(sys.argv) == 3:
        try:
            main(*sys.argv[1:])
        except GLib.Error as e:
            notify("KDE Connect", e.message, "dialog-error")
            sys.exit(1)
    else:
        sys.exit(__doc__)
