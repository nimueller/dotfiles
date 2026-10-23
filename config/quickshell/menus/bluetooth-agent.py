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

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

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
DEVICE = "org.bluez.Device1"
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
# Shown codes get no answer to tell when they're over
DISPLAY_TIMEOUT = 60

bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)


def out(message):
    print(json.dumps(message), flush=True)


def device_props(path):
    try:
        reply = bus.call_sync(
            "org.bluez",
            path,
            "org.freedesktop.DBus.Properties",
            "GetAll",
            GLib.Variant("(s)", (DEVICE,)),
            None,
            Gio.DBusCallFlags.NONE,
            -1,
            None,
        )
        return reply.unpack()[0]
    except GLib.Error:
        return {}


def set_trusted(path):
    try:
        bus.call_sync(
            "org.bluez",
            path,
            "org.freedesktop.DBus.Properties",
            "Set",
            GLib.Variant("(ssv)", (DEVICE, "Trusted", GLib.Variant("b", True))),
            None,
            Gio.DBusCallFlags.NONE,
            -1,
            None,
        )
    except GLib.Error:
        pass


class Agent:
    def __init__(self):
        self.next_id = 1
        self.pending = {}  # id → (invocation or None, kind, device path)
        self.bluez = None  # bluetoothd's unique name, the only one to listen to
        node = Gio.DBusNodeInfo.new_for_xml(XML)
        bus.register_object(PATH, node.interfaces[0], self.method_call, None, None)
        Gio.bus_watch_name_on_connection(bus, "org.bluez", Gio.BusNameWatcherFlags.NONE, self.appeared, self.vanished)
        # Shown codes are over once the device is paired
        bus.signal_subscribe(
            "org.bluez",
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            None,
            DEVICE,
            Gio.DBusSignalFlags.NONE,
            self.device_changed,
        )
        channel = GLib.IOChannel.unix_new(sys.stdin.fileno())
        GLib.io_add_watch(channel, GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP, self.read)

    # BlueZ -------------------------------------------------------------------

    def appeared(self, _bus, _name, owner):
        """bluetoothd (re)started: register, and as the agent it asks."""
        self.bluez = owner
        try:
            self.manager("RegisterAgent", GLib.Variant("(os)", (PATH, "KeyboardDisplay")))
        except GLib.Error as e:
            if "AlreadyExists" not in e.message:
                print(f"bluetooth-agent: {e.message}", file=sys.stderr)
                return
        self.make_default()

    def vanished(self, *_):
        self.bluez = None
        for request_id in list(self.pending):
            self.finish(request_id)

    def manager(self, method, args):
        bus.call_sync(
            "org.bluez", "/org/bluez", "org.bluez.AgentManager1", method, args, None, Gio.DBusCallFlags.NONE, -1, None
        )

    def make_default(self):
        if not self.bluez:
            return
        try:
            self.manager("RequestDefaultAgent", GLib.Variant("(o)", (PATH,)))
        except GLib.Error as e:
            print(f"bluetooth-agent: {e.message}", file=sys.stderr)

    def method_call(self, _bus, sender, _path, _iface, method, params, invocation):
        if sender != self.bluez:
            invocation.return_dbus_error("org.bluez.Error.Rejected", "Only BlueZ asks the agent")
            return
        args = params.unpack()
        if method == "Release":
            self.vanished()
            invocation.return_value(None)
        elif method == "Cancel":
            for request_id, (pending, _, _) in list(self.pending.items()):
                if pending:
                    pending.return_dbus_error("org.bluez.Error.Canceled", "Canceled")
                self.finish(request_id)
            invocation.return_value(None)
        elif method == "RequestPinCode":
            self.ask(invocation, "pin", args[0])
        elif method == "RequestPasskey":
            self.ask(invocation, "passkey", args[0])
        elif method == "RequestConfirmation":
            self.ask(invocation, "confirm", args[0], code=f"{args[1]:06d}")
        elif method == "RequestAuthorization":
            self.ask(invocation, "authorize", args[0])
        elif method == "AuthorizeService":
            path, uuid = args
            props = device_props(path)
            # Paired here, so already let in once; BlueZ only asks for the
            # ones that aren't trusted
            if props.get("Paired") or props.get("Bonded"):
                invocation.return_value(None)
            else:
                self.ask(invocation, "service", path, service=SERVICES.get(uuid[4:8].lower(), "a service"))
        elif method == "DisplayPinCode":
            self.show(args[0], args[1], 0)
            invocation.return_value(None)
        elif method == "DisplayPasskey":
            self.show(args[0], f"{args[1]:06d}", args[2])
            invocation.return_value(None)

    def ask(self, invocation, kind, path, request_id=None, **extra):
        if request_id is None:
            request_id = self.next_id
            self.next_id += 1
        self.pending[request_id] = (invocation, kind, path)
        props = device_props(path)
        address = props.get("Address", "")
        out({"id": request_id, "kind": kind, "address": address, "name": props.get("Alias", address), **extra})
        return request_id

    def show(self, path, code, entered):
        """A code to type on the device; again, same id, for every key typed
        there."""
        same = [i for i, (_, kind, p) in self.pending.items() if kind == "display" and p == path]
        if same:
            self.ask(None, "display", path, same[0], code=code, entered=entered)
            return
        request_id = self.ask(None, "display", path, code=code, entered=entered)
        GLib.timeout_add_seconds(DISPLAY_TIMEOUT, self.finish, request_id)

    def device_changed(self, _bus, _sender, path, _iface, _signal, params):
        changed = params.unpack()[1]
        if changed.get("Paired") or changed.get("Bonded") or changed.get("Connected") is False:
            for request_id, (_, kind, p) in list(self.pending.items()):
                if kind == "display" and p == path:
                    self.finish(request_id)

    def finish(self, request_id):
        if self.pending.pop(request_id, None):
            out({"done": request_id})
        return GLib.SOURCE_REMOVE

    # The menu ----------------------------------------------------------------

    def read(self, channel, condition):
        status, line, _, _ = channel.read_line()
        # The menu's gone: BlueZ forgets the agent along with the connection
        if status == GLib.IOStatus.EOF:
            loop.quit()
            return False
        try:
            self.answer(json.loads(line))
        except (ValueError, TypeError, KeyError, AttributeError) as e:
            print(f"bluetooth-agent: bad answer {line!r}: {e}", file=sys.stderr)
        return True

    def answer(self, message):
        if message.get("default"):
            self.make_default()
            return
        request_id = message["id"]
        if request_id not in self.pending:
            return  # over already
        invocation, kind, path = self.pending[request_id]
        value = str(message.get("value", "")).strip()
        ok = bool(message.get("ok"))
        if ok and kind == "pin" and not 1 <= len(value) <= 16:
            ok = False
        if ok and kind == "passkey" and not (value.isdigit() and int(value) <= 999999):
            ok = False
        self.finish(request_id)
        if not invocation:
            return
        if not ok:
            invocation.return_dbus_error("org.bluez.Error.Rejected", "Rejected")
        elif kind == "pin":
            invocation.return_value(GLib.Variant("(s)", (value,)))
        elif kind == "passkey":
            invocation.return_value(GLib.Variant("(u)", (int(value),)))
        else:
            # Let in for good: it isn't asked again
            if kind == "service":
                set_trusted(path)
            invocation.return_value(None)


if __name__ == "__main__":
    loop = GLib.MainLoop()
    Agent()
    loop.run()
