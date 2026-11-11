# pyright: strict
"""Notifies when a USB drive, memory card, disc or phone shows up, with Open
(mounts it and shows it in Files) and Eject. Run by daemon.qml, with the
system's Python: GVfs's volume monitors (gvfs, gvfs-mtp) only load into the
system's GLib, the same ones Files uses.
"""

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib, GObject  # noqa: E402
from i18n import tr  # noqa: E402
from notifications import close, notify, subscribe  # noqa: E402

APP = "Drives"
FALLBACK_ICON = "drive-removable-media"
ERROR_ICON = "dialog-error"
# "default" is a click on the notification itself
OPEN_ACTIONS = {"default", "open"}
EJECT_ACTION = "eject"


def icon_name(volume: Gio.Volume) -> str:
    icon = volume.get_icon()
    if isinstance(icon, Gio.ThemedIcon):
        return icon.get_names()[0]
    return FALLBACK_ICON


def was_plugged_in(volume: Gio.Volume) -> bool:
    """Removable drives and phones (which have no drive); a new partition
    on an internal disk doesn't count."""
    drive = volume.get_drive()
    if drive is None:
        return True
    return drive.is_removable() or drive.is_media_removable()


def drive_name(volume: Gio.Volume) -> str:
    """The drive's name when it says more than the volume's, else ""."""
    drive = volume.get_drive()
    if drive is None or drive.get_name() == volume.get_name():
        return ""
    return drive.get_name()


def show_in_files(mount: Gio.Mount) -> None:
    uri = mount.get_root().get_uri()
    Gio.AppInfo.launch_default_for_uri(uri, None)


class Drives:
    def __init__(self) -> None:
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION)
        # The volumes whose notification is still shown, by its id
        self.shown: dict[int, Gio.Volume] = {}
        subscribe(self.bus, self.on_action, self.on_closed)
        self.monitor = Gio.VolumeMonitor.get()
        self.monitor.connect("volume-added", self.on_added)
        self.monitor.connect("volume-removed", self.on_removed)

    # ---------- Notifications ----------

    def on_action(self, notification_id: int, action: str) -> None:
        volume = self.shown.pop(notification_id, None)
        if volume is None:
            return
        if action in OPEN_ACTIONS:
            self.open(volume, notification_id)
        elif action == EJECT_ACTION:
            self.eject(volume, notification_id)

    def on_closed(self, notification_id: int) -> None:
        self.shown.pop(notification_id, None)

    def failed(self, summary: str, error: GLib.Error, notification_id: int) -> None:
        """summary says what didn't work: "Couldn't open <drive>"."""
        notify(self.bus, APP, summary, error.message, ERROR_ICON, replaces=notification_id)

    # ---------- Volumes ----------

    def on_added(self, _monitor: Gio.VolumeMonitor, volume: Gio.Volume) -> None:
        if not was_plugged_in(volume):
            return
        actions = ["default", tr("Open"), "open", tr("Open")]
        if volume.can_eject() or volume.get_mount() is not None:
            actions += [EJECT_ACTION, tr("Eject")]
        summary = tr("%1 connected", volume.get_name())
        notification_id = notify(self.bus, APP, summary, drive_name(volume), icon_name(volume), actions)
        self.shown[notification_id] = volume

    def on_removed(self, _monitor: Gio.VolumeMonitor, volume: Gio.Volume) -> None:
        gone = [notification_id for notification_id, shown in self.shown.items() if shown == volume]
        for notification_id in gone:
            del self.shown[notification_id]
            close(self.bus, notification_id)

    def open(self, volume: Gio.Volume, notification_id: int) -> None:
        mount = volume.get_mount()
        if mount is not None:
            show_in_files(mount)
            return

        def on_mounted(_source: GObject.Object | None, result: Gio.AsyncResult) -> None:
            try:
                volume.mount_finish(result)
            except GLib.Error as error:
                self.failed(tr("Couldn't open %1", volume.get_name()), error, notification_id)
                return
            mounted = volume.get_mount()
            if mounted is not None:
                show_in_files(mounted)

        volume.mount(Gio.MountMountFlags.NONE, Gio.MountOperation(), None, on_mounted)

    def eject(self, volume: Gio.Volume, notification_id: int) -> None:
        """Ejects the volume, or unmounts it when it can't be ejected."""
        name = volume.get_name()
        icon = icon_name(volume)
        mount = volume.get_mount()

        def on_done(source: GObject.Object | None, result: Gio.AsyncResult) -> None:
            try:
                if isinstance(source, Gio.Mount):
                    source.unmount_with_operation_finish(result)
                else:
                    volume.eject_with_operation_finish(result)
            except GLib.Error as error:
                self.failed(tr("Couldn't eject %1", volume.get_name()), error, notification_id)
                return
            notify(self.bus, APP, tr("%1 can be removed", name), "", icon, replaces=notification_id)

        operation = Gio.MountOperation()
        if volume.can_eject():
            volume.eject_with_operation(Gio.MountUnmountFlags.NONE, operation, None, on_done)
        elif mount is not None:
            mount.unmount_with_operation(Gio.MountUnmountFlags.NONE, operation, None, on_done)


def main() -> None:
    Drives()
    # pygobject-stubs leave MainLoop.run's return type unknown
    GLib.MainLoop().run()  # pyright: ignore[reportUnknownMemberType]


if __name__ == "__main__":
    main()
