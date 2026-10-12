"""Notifies when a USB drive, memory card, disc or phone shows up, with Open
(mounts it and shows it in Files) and Eject. Run by daemon.qml, with the
system's Python: GVfs's volume monitors (gvfs, gvfs-mtp) only load into the
system's GLib, the same ones Files uses.
"""

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

APP = "Drives"


class Drives:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION)
        self.shown = {}  # notification id → volume
        self.bus.signal_subscribe(
            "org.freedesktop.Notifications",
            "org.freedesktop.Notifications",
            None,
            "/org/freedesktop/Notifications",
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_signal,
        )
        self.monitor = Gio.VolumeMonitor.get()
        self.monitor.connect("volume-added", self.on_added)
        self.monitor.connect("volume-removed", self.on_removed)

    # Notifications ----------------------------------------------------------

    def notify(self, summary, body, icon, actions=(), replaces=0):
        reply = self.bus.call_sync(
            "org.freedesktop.Notifications",
            "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications",
            "Notify",
            GLib.Variant(
                "(susssasa{sv}i)",
                (APP, replaces, icon, summary, body, list(actions), {}, -1),
            ),
            GLib.VariantType("(u)"),
            Gio.DBusCallFlags.NONE,
            -1,
        )
        return reply.unpack()[0]

    def close(self, nid):
        self.bus.call(
            "org.freedesktop.Notifications",
            "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications",
            "CloseNotification",
            GLib.Variant("(u)", (nid,)),
            None,
            Gio.DBusCallFlags.NONE,
            -1,
        )

    def on_signal(self, _bus, _sender, _path, _iface, signal, params):
        if signal == "ActionInvoked":
            nid, action = params.unpack()
            volume = self.shown.pop(nid, None)
            if volume is None:
                return
            if action in ("default", "open"):
                self.open(volume, nid)
            elif action == "eject":
                self.eject(volume, nid)
        elif signal == "NotificationClosed":
            self.shown.pop(params.unpack()[0], None)

    # Volumes ----------------------------------------------------------------

    @staticmethod
    def icon(volume):
        icon = volume.get_icon()
        return icon.get_names()[0] if isinstance(icon, Gio.ThemedIcon) else "drive-removable-media"

    def on_added(self, _monitor, volume):
        # Only what was plugged in or inserted: removable drives and phones
        # (no drive); a new partition on an internal disk doesn't count
        drive = volume.get_drive()
        if drive and not (drive.is_removable() or drive.is_media_removable()):
            return
        name = volume.get_name()
        body = drive.get_name() if drive and drive.get_name() != name else ""
        actions = ["default", "Open", "open", "Open"]
        if volume.can_eject() or volume.get_mount():
            actions += ["eject", "Eject"]
        nid = self.notify(f"{name} connected", body, self.icon(volume), actions)
        self.shown[nid] = volume

    def on_removed(self, _monitor, volume):
        for nid, v in list(self.shown.items()):
            if v == volume:
                del self.shown[nid]
                self.close(nid)

    def failed(self, volume, what, error, nid):
        self.notify(f"Couldn't {what} {volume.get_name()}", error.message, "dialog-error", replaces=nid)

    def open(self, volume, nid):
        mount = volume.get_mount()
        if mount:
            self.show(mount)
            return

        def done(volume, result):
            try:
                volume.mount_finish(result)
            except GLib.Error as e:
                self.failed(volume, "open", e, nid)
                return
            self.show(volume.get_mount())

        volume.mount(Gio.MountMountFlags.NONE, Gio.MountOperation(), None, done)

    @staticmethod
    def show(mount):
        Gio.AppInfo.launch_default_for_uri(mount.get_root().get_uri(), None)

    def eject(self, volume, nid):
        name = volume.get_name()
        icon = self.icon(volume)
        mount = volume.get_mount()

        def done(obj, result):
            try:
                if obj is volume:
                    volume.eject_with_operation_finish(result)
                else:
                    obj.unmount_with_operation_finish(result)
            except GLib.Error as e:
                self.failed(volume, "eject", e, nid)
                return
            self.notify(f"{name} can be removed", "", icon, replaces=nid)

        operation = Gio.MountOperation()
        if volume.can_eject():
            volume.eject_with_operation(Gio.MountUnmountFlags.NONE, operation, None, done)
        elif mount:
            mount.unmount_with_operation(Gio.MountUnmountFlags.NONE, operation, None, done)


if __name__ == "__main__":
    Drives()
    GLib.MainLoop().run()
