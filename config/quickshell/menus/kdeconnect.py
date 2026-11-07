# pyright: strict
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
import sys
from typing import Any, TypedDict

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402
from notifications import notify  # noqa: E402
from portal import choose_files  # noqa: E402

APP = "KDE Connect"
SERVICE = "org.kde.kdeconnect"
ROOT = "/modules/kdeconnect"
DAEMON = "org.kde.kdeconnect.daemon"
DEVICE = "org.kde.kdeconnect.device"
PROPERTIES = "org.freedesktop.DBus.Properties"
NO_TIMEOUT = -1
MOUNT_TIMEOUT = 30_000  # ms
UPDATE_DELAY = 300  # ms: one update for a burst of signals
NO_BATTERY = -1
NO_SIGNAL = -1
# Files' sidebar finds this through a desktop entry (pkgs: phones-in-files)
SIDEBAR_NAME = "io.github.nimueller.dotfiles.Phones"
SIDEBAR_PATH = "/io/github/nimueller/dotfiles/Phones"
PROVIDER_PATH = f"{SIDEBAR_PATH}/Provider"
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
ACCOUNT_IDLE = 1
PERMISSION_HINT = " Allow it on the phone: KDE Connect, the computer, Plugin settings, Filesystem expose."

# A storage folder of a phone: (path in the mount, name)
Folder = tuple[str, str]
# A sidebar folder: (label, path), by its object name
SidebarFolders = dict[str, tuple[str, str]]
# D-Bus objects: {path: {interface: {property: value}}}
Objects = dict[str, dict[str, dict[str, GLib.Variant]]]


class Device(TypedDict):
    """A paired device, as the bar and the menu get it."""

    id: str
    name: str
    type: str
    reachable: bool
    battery: int
    charging: bool
    network: str
    signal: int
    mounted: bool
    storage: list[Folder]


bus = Gio.bus_get_sync(Gio.BusType.SESSION)


def call(
    path: str,
    interface: str,
    method: str,
    arguments: GLib.Variant | None = None,
    timeout: int = NO_TIMEOUT,
) -> Any:
    """A method of kdeconnectd; returns the reply's values as a tuple."""
    reply = bus.call_sync(SERVICE, path, interface, method, arguments, None, Gio.DBusCallFlags.NONE, timeout, None)
    return reply.unpack()


def properties(path: str, interface: str) -> dict[str, Any]:
    """All properties of an object, {} when the plugin isn't loaded."""
    try:
        (values,) = call(path, PROPERTIES, "GetAll", GLib.Variant("(s)", (interface,)))
    except GLib.Error:
        return {}
    return values


def device_path(device_id: str) -> str:
    return f"{ROOT}/devices/{device_id}"


def plugin(device_id: str, name: str) -> tuple[str, str]:
    """A plugin's object path and interface."""
    return f"{device_path(device_id)}/{name}", f"{DEVICE}.{name}"


def storage(device_id: str) -> list[Folder]:
    """The phone's folders in its mount: none while the phone doesn't let
    KDE Connect at its files. The mount's top folder itself can't be
    listed."""
    try:
        (directories,) = call(*plugin(device_id, "sftp"), "getDirectories")
    except GLib.Error:
        return []
    return list(directories.items())


def is_mounted(device_id: str) -> bool:
    try:
        (mounted,) = call(*plugin(device_id, "sftp"), "isMounted")
    except GLib.Error:
        # No SFTP plugin: nothing to mount
        return False
    return mounted


# ---------- Watching ----------


def device_ids() -> list[str]:
    """The paired devices, [] while kdeconnectd isn't running."""
    only_reachable = False
    only_paired = True
    try:
        (ids,) = call(ROOT, DAEMON, "devices", GLib.Variant("(bb)", (only_reachable, only_paired)))
    except GLib.Error:
        return []
    return ids


def device(device_id: str) -> Device:
    info = properties(device_path(device_id), DEVICE)
    battery = properties(*plugin(device_id, "battery"))
    network = properties(*plugin(device_id, "connectivity_report"))
    reachable = info.get("isReachable", False)
    mounted = reachable and is_mounted(device_id)
    charge = battery.get("charge", NO_BATTERY) if battery.get("hasBattery") else NO_BATTERY
    return {
        "id": device_id,
        "name": info.get("name", device_id),
        "type": info.get("type", "phone"),
        "reachable": reachable,
        "battery": charge,
        "charging": battery.get("isCharging", False),
        "network": network.get("cellularNetworkType", ""),
        "signal": network.get("cellularNetworkStrength", NO_SIGNAL),
        "mounted": mounted,
        "storage": storage(device_id) if mounted else [],
    }


def devices() -> list[Device]:
    return [device(device_id) for device_id in device_ids()]


def account(label: str, path: str) -> dict[str, dict[str, GLib.Variant]]:
    return {
        ACCOUNT: {
            "Name": GLib.Variant("s", label),
            "Path": GLib.Variant("s", path),
            "Icon": GLib.Variant("s", "phone-symbolic"),
            "Status": GLib.Variant("i", ACCOUNT_IDLE),
            "StatusDetails": GLib.Variant("s", "Connected"),
        }
    }


class Sidebar:
    """The phones' storage folders as accounts of a cloud provider, the way
    the Nextcloud client shows up in Files' sidebar: in its own section, and
    unlike a bookmark it can't be removed there."""

    def __init__(self) -> None:
        node = Gio.DBusNodeInfo.new_for_xml(SIDEBAR_XML)
        self.interfaces = {interface.name: interface for interface in node.interfaces}
        self.objects: Objects = {PROVIDER_PATH: {PROVIDER: {"Name": GLib.Variant("s", APP)}}}
        self.registrations: dict[str, int] = {}
        self.register(SIDEBAR_PATH, MANAGER)
        self.register(PROVIDER_PATH, PROVIDER)
        Gio.bus_own_name_on_connection(bus, SIDEBAR_NAME, Gio.BusNameOwnerFlags.NONE, None, None)

    def register(self, path: str, interface: str) -> None:
        self.registrations[path] = bus.register_object(
            path,
            self.interfaces[interface],
            self.on_method_call,
            self.on_get_property,
            None,
        )

    def on_method_call(
        self,
        _bus: Gio.DBusConnection,
        _sender: str,
        _path: str,
        _interface: str,
        method: str,
        _parameters: GLib.Variant,
        invocation: Gio.DBusMethodInvocation,
    ) -> None:
        if method == "GetManagedObjects":
            invocation.return_value(GLib.Variant("(a{oa{sa{sv}}})", (self.objects,)))

    def on_get_property(
        self,
        _bus: Gio.DBusConnection,
        _sender: str,
        path: str,
        interface: str,
        name: str,
    ) -> GLib.Variant:
        return self.objects[path][interface][name]

    def remove_account(self, path: str) -> None:
        bus.unregister_object(self.registrations.pop(path))
        del self.objects[path]
        self.emit("InterfacesRemoved", GLib.Variant("(oas)", (path, [ACCOUNT])))

    def add_account(self, path: str, interfaces: dict[str, dict[str, GLib.Variant]]) -> None:
        self.objects[path] = interfaces
        self.register(path, ACCOUNT)
        self.emit("InterfacesAdded", GLib.Variant("(oa{sa{sv}})", (path, interfaces)))

    def show(self, folders: SidebarFolders) -> None:
        """Shows these folders and no others."""
        wanted = {f"{SIDEBAR_PATH}/Account/{key}": account(label, path) for key, (label, path) in folders.items()}
        shown = {path: interfaces for path, interfaces in self.objects.items() if ACCOUNT in interfaces}
        for path, interfaces in shown.items():
            if wanted.get(path) != interfaces:
                self.remove_account(path)
        for path, interfaces in wanted.items():
            if path not in self.objects:
                self.add_account(path, interfaces)

    @staticmethod
    def emit(signal: str, parameters: GLib.Variant) -> None:
        bus.emit_signal(None, SIDEBAR_PATH, MANAGER, signal, parameters)


def sidebar_folders(phone: Device) -> SidebarFolders:
    """A phone's folders for the sidebar: labelled with its name, plus the
    folder's when it has more than one (an SD card)."""
    folders = phone["storage"]
    result: SidebarFolders = {}
    for index, (path, name) in enumerate(folders):
        label = phone["name"] if len(folders) == 1 else f"{phone['name']}: {name}"
        result[f"{phone['id']}_{index}"] = (label, path)
    return result


class Watch:
    def __init__(self) -> None:
        self.last_line: str | None = None
        # Reachable devices that were asked to mount once
        self.mount_tried: set[str] = set()
        self.pending_update = 0
        self.sidebar = Sidebar()
        # Any change of kdeconnectd: devices, reachability, battery, mounts
        bus.signal_subscribe(SERVICE, None, None, None, None, Gio.DBusSignalFlags.NONE, self.on_signal)
        Gio.bus_watch_name_on_connection(
            bus,
            SERVICE,
            Gio.BusNameWatcherFlags.NONE,
            self.on_name_appeared,
            self.on_name_vanished,
        )
        self.update()

    def on_signal(self, *_signal: object) -> None:
        self.changed()

    def on_name_appeared(self, _bus: Gio.DBusConnection, _name: str, _owner: str) -> None:
        self.changed()

    def on_name_vanished(self, _bus: Gio.DBusConnection, _name: str) -> None:
        self.changed()

    def changed(self) -> None:
        if self.pending_update == 0:
            self.pending_update = GLib.timeout_add(UPDATE_DELAY, self.update)

    def mount_once(self, phone: Device) -> None:
        """Mounts a phone that is reachable but shows no storage: not
        mounted, or mounted before the phone allowed access. Once per
        connection, as it fails again until the phone allows it."""
        if not phone["reachable"]:
            self.mount_tried.discard(phone["id"])
            return
        if phone["storage"] or phone["id"] in self.mount_tried:
            return
        self.mount_tried.add(phone["id"])
        path, interface = plugin(phone["id"], "sftp")
        if phone["mounted"]:
            call(path, interface, "unmount")
        bus.call(SERVICE, path, interface, "mount", None, None, Gio.DBusCallFlags.NONE, NO_TIMEOUT, None, None)

    def update(self) -> bool:
        self.pending_update = 0
        phones = devices()
        sidebar: SidebarFolders = {}
        for phone in phones:
            self.mount_once(phone)
            sidebar.update(sidebar_folders(phone))
        self.sidebar.show(sidebar)
        line = json.dumps(phones)
        if line != self.last_line:
            self.last_line = line
            print(line, flush=True)
        return GLib.SOURCE_REMOVE


# ---------- Actions ----------


def mount_and_wait(path: str, interface: str) -> bool:
    (mounted,) = call(path, interface, "mountAndWait", timeout=MOUNT_TIMEOUT)
    return mounted


def mounted_storage(device_id: str) -> list[Folder]:
    """Mounts the phone and returns its folders; mounts it again when it
    was mounted before the phone allowed access."""
    path, interface = plugin(device_id, "sftp")
    if not mount_and_wait(path, interface):
        return []
    folders = storage(device_id)
    if folders:
        return folders
    call(path, interface, "unmount")
    if not mount_and_wait(path, interface):
        return []
    return storage(device_id)


def browse(device_id: str, name: str) -> None:
    folders = mounted_storage(device_id)
    if folders:
        first_path, _name = folders[0]
        Gio.AppInfo.launch_default_for_uri(GLib.filename_to_uri(first_path, None), None)
        return
    path, interface = plugin(device_id, "sftp")
    (error,) = call(path, interface, "getMountError")
    # Without folders the phone hasn't allowed access, whatever the error says
    message = (error or "The phone didn't share any folders.") + PERMISSION_HINT
    notify(bus, APP, f"Couldn't open {name}", message, "dialog-error")


def send_files(device_id: str, name: str) -> None:
    uris = choose_files(bus, f"Select files to send to {name}", "_Send", multiple=True)
    if uris:
        call(*plugin(device_id, "share"), "shareUrls", GLib.Variant("(as)", (uris,)))


def run_action(action: str, device_id: str) -> None:
    name = properties(device_path(device_id), DEVICE).get("name", "the phone")
    if action == "ring":
        call(*plugin(device_id, "findmyphone"), "ring")
    elif action == "ping":
        call(*plugin(device_id, "ping"), "sendPing")
    elif action == "clipboard":
        call(*plugin(device_id, "clipboard"), "sendClipboard")
    elif action == "send":
        send_files(device_id, name)
    elif action == "browse":
        browse(device_id, name)
    else:
        sys.exit(__doc__)


def watch() -> None:
    Watch()
    # pygobject-stubs leave MainLoop.run's return type unknown
    GLib.MainLoop().run()  # pyright: ignore[reportUnknownMemberType]


def main() -> None:
    arguments = sys.argv[1:]
    if arguments == ["watch"]:
        watch()
        return
    if len(arguments) != 2:
        sys.exit(__doc__)
    action, device_id = arguments
    try:
        run_action(action, device_id)
    except GLib.Error as error:
        notify(bus, APP, APP, error.message, "dialog-error")
        sys.exit(1)


if __name__ == "__main__":
    main()
