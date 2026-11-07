# pyright: strict
"""Desktop notifications over D-Bus for the shell's Python helpers that
already run a GLib main loop (drives.py, kdeconnect.py): unlike notify-send
they can replace a notification, close it, and hear its actions without
blocking. The notification server is the shell's own (Notifications.qml)."""

from collections.abc import Callable

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

SERVICE = "org.freedesktop.Notifications"
PATH = "/org/freedesktop/Notifications"
INTERFACE = "org.freedesktop.Notifications"
DEFAULT_TIMEOUT = -1
NO_TIMEOUT = -1
NEW = 0  # "replaces" for a new notification instead of replacing one

# on_action(id, action), on_closed(id)
ActionHandler = Callable[[int, str], None]
ClosedHandler = Callable[[int], None]


def notify(
    bus: Gio.DBusConnection,
    app: str,
    summary: str,
    body: str = "",
    icon: str = "",
    actions: list[str] | None = None,
    replaces: int = NEW,
) -> int:
    """Shows a notification, or replaces the one with that id; returns its
    id. actions alternate between a key and its label."""
    parameters = GLib.Variant(
        "(susssasa{sv}i)",
        (app, replaces, icon, summary, body, actions or [], {}, DEFAULT_TIMEOUT),
    )
    reply = bus.call_sync(
        SERVICE,
        PATH,
        INTERFACE,
        "Notify",
        parameters,
        GLib.VariantType("(u)"),
        Gio.DBusCallFlags.NONE,
        NO_TIMEOUT,
        None,
    )
    (notification_id,) = reply.unpack()
    return notification_id


def close(bus: Gio.DBusConnection, notification_id: int) -> None:
    bus.call(
        SERVICE,
        PATH,
        INTERFACE,
        "CloseNotification",
        GLib.Variant("(u)", (notification_id,)),
        None,
        Gio.DBusCallFlags.NONE,
        NO_TIMEOUT,
        None,
        None,
    )


def subscribe(bus: Gio.DBusConnection, on_action: ActionHandler, on_closed: ClosedHandler) -> None:
    """Calls on_action when an action of any notification is clicked and
    on_closed when one closes; the ids tell whose they are."""

    def on_signal(
        _bus: Gio.DBusConnection,
        _sender: str | None,
        _path: str,
        _interface: str,
        signal: str,
        parameters: GLib.Variant,
    ) -> None:
        if signal == "ActionInvoked":
            notification_id, action = parameters.unpack()
            on_action(notification_id, action)
        elif signal == "NotificationClosed":
            notification_id, _reason = parameters.unpack()
            on_closed(notification_id)

    bus.signal_subscribe(
        SERVICE,
        INTERFACE,
        None,
        PATH,
        None,
        Gio.DBusSignalFlags.NONE,
        on_signal,
    )
