#!/usr/bin/env python3
# pyright: strict
"""The partition editor's helper (Disks.qml, disks.qml): reads the drives
from udisks2 and writes a plan to one of them. What a plan does, and whether
it can, is worked out in disk_layout.py; nothing here is written before
`apply`. Runs with the system's Python, for PyGObject.

  disks.py list               {"drives": [...], "filesystems": [...], "types": {...}}
  disks.py plan  < request    {"drive": {...}, "steps": [{"step", "text", "problem"}]}
  disks.py apply < request    one JSON line per event, see below
  disks.py watch              prints "changed" whenever udisks' drives change
  disks.py image open|save    the file chooser: {"path": "…", "size": n}, {} if cancelled

A request is {"drive": id, "revision": "…", "steps": [step, …]}, the steps
as disk_layout.py describes them. plan takes "add": [step, …], too: the
steps then come back with those at the end, each after the unmount and lock
steps it needs.
When the drive changed since the menu read it (another revision), plan and
apply answer {"stale": true} and do nothing.

apply prints {"step": i, "state": "running"}, {"step": i, "progress": 0.4}
while an image is copied, {"step": i, "state": "done", "note": "…"}, and at
the end {"done": true} or {"error": "…", "step": i}. It stops at the first
step that fails. udisks asks for the password through polkit where needed.

Anything else that goes wrong: {"error": "…"}.
"""

import bz2
import gzip
import io
import json
import lzma
import re
import sys
from collections.abc import Callable
from compression import zstd
from pathlib import Path
from typing import Any, Literal

import gi

gi.require_version("Gio", "2.0")
from disk_layout import (  # noqa: E402
    DOS_BOOTABLE,
    FILESYSTEMS,
    LABEL_LIMITS,
    NEW_PREFIX,
    NO_FILESYSTEM,
    OWNED_FILESYSTEMS,
    Capabilities,
    Capability,
    Drive,
    Step,
    align_down,
    align_up,
    drive_view,
    filesystem_views,
    revision,
    simulate,
    step_from_json,
    step_to_json,
    type_views,
    with_step,
)
from disk_objects import (  # noqa: E402
    BLOCK,
    DRIVE,
    ENCRYPTED,
    FILESYSTEM,
    PARTITION,
    SWAPSPACE,
    TABLE,
    Objects,
    cleartext_of,
    read_drives,
)
from gi.repository import Gio, GLib  # noqa: E402
from i18n import tr  # noqa: E402
from portal import choose_files, choose_save_file  # noqa: E402

UDISKS = "org.freedesktop.UDisks2"
UDISKS_ROOT = "/org/freedesktop/UDisks2"
MANAGER_PATH = "/org/freedesktop/UDisks2/Manager"
MANAGER = "org.freedesktop.UDisks2.Manager"
OBJECT_MANAGER = "org.freedesktop.DBus.ObjectManager"
# Formatting with zeros or copying an image can take hours
NO_TIMEOUT = GLib.MAXINT
QUICK_TIMEOUT = 10_000
CALL_FLAGS = Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION
REMOTE_ERROR = re.compile(r"^GDBus\.Error:[\w.-]+: ")
CHUNK = 4 * 1024**2
PROGRESS_STEP = 0.01
# Changes come in bursts (a partition table brings a dozen): one line for them
WATCH_DELAY_MS = 300
IMAGE_TYPES = ["application/x-raw-disk-image", "application/x-cd-image", "application/octet-stream"]
COMPRESSED: dict[str, Callable[..., Any]] = {
    ".xz": lzma.open,
    ".gz": gzip.open,
    ".bz2": bz2.open,
    ".zst": zstd.open,
}


def output(value: object) -> None:
    print(json.dumps(value), flush=True)


def system_bus() -> Gio.DBusConnection:
    return Gio.bus_get_sync(Gio.BusType.SYSTEM)


def call(
    bus: Gio.DBusConnection,
    path: str,
    interface: str,
    method: str,
    arguments: GLib.Variant | None,
    timeout: int = NO_TIMEOUT,
) -> tuple[Any, ...]:
    reply = bus.call_sync(UDISKS, path, interface, method, arguments, None, CALL_FLAGS, timeout, None)
    return tuple(reply.unpack())


def options(values: dict[str, bool | str] | None = None) -> dict[str, GLib.Variant]:
    """udisks' a{sv} options from plain values"""
    variants: dict[str, GLib.Variant] = {}
    for key, value in (values or {}).items():
        variants[key] = GLib.Variant("b", value) if isinstance(value, bool) else GLib.Variant("s", value)
    return variants


def managed_objects(bus: Gio.DBusConnection) -> Objects:
    (objects,) = call(bus, UDISKS_ROOT, OBJECT_MANAGER, "GetManagedObjects", None, QUICK_TIMEOUT)
    return objects


def ask_manager(bus: Gio.DBusConnection, method: str, fs: str, unsupported: tuple[Any, ...]) -> tuple[Any, ...]:
    """One of udisks' CanFormat, CanResize, CanCheck, CanRepair"""
    argument = GLib.Variant("(s)", (fs,))
    try:
        (answer,) = call(bus, MANAGER_PATH, MANAGER, method, argument, QUICK_TIMEOUT)
    except GLib.Error:
        # libblockdev answers a filesystem it can't do this for with an error
        return unsupported
    return tuple(answer)


def capabilities(bus: Gio.DBusConnection, filesystems: list[str]) -> Capabilities:
    """What udisks can do with each filesystem, by the tools installed"""
    found: Capabilities = {}
    for fs in filesystems:
        can_format, utility = ask_manager(bus, "CanFormat", fs, (False, ""))
        _can_resize, resize_flags, _resize_utility = ask_manager(bus, "CanResize", fs, (False, 0, ""))
        can_check, _check_utility = ask_manager(bus, "CanCheck", fs, (False, ""))
        can_repair, _repair_utility = ask_manager(bus, "CanRepair", fs, (False, ""))
        found[fs] = Capability(
            format=bool(can_format),
            utility=str(utility),
            resize=int(resize_flags),
            check=bool(can_check),
            repair=bool(can_repair),
        )
    return found


def known_filesystems() -> list[str]:
    """The ones the editor formats, and the ones it may find"""
    names = {*FILESYSTEMS, *LABEL_LIMITS}
    names.discard(NO_FILESYSTEM)
    return sorted(names)


def list_drives() -> None:
    bus = system_bus()
    found = capabilities(bus, known_filesystems())
    drives = read_drives(managed_objects(bus))
    output(
        {
            "drives": [drive_view(drive, found) for drive in drives],
            "filesystems": filesystem_views(found),
            "types": type_views(),
        }
    )


# ---------- Planning ----------


def error_message(error: GLib.Error) -> str:
    """udisks' message without the D-Bus error name in front"""
    return REMOTE_ERROR.sub("", error.message).strip()


def requested_drive(bus: Gio.DBusConnection, request: dict[str, Any]) -> Drive | None:
    """The drive the request is about, None if it's gone or changed"""
    drives = read_drives(managed_objects(bus))
    drive = next((d for d in drives if d.id == request.get("drive")), None)
    if drive is None or revision(drive) != request.get("revision"):
        return None
    return drive


def requested_steps(request: dict[str, Any]) -> list[Step]:
    steps: list[object] = request.get("steps", [])
    return [step_from_json(step) for step in steps if isinstance(step, dict)]  # pyright: ignore[reportUnknownArgumentType]


def plan(request: dict[str, Any]) -> None:
    bus = system_bus()
    drive = requested_drive(bus, request)
    if drive is None:
        output({"stale": True})
        return
    found = capabilities(bus, known_filesystems())
    steps = requested_steps(request)
    for added in requested_steps({"steps": request.get("add", [])}):
        steps = with_step(drive, steps, added, found)
    result = simulate(drive, steps, found)
    rows = [
        {"step": step_to_json(step), "text": text, "problem": problem}
        for step, text, problem in zip(steps, result.texts, result.problems, strict=True)
    ]
    output({"drive": drive_view(result.drive, found), "steps": rows})


def apply(request: dict[str, Any]) -> None:
    bus = system_bus()
    drive = requested_drive(bus, request)
    if drive is None:
        output({"stale": True})
        return
    steps = requested_steps(request)
    result = simulate(drive, steps, capabilities(bus, known_filesystems()))
    if any(result.problems):
        output({"error": tr("The plan has problems, nothing was written")})
        return
    Writer(bus, drive, steps).run()


# ---------- Writing ----------


def format_options(step: Step) -> dict[str, GLib.Variant]:
    values: dict[str, bool | str] = {"update-partition-type": True}
    if step.label:
        values["label"] = step.label
    if step.fs in OWNED_FILESYSTEMS:
        values["take-ownership"] = True
    if step.passphrase:
        values["encrypt.passphrase"] = step.passphrase
        values["encrypt.type"] = "luks2"
    if step.erase:
        values["erase"] = "zero"
    return options(values)


def image_reader(path: Path, raw: io.BufferedReader) -> Any:
    """The image's bytes, unpacked when its name says it's compressed"""
    opener = COMPRESSED.get(path.suffix)
    return opener(raw, "rb") if opener else raw


def image_writer(path: Path) -> Any:
    opener = COMPRESSED.get(path.suffix)
    return opener(path, "wb") if opener else path.open("wb")


class Writer:
    """Does a plan's steps one after the other, stopping at the first that
    fails. Partitions the plan creates are found by "new<i>"."""

    def __init__(self, bus: Gio.DBusConnection, drive: Drive, steps: list[Step]) -> None:
        self.bus = bus
        self.drive = drive
        self.steps = steps
        self.created: dict[str, str] = {}
        self.index = 0

    def run(self) -> None:
        for index, step in enumerate(self.steps):
            self.index = index
            output({"step": index, "state": "running"})
            try:
                note = self.do(step)
            except GLib.Error as error:
                output({"step": index, "error": error_message(error)})
                return
            except OSError as error:
                output({"step": index, "error": str(error)})
                return
            output({"step": index, "state": "done", "note": note})
        output({"done": True})

    def do(self, step: Step) -> str:
        """Carries out one step; a note to show with it, "" for none"""
        steps: dict[str, Callable[[Step], str]] = {
            "table": self.table,
            "create": self.create,
            "delete": self.delete,
            "format": self.format,
            "resize": self.resize,
            "label": self.label,
            "name": self.name,
            "type": self.type,
            "bootable": self.bootable,
            "check": self.check,
            "repair": self.repair,
            "mount": self.mount,
            "unmount": self.unmount,
            "unlock": self.unlock,
            "lock": self.lock,
            "passphrase": self.passphrase,
            "restore": self.restore,
            "backup": self.backup,
            "poweroff": self.poweroff,
        }
        return steps[step.op](step)

    # ---------- Finding the objects ----------

    def object_of(self, target: str) -> str:
        return self.created.get(target, target)

    def interfaces(self, path: str) -> dict[str, dict[str, Any]]:
        return managed_objects(self.bus).get(path, {})

    def content_of(self, target: str) -> str:
        """The block with the filesystem: the unlocked one of a LUKS volume"""
        path = self.object_of(target)
        objects = managed_objects(self.bus)
        if ENCRYPTED not in objects.get(path, {}):
            return path
        return cleartext_of(objects, path) or path

    def call(self, path: str, interface: str, method: str, signature: str, *arguments: object) -> tuple[Any, ...]:
        """A udisks method whose last argument is the (empty) options"""
        variant = GLib.Variant(f"({signature}a{{sv}})", (*arguments, options()))
        return call(self.bus, path, interface, method, variant)

    # ---------- The steps ----------

    def table(self, step: Step) -> str:
        variant = GLib.Variant("(sa{sv})", (step.type, options()))
        call(self.bus, self.drive.block, BLOCK, "Format", variant)
        return ""

    def create(self, step: Step) -> str:
        offset = align_up(step.offset)
        size = align_down(step.offset + step.size) - offset
        partition_options = options({"partition-type": "primary"} if self.drive.table == "dos" else None)
        table = self.drive.block
        if step.fs == NO_FILESYSTEM:
            variant = GLib.Variant("(ttssa{sv})", (offset, size, "", step.name, partition_options))
            (path,) = call(self.bus, table, TABLE, "CreatePartition", variant)
        else:
            arguments = (offset, size, "", step.name, partition_options, step.fs, format_options(step))
            variant = GLib.Variant("(ttssa{sv}sa{sv})", arguments)
            (path,) = call(self.bus, table, TABLE, "CreatePartitionAndFormat", variant)
        self.created[f"{NEW_PREFIX}{self.index}"] = str(path)
        return ""

    def delete(self, step: Step) -> str:
        self.call(self.object_of(step.target), PARTITION, "Delete", "")
        return ""

    def format(self, step: Step) -> str:
        variant = GLib.Variant("(sa{sv})", (step.fs, format_options(step)))
        call(self.bus, self.object_of(step.target), BLOCK, "Format", variant)
        return ""

    def resize(self, step: Step) -> str:
        """The filesystem shrinks before its partition, and grows after it"""
        path = self.object_of(step.target)
        interfaces = self.interfaces(path)
        size = align_down(step.size)
        has_filesystem = FILESYSTEM in interfaces
        shrinks = size < int(interfaces[PARTITION]["Size"])
        if has_filesystem and shrinks and str(interfaces[BLOCK]["IdType"]).startswith("ext"):
            # resize2fs shrinks only right after a forced e2fsck, which Repair is
            self.call(path, FILESYSTEM, "Repair", "")
        if has_filesystem and shrinks:
            self.call(path, FILESYSTEM, "Resize", "t", size)
        self.call(path, PARTITION, "Resize", "t", size)
        if has_filesystem and not shrinks:
            # 0: as big as the partition
            self.call(path, FILESYSTEM, "Resize", "t", 0)
        return ""

    def label(self, step: Step) -> str:
        path = self.content_of(step.target)
        interface = SWAPSPACE if SWAPSPACE in self.interfaces(path) else FILESYSTEM
        self.call(path, interface, "SetLabel", "s", step.value)
        return ""

    def name(self, step: Step) -> str:
        self.call(self.object_of(step.target), PARTITION, "SetName", "s", step.value)
        return ""

    def type(self, step: Step) -> str:
        self.call(self.object_of(step.target), PARTITION, "SetType", "s", step.value)
        return ""

    def bootable(self, step: Step) -> str:
        path = self.object_of(step.target)
        flags = int(self.interfaces(path)[PARTITION]["Flags"])
        flags = flags | DOS_BOOTABLE if step.on else flags & ~DOS_BOOTABLE
        self.call(path, PARTITION, "SetFlags", "t", flags)
        return ""

    def check(self, step: Step) -> str:
        (consistent,) = self.call(self.content_of(step.target), FILESYSTEM, "Check", "")
        return tr("No errors found") if consistent else tr("Errors found, repair it")

    def repair(self, step: Step) -> str:
        (repaired,) = self.call(self.content_of(step.target), FILESYSTEM, "Repair", "")
        return tr("Repaired") if repaired else tr("Not everything could be repaired")

    def mount(self, step: Step) -> str:
        (where,) = self.call(self.content_of(step.target), FILESYSTEM, "Mount", "")
        return tr("Mounted at %1", where)

    def unmount(self, step: Step) -> str:
        self.call(self.content_of(step.target), FILESYSTEM, "Unmount", "")
        return ""

    def unlock(self, step: Step) -> str:
        self.call(self.object_of(step.target), ENCRYPTED, "Unlock", "s", step.passphrase)
        return ""

    def lock(self, step: Step) -> str:
        self.call(self.object_of(step.target), ENCRYPTED, "Lock", "")
        return ""

    def passphrase(self, step: Step) -> str:
        self.call(self.object_of(step.target), ENCRYPTED, "ChangePassphrase", "ss", step.passphrase, step.value)
        return ""

    def poweroff(self, _step: Step) -> str:
        self.call(self.drive.id, DRIVE, "PowerOff", "")
        return ""

    # ---------- Images ----------

    def open_block(self, path: str, method: Literal["OpenForRestore", "OpenForBackup"]) -> int:
        """A file descriptor of the block, opened by udisks for us"""
        reply, fds = self.bus.call_with_unix_fd_list_sync(
            UDISKS,
            path,
            BLOCK,
            method,
            GLib.Variant("(a{sv})", (options(),)),
            GLib.VariantType("(h)"),
            CALL_FLAGS,
            NO_TIMEOUT,
            None,
            None,
        )
        (index,) = reply.unpack()
        return fds.get(index)

    def restore(self, step: Step) -> str:
        image = Path(step.image)
        total = image.stat().st_size
        descriptor = self.open_block(self.drive.block, "OpenForRestore")
        with image.open("rb") as raw, image_reader(image, raw) as source, open(descriptor, "wb") as target:
            self.copy(source, target, total, raw.tell)
        return ""

    def backup(self, step: Step) -> str:
        path = self.object_of(step.target)
        total = int(self.interfaces(path)[BLOCK]["Size"])
        descriptor = self.open_block(path, "OpenForBackup")
        with open(descriptor, "rb") as source, image_writer(Path(step.image)) as target:
            self.copy(source, target, total)
        return tr("Saved as %1", step.image)

    def copy(self, source: Any, target: Any, total: int, position: Callable[[], int] | None = None) -> None:
        """Copies and reports how far it got; position() tells it where a
        compressed image is read, else the bytes copied count"""
        copied = 0
        shown = 0.0
        while chunk := source.read(CHUNK):
            target.write(chunk)
            copied += len(chunk)
            done = min(1.0, (position() if position else copied) / max(total, 1))
            if done - shown >= PROGRESS_STEP:
                shown = done
                output({"step": self.index, "progress": round(done, 3)})
        target.flush()


# ---------- Watching and choosing images ----------


class Watcher:
    """Prints "changed" once after a burst of udisks signals"""

    def __init__(self) -> None:
        self.pending = 0
        bus = system_bus()
        bus.signal_subscribe(UDISKS, None, None, None, None, Gio.DBusSignalFlags.NONE, self.on_signal)

    def on_signal(self, *_arguments: object) -> None:
        if self.pending == 0:
            self.pending = GLib.timeout_add(WATCH_DELAY_MS, self.report)

    def report(self) -> bool:
        self.pending = 0
        print("changed", flush=True)
        return GLib.SOURCE_REMOVE


def watch() -> None:
    Watcher()
    # pygobject-stubs leave MainLoop.run's return type unknown
    GLib.MainLoop().run()  # pyright: ignore[reportUnknownMemberType]


def choose_image(mode: str) -> None:
    """A compressed image's size isn't known before unpacking it: 0"""
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    if mode == "open":
        uris = choose_files(bus, tr("Select a disk image"), tr("_Open"), mime_types=IMAGE_TYPES)
        uri = uris[0] if uris else ""
    else:
        uri = choose_save_file(bus, tr("Select where to save the image"), tr("_Save"), "disk.img")
    path = Gio.File.new_for_uri(uri).get_path() if uri else None
    if path is None:
        output({})
        return
    image = Path(path)
    compressed = image.suffix in COMPRESSED
    size = image.stat().st_size if mode == "open" and not compressed else 0
    output({"path": str(image), "size": size})


def read_request() -> dict[str, Any]:
    request: object = json.load(sys.stdin)
    return request if isinstance(request, dict) else {}  # pyright: ignore[reportUnknownVariableType]


def main() -> None:
    arguments = sys.argv[1:]
    commands: dict[str, Callable[[], None]] = {
        "list": list_drives,
        "plan": lambda: plan(read_request()),
        "apply": lambda: apply(read_request()),
        "watch": watch,
    }
    is_image = len(arguments) == 2 and arguments[0] == "image" and arguments[1] in ("open", "save")
    if len(arguments) == 1 and arguments[0] in commands:
        command = commands[arguments[0]]
    elif is_image:
        command = lambda: choose_image(arguments[1])  # noqa: E731
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    try:
        command()
    except GLib.Error as error:
        output({"error": error_message(error)})


if __name__ == "__main__":
    main()
