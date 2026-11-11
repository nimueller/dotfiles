# pyright: strict
"""BlueZ pairing agent for the Bluetooth menu (BluetoothAgent.qml,
bluetooth.qml), with the system's Python like drives.py. BlueZ asks it
whenever a pairing or connection needs someone: a code to show or type, a
code to compare, a device that wants to pair or connect by itself.

Each question goes out as a JSON line on stdout:
  {"id": 3, "kind": "confirm", "address": "…", "name": "…", "code": "042817"}
kinds: pin (type a PIN), passkey (type a code), confirm (compare a code),
authorize (pair without a code), service (connect), display (type `code` on
the device; `entered`: how much of it), and {"done": 3} once a question is
answered elsewhere, cancelled or over. The answers come back on stdin:
  {"id": 3, "ok": true, "value": "0000"}
and {"default": true} asks BlueZ again to make this the agent it asks, after
another one (Blueman's) took over.
"""

import json
import sys
from dataclasses import dataclass
from typing import Any

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402
from i18n import tr  # noqa: E402

PATH = "/io/github/nimueller/dotfiles/BluetoothAgent"
XML = """
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode"><arg type="o"/><arg type="s" direction="out"/></method>
    <method name="DisplayPinCode"><arg type="o"/><arg type="s"/></method>
    <method name="RequestPasskey"><arg type="o"/><arg type="u" direction="out"/></method>
    <method name="DisplayPasskey"><arg type="o"/><arg type="u"/><arg type="q"/></method>
    <method name="RequestConfirmation"><arg type="o"/><arg type="u"/></method>
    <method name="RequestAuthorization"><arg type="o"/></method>
    <method name="AuthorizeService"><arg type="o"/><arg type="s"/></method>
    <method name="Cancel"/>
  </interface>
</node>
"""
BLUEZ = "org.bluez"
DEVICE = "org.bluez.Device1"
AGENT_MANAGER = "org.bluez.AgentManager1"
PROPERTIES = "org.freedesktop.DBus.Properties"
REJECTED = "org.bluez.Error.Rejected"
CANCELED = "org.bluez.Error.Canceled"
CAPABILITY = "KeyboardDisplay"
NO_TIMEOUT = -1
# What a device connects for, by the UUID's 16-bit part
SERVICES = {
    "110a": "audio",
    "110b": "audio",
    "110c": "remote control",
    "110d": "audio",
    "110e": "remote control",
    "1108": "calls",
    "111e": "calls",
    "111f": "calls",
    "1112": "calls",
    "1124": "input",
    "1105": "file transfer",
    "1106": "file transfer",
    "1115": "network",
    "1116": "network",
    "112f": "contacts",
    "1132": "messages",
}
UNKNOWN_SERVICE = "a service"
# Shown codes get no answer to tell when they're over
DISPLAY_TIMEOUT = 60
MAX_PIN_LENGTH = 16
MAX_PASSKEY = 999_999

# Kinds of questions
PIN = "pin"
PASSKEY = "passkey"
CONFIRM = "confirm"
AUTHORIZE = "authorize"
SERVICE = "service"
DISPLAY = "display"

bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)


@dataclass
class Request:
    # None for a shown code: BlueZ waits for no answer
    invocation: Gio.DBusMethodInvocation | None
    kind: str
    device: str  # its object path


def out(message: dict[str, object]) -> None:
    print(json.dumps(message), flush=True)


def log(message: str) -> None:
    print(f"bluetooth-agent: {message}", file=sys.stderr)


def device_properties(path: str) -> dict[str, Any]:
    """The device's properties, {} when it's gone."""
    try:
        reply = bus.call_sync(
            BLUEZ,
            path,
            PROPERTIES,
            "GetAll",
            GLib.Variant("(s)", (DEVICE,)),
            None,
            Gio.DBusCallFlags.NONE,
            NO_TIMEOUT,
            None,
        )
    except GLib.Error:
        return {}
    (properties,) = reply.unpack()
    return properties


def set_trusted(path: str) -> None:
    try:
        bus.call_sync(
            BLUEZ,
            path,
            PROPERTIES,
            "Set",
            GLib.Variant("(ssv)", (DEVICE, "Trusted", GLib.Variant("b", True))),
            None,
            Gio.DBusCallFlags.NONE,
            NO_TIMEOUT,
            None,
        )
    except GLib.Error as error:
        # The connection is let in either way; untrusted, BlueZ asks again
        # next time
        log(f"couldn't trust {path}: {error.message}")


def six_digits(number: int) -> str:
    return f"{number:06d}"


def service_name(uuid: str) -> str:
    """0000110b-0000-1000-8000-00805f9b34fb -> "audio"."""
    short_uuid = uuid[4:8].lower()
    return tr(SERVICES.get(short_uuid, UNKNOWN_SERVICE))


def is_valid_answer(kind: str, value: str) -> bool:
    if kind == PIN:
        return 1 <= len(value) <= MAX_PIN_LENGTH
    if kind == PASSKEY:
        return value.isdigit() and int(value) <= MAX_PASSKEY
    return True


def is_pairing_over(changed: dict[str, Any]) -> bool:
    """Whether a device's changed properties end a shown code."""
    is_paired = bool(changed.get("Paired") or changed.get("Bonded"))
    is_disconnected = changed.get("Connected") is False
    return is_paired or is_disconnected


class Agent:
    def __init__(self, loop: GLib.MainLoop) -> None:
        self.loop = loop
        self.next_id = 1
        self.pending: dict[int, Request] = {}
        # bluetoothd's unique name, the only one to listen to
        self.bluez: str | None = None
        node = Gio.DBusNodeInfo.new_for_xml(XML)
        bus.register_object(PATH, node.interfaces[0], self.on_method_call, None, None)
        Gio.bus_watch_name_on_connection(
            bus,
            BLUEZ,
            Gio.BusNameWatcherFlags.NONE,
            self.on_bluez_appeared,
            self.on_bluez_vanished,
        )
        # Shown codes are over once the device is paired
        bus.signal_subscribe(
            BLUEZ,
            PROPERTIES,
            "PropertiesChanged",
            None,
            DEVICE,
            Gio.DBusSignalFlags.NONE,
            self.on_device_changed,
        )
        channel = GLib.IOChannel.unix_new(sys.stdin.fileno())
        conditions = GLib.IOCondition.IN | GLib.IOCondition.HUP
        # pygobject-stubs leave io_add_watch's parameters unknown
        GLib.io_add_watch(channel, GLib.PRIORITY_DEFAULT, conditions, self.on_input)  # pyright: ignore[reportUnknownMemberType]

    # ---------- BlueZ ----------

    def call_manager(self, method: str, arguments: GLib.Variant) -> None:
        bus.call_sync(
            BLUEZ,
            "/org/bluez",
            AGENT_MANAGER,
            method,
            arguments,
            None,
            Gio.DBusCallFlags.NONE,
            NO_TIMEOUT,
            None,
        )

    def on_bluez_appeared(self, _bus: Gio.DBusConnection, _name: str, owner: str) -> None:
        """bluetoothd (re)started: register, and as the agent it asks."""
        self.bluez = owner
        try:
            self.call_manager("RegisterAgent", GLib.Variant("(os)", (PATH, CAPABILITY)))
        except GLib.Error as error:
            if "AlreadyExists" not in error.message:
                log(error.message)
                return
        self.make_default()

    def on_bluez_vanished(self, _bus: Gio.DBusConnection | None = None, _name: str = "") -> None:
        self.bluez = None
        for request_id in list(self.pending):
            self.finish(request_id)

    def make_default(self) -> None:
        if self.bluez is None:
            return
        try:
            self.call_manager("RequestDefaultAgent", GLib.Variant("(o)", (PATH,)))
        except GLib.Error as error:
            log(error.message)

    def on_method_call(
        self,
        _bus: Gio.DBusConnection,
        sender: str,
        _path: str,
        _interface: str,
        method: str,
        parameters: GLib.Variant,
        invocation: Gio.DBusMethodInvocation,
    ) -> None:
        if sender != self.bluez:
            invocation.return_dbus_error(REJECTED, "Only BlueZ asks the agent")
            return
        arguments = parameters.unpack()
        if method == "Release":
            self.on_bluez_vanished()
            invocation.return_value(None)
        elif method == "Cancel":
            self.cancel_all()
            invocation.return_value(None)
        elif method == "RequestPinCode":
            (device,) = arguments
            self.ask(invocation, PIN, device)
        elif method == "RequestPasskey":
            (device,) = arguments
            self.ask(invocation, PASSKEY, device)
        elif method == "RequestConfirmation":
            device, passkey = arguments
            self.ask(invocation, CONFIRM, device, code=six_digits(passkey))
        elif method == "RequestAuthorization":
            (device,) = arguments
            self.ask(invocation, AUTHORIZE, device)
        elif method == "AuthorizeService":
            device, uuid = arguments
            self.authorize_service(invocation, device, uuid)
        elif method == "DisplayPinCode":
            device, pin = arguments
            self.show(device, pin, 0)
            invocation.return_value(None)
        elif method == "DisplayPasskey":
            device, passkey, entered = arguments
            self.show(device, six_digits(passkey), entered)
            invocation.return_value(None)

    def cancel_all(self) -> None:
        for request_id, request in list(self.pending.items()):
            if request.invocation is not None:
                request.invocation.return_dbus_error(CANCELED, "Canceled")
            self.finish(request_id)

    def authorize_service(self, invocation: Gio.DBusMethodInvocation, device: str, uuid: str) -> None:
        properties = device_properties(device)
        # Paired here, so already let in once; BlueZ only asks for the ones
        # that aren't trusted
        if properties.get("Paired") or properties.get("Bonded"):
            invocation.return_value(None)
            return
        self.ask(invocation, SERVICE, device, service=service_name(uuid))

    def ask(
        self,
        invocation: Gio.DBusMethodInvocation | None,
        kind: str,
        device: str,
        request_id: int | None = None,
        **extra: object,
    ) -> int:
        """Sends the question to the menu; a new one, or again with the
        same id."""
        if request_id is None:
            request_id = self.next_id
            self.next_id += 1
        self.pending[request_id] = Request(invocation, kind, device)
        properties = device_properties(device)
        address = properties.get("Address", "")
        name = properties.get("Alias", address)
        out({"id": request_id, "kind": kind, "address": address, "name": name, **extra})
        return request_id

    def shown_codes(self, device: str) -> list[int]:
        return [
            request_id
            for request_id, request in self.pending.items()
            if request.kind == DISPLAY and request.device == device
        ]

    def show(self, device: str, code: str, entered: int) -> None:
        """A code to type on the device; again, with the same id, for every
        key typed there."""
        shown = self.shown_codes(device)
        if shown:
            self.ask(None, DISPLAY, device, shown[0], code=code, entered=entered)
            return
        request_id = self.ask(None, DISPLAY, device, code=code, entered=entered)
        GLib.timeout_add_seconds(DISPLAY_TIMEOUT, self.finish, request_id)

    def on_device_changed(
        self,
        _bus: Gio.DBusConnection,
        _sender: str | None,
        path: str,
        _interface: str,
        _signal: str,
        parameters: GLib.Variant,
    ) -> None:
        _interface_name, changed, _invalidated = parameters.unpack()
        if not is_pairing_over(changed):
            return
        for request_id in self.shown_codes(path):
            self.finish(request_id)

    def finish(self, request_id: int) -> bool:
        """Tells the menu a question is over. Also a timeout's callback."""
        if self.pending.pop(request_id, None) is not None:
            out({"done": request_id})
        return GLib.SOURCE_REMOVE

    # ---------- The menu ----------

    def on_input(self, channel: GLib.IOChannel, _condition: GLib.IOCondition) -> bool:
        status, line, _length, _terminator = channel.read_line()
        # The menu's gone: BlueZ forgets the agent along with the connection
        if status == GLib.IOStatus.EOF:
            self.loop.quit()
            return False
        try:
            self.answer(json.loads(line))
        except (ValueError, TypeError, KeyError, AttributeError) as error:
            log(f"bad answer {line!r}: {error}")
        return True

    def answer(self, message: dict[str, Any]) -> None:
        if message.get("default"):
            self.make_default()
            return
        request_id: int = message["id"]
        request = self.pending.get(request_id)
        if request is None:
            # Over already
            return
        value = str(message.get("value", "")).strip()
        is_accepted = bool(message.get("ok")) and is_valid_answer(request.kind, value)
        self.finish(request_id)
        self.reply(request, is_accepted, value)

    @staticmethod
    def reply(request: Request, is_accepted: bool, value: str) -> None:
        """Answers BlueZ, unless it waits for no answer (a shown code)."""
        invocation = request.invocation
        if invocation is None:
            return
        if not is_accepted:
            invocation.return_dbus_error(REJECTED, "Rejected")
        elif request.kind == PIN:
            invocation.return_value(GLib.Variant("(s)", (value,)))
        elif request.kind == PASSKEY:
            invocation.return_value(GLib.Variant("(u)", (int(value),)))
        else:
            # Let in for good: it isn't asked again
            if request.kind == SERVICE:
                set_trusted(request.device)
            invocation.return_value(None)


def main() -> None:
    loop = GLib.MainLoop()
    Agent(loop)
    # pygobject-stubs leave MainLoop.run's return type unknown
    loop.run()  # pyright: ignore[reportUnknownMemberType]


if __name__ == "__main__":
    main()
