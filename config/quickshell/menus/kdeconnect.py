"""KDE Connect for the bar's phone chip and menu (Bar.qml, kdeconnect.qml),
over kdeconnectd's D-Bus interface, with the system's Python like drives.py.

  kdeconnect.py watch           print the paired devices as a JSON line on
                                every change; also mounts reachable phones
                                (SFTP) and shows their storage in Files'
                                sidebar while it's mounted, next to
                                Nextcloud (as a cloud provider)
  kdeconnect.py ring ID         make the phone ring
  kdeconnect.py ping ID         send a ping
  kdeconnect.py clipboard ID    send the clipboard
  kdeconnect.py send ID         pick files (file chooser portal) and send them
  kdeconnect.py browse ID       mount the phone and show it in Files
"""

import json
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

SERVICE = "org.kde.kdeconnect"
ROOT = "/modules/kdeconnect"
IFACE = "org.kde.kdeconnect.device"
# Files' sidebar finds this through a desktop entry (pkgs: phones-in-files)
SIDEBAR_NAME = "io.github.nimueller.dotfiles.Phones"
SIDEBAR_PATH = "/io/github/nimueller/dotfiles/Phones"
SIDEBAR_XML = """
<node>
  <interface name="org.freedesktop.DBus.ObjectManager">
    <method name="GetManagedObjects"><arg type="a{oa{sa{sv}}}" direction="out"/></method>
    <signal name="InterfacesAdded"><arg type="o"/><arg type="a{sa{sv}}"/></signal>
    <signal name="InterfacesRemoved"><arg type="o"/><arg type="as"/></signal>
  </interface>
  <interface name="org.freedesktop.CloudProviders.Provider">
    <property name="Name" type="s" access="read"/>
  </interface>
  <interface name="org.freedesktop.CloudProviders.Account">
    <property name="Name" type="s" access="read"/>
    <property name="Path" type="s" access="read"/>
    <property name="Icon" type="s" access="read"/>
    <property name="Status" type="i" access="read"/>
    <property name="StatusDetails" type="s" access="read"/>
  </interface>
</node>
"""
PROVIDER = "org.freedesktop.CloudProviders.Provider"
ACCOUNT = "org.freedesktop.CloudProviders.Account"
MANAGER = "org.freedesktop.DBus.ObjectManager"

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


class Sidebar:
    """The phones' storage folders as accounts of a cloud provider, the way
    the Nextcloud client shows up in Files' sidebar: in its own section, and
    unlike a bookmark it can't be removed there."""

    def __init__(self):
        node = Gio.DBusNodeInfo.new_for_xml(SIDEBAR_XML)
        self.interfaces = {i.name: i for i in node.interfaces}
        self.objects = {f"{SIDEBAR_PATH}/Provider": {PROVIDER: {"Name": GLib.Variant("s", "KDE Connect")}}}
        self.registrations = {}
        self.register(SIDEBAR_PATH, MANAGER)
        self.register(f"{SIDEBAR_PATH}/Provider", PROVIDER)
        Gio.bus_own_name_on_connection(bus, SIDEBAR_NAME, Gio.BusNameOwnerFlags.NONE, None, None)

    def register(self, path, interface):
        self.registrations[path] = bus.register_object(
            path, self.interfaces[interface], self.method_call, self.get_property, None
        )

    def method_call(self, _bus, _sender, _path, _iface, method, _params, invocation):
        if method == "GetManagedObjects":
            invocation.return_value(GLib.Variant("(a{oa{sa{sv}}})", (self.objects,)))

    def get_property(self, _bus, _sender, path, iface, name):
        return self.objects[path][iface][name]

    def show(self, folders):
        """Show these folders, {object name: (label, path)}, and no others."""
        wanted = {
            f"{SIDEBAR_PATH}/Account/{key}": {
                ACCOUNT: {
                    "Name": GLib.Variant("s", label),
                    "Path": GLib.Variant("s", path),
                    "Icon": GLib.Variant("s", "phone-symbolic"),
                    "Status": GLib.Variant("i", 1),  # idle
                    "StatusDetails": GLib.Variant("s", "Connected"),
                }
            }
            for key, (label, path) in folders.items()
        }
        accounts = {p: o for p, o in self.objects.items() if ACCOUNT in o}
        for path, interfaces in accounts.items():
            if wanted.get(path) != interfaces:
                bus.unregister_object(self.registrations.pop(path))
                del self.objects[path]
                self.emit("InterfacesRemoved", GLib.Variant("(oas)", (path, [ACCOUNT])))
        for path, interfaces in wanted.items():
            if path not in self.objects:
                self.objects[path] = interfaces
                self.register(path, ACCOUNT)
                self.emit("InterfacesAdded", GLib.Variant("(oa{sa{sv}})", (path, interfaces)))

    @staticmethod
    def emit(signal, params):
        bus.emit_signal(None, SIDEBAR_PATH, MANAGER, signal, params)


class Watch:
    def __init__(self):
        self.last = None
        self.mount_tried = set()  # reachable devices that were asked to mount once
        self.pending = 0
        self.sidebar = Sidebar()
        # Any change of kdeconnectd: devices, reachability, battery, mounts
        bus.signal_subscribe(SERVICE, None, None, None, None, Gio.DBusSignalFlags.NONE, self.changed)
        Gio.bus_watch_name_on_connection(
            bus, SERVICE, Gio.BusNameWatcherFlags.NONE, lambda *_: self.changed(), lambda *_: self.changed()
        )
        self.update()

    @staticmethod
    def folders(device):
        """A phone's folders for the sidebar, {object name: (label, path)}:
        its name, plus the folder's when it has more than one (an SD card)."""
        folders = device["storage"]
        return {
            f"{device['id']}_{i}": (device["name"] if len(folders) == 1 else f"{device['name']}: {name}", path)
            for i, (path, name) in enumerate(folders)
        }

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
        self.sidebar.show({k: v for d in state for k, v in self.folders(d).items()})
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
