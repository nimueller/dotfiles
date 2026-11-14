# pyright: strict
"""What a drive will look like after the partition editor's planned steps
(disks.qml): the plan is checked and shown here, before disks.py writes any
of it with udisks2. Pure, without D-Bus, so the tests can run it.

A step is one change, in the order the menu lists them:

  {"op": "table", "type": "gpt"}       a new partition table ("gpt", "dos"), or none ("empty")
  {"op": "create", "offset": n, "size": n, "fs": "ext4", "label": "…", "name": "…",
   "passphrase": "…", "erase": false}  a partition in free space, with a filesystem
  {"op": "delete", "target": id}
  {"op": "format", "target": id, "fs": "exfat", "label": "…", "passphrase": "…", "erase": false}
  {"op": "resize", "target": id, "size": n}
  {"op": "label" | "name" | "type", "target": id, "value": "…"}
  {"op": "bootable", "target": id, "on": true}
  {"op": "check" | "repair" | "mount" | "unmount" | "lock", "target": id}
  {"op": "unlock", "target": id, "passphrase": "…"}
  {"op": "passphrase", "target": id, "passphrase": "old", "value": "new"}
  {"op": "restore", "image": path, "image_size": n}   the whole drive from an image
  {"op": "backup", "target": id, "image": path}       a partition or the drive into an image
  {"op": "poweroff"}

A target is a partition's udisks object path, the drive's own block object
for what's on the drive without a partition table, or "new<i>" for the
partition that step i creates. Steps with "auto": true were put in front of
the step after them because it needs them (unmount, lock); undoing that step
takes them along.
"""

import copy
import hashlib
import json
from collections.abc import Callable
from dataclasses import asdict, dataclass, field, fields

from i18n import tr

MIB = 1024**2
# udisks and parted put partitions on 1 MiB boundaries
ALIGNMENT = MIB
# The first MiB holds the partition table; GPT keeps a copy at the end
TABLE_START = MIB
GPT_BACKUP = MIB
SMALLEST_PARTITION = MIB
# A smaller gap is what's left between aligned partitions, not room for one
SMALLEST_FREE = 2 * MIB
DOS_PRIMARY_LIMIT = 4
DOS_BOOTABLE = 0x80
GPT_NAME_LIMIT = 36
TABLES = ("gpt", "dos")
NO_FILESYSTEM = "empty"
SWAP = "swap"
LUKS = "crypto_LUKS"
PLANNED_MOUNT = "*"
NEW_PREFIX = "new"
# udisks' CanResize flags (BDFSResizeFlags): the editor resizes unmounted
RESIZE_OFFLINE_SHRINK = 2
RESIZE_OFFLINE_GROW = 4

# The filesystems the editor offers, in this order, with what they're for
FILESYSTEMS = {
    "ext4": "Linux",
    "btrfs": "Linux, with snapshots",
    "xfs": "Linux, big files",
    "f2fs": "Linux, flash memory",
    "exfat": "All systems, files over 4 GB",
    "vfat": "All systems, older devices too",
    "ntfs": "Windows",
    SWAP: "Linux swap",
    NO_FILESYSTEM: "Leave the partition empty",
}
FILESYSTEM_NAMES = {
    "vfat": "FAT",
    "exfat": "exFAT",
    "ntfs": "NTFS",
    SWAP: "Swap",
    LUKS: "LUKS",
    "BitLocker": "BitLocker",
}
# Characters a filesystem's label may have; not listed: no label
LABEL_LIMITS = {
    "ext2": 16,
    "ext3": 16,
    "ext4": 16,
    "btrfs": 255,
    "xfs": 12,
    "f2fs": 512,
    "exfat": 15,
    "vfat": 11,
    "ntfs": 128,
    SWAP: 16,
}
# The owner of a new filesystem's top folder is the user, where it has one
OWNED_FILESYSTEMS = ("ext4", "btrfs", "xfs", "f2fs")

PARTITION_TYPES = {
    "gpt": {
        "0fc63daf-8483-4772-8e79-3d69d8477de4": "Linux filesystem",
        "c12a7328-f81f-11d2-ba4b-00a0c93ec93b": "EFI system",
        "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f": "Linux swap",
        "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7": "Microsoft basic data",
        "e6d6d379-f507-44c2-a23c-238f2a3df928": "Linux LVM",
        "a19d880f-05fc-4d3b-a006-743f0f84911e": "Linux RAID",
        "21686148-6449-6e6f-744e-656564454649": "BIOS boot",
        "e3c9e316-0b5c-4db8-817d-f92df00215ae": "Microsoft reserved",
        "de94bba4-06d1-4d40-a16a-bfd50179d6ac": "Windows recovery",
    },
    "dos": {
        "0x83": "Linux filesystem",
        "0xef": "EFI system",
        "0x82": "Linux swap",
        "0x07": "NTFS or exFAT",
        "0x0c": "FAT32",
        "0x8e": "Linux LVM",
        "0xfd": "Linux RAID",
    },
}

# What the menu may offer, by where
PARTITION_ACTIONS = ("format", "delete", "resize", "label", "name", "type", "bootable")
CHECK_ACTIONS = ("check", "repair")
MOUNT_ACTIONS = ("mount", "unmount")
CRYPTO_ACTIONS = ("unlock", "lock", "passphrase")
# Steps that need their target unmounted, and those that need it locked, too
NEEDS_UNMOUNTED = ("delete", "format", "resize", "check", "repair", "backup", "lock")
NEEDS_LOCKED = ("delete", "format", "resize")
# Steps that need the whole drive unmounted and locked
NEEDS_DRIVE_RELEASED = ("table", "restore", "poweroff")


@dataclass
class Volume:
    """What's on a partition, or on a drive without a partition table"""

    usage: str = ""  # udisks' IdUsage: "filesystem", "crypto", "other", "raid", "" for nothing known
    fs: str = ""  # IdType: "ext4", "crypto_LUKS", "swap", …
    label: str = ""
    mounts: list[str] = field(default_factory=list[str])
    # The unlocked content of an encrypted volume; None while it's locked
    inner: "Volume | None" = None


@dataclass
class Partition:
    id: str  # udisks object path, or "new<i>"
    number: int
    offset: int
    size: int
    type: str = ""
    name: str = ""
    flags: int = 0
    volume: Volume = field(default_factory=Volume)
    in_use: str = ""  # why it can't be changed, "" when it can
    planned: bool = False  # created by the plan
    changed: bool = False  # changed by the plan


@dataclass
class Drive:
    id: str  # udisks drive object
    block: str  # the whole drive's block object
    device: str  # "/dev/sdb"
    name: str
    size: int
    removable: bool
    table: str = ""  # "gpt", "dos", "" without one
    volume: Volume | None = None  # what's on it without a partition table
    partitions: list[Partition] = field(default_factory=list[Partition])
    in_use: str = ""  # why nothing on it can be changed
    can_power_off: bool = False
    health: str = ""
    image: str = ""  # planned: written from this image, so its layout is unknown
    powered_off: bool = False  # planned


@dataclass
class Capability:
    """What udisks can do with a filesystem, by what's installed"""

    format: bool = False
    utility: str = ""  # what's missing to format it
    resize: int = 0  # RESIZE_* flags
    check: bool = False
    repair: bool = False


@dataclass
class Step:
    op: str
    target: str = ""
    type: str = ""
    offset: int = 0
    size: int = 0
    fs: str = ""
    label: str = ""
    name: str = ""
    value: str = ""
    passphrase: str = ""
    erase: bool = False
    on: bool = False
    image: str = ""
    image_size: int = 0
    auto: bool = False


@dataclass
class Region:
    offset: int
    size: int


Capabilities = dict[str, Capability]


def step_from_json(data: dict[str, object]) -> Step:
    """A step as the menu sends it; fields of the wrong type are left out"""
    step = Step(op=str(data.get("op", "")))
    for step_field in fields(Step):
        value = data.get(step_field.name)
        if isinstance(value, type(getattr(step, step_field.name))):
            setattr(step, step_field.name, value)
    return step


def step_to_json(step: Step) -> dict[str, object]:
    return asdict(step)


# ---------- Sizes ----------


def align_up(value: int) -> int:
    return -(-value // ALIGNMENT) * ALIGNMENT


def align_down(value: int) -> int:
    return value // ALIGNMENT * ALIGNMENT


def size_text(size: int) -> str:
    """Decimal units, as drives are sold: a 64 GB stick shows 64 GB"""
    units = (("TB", 10**12), ("GB", 10**9), ("MB", 10**6), ("kB", 10**3))
    for unit, factor in units:
        if size >= factor:
            value = size / factor
            digits = 0 if value >= 100 else 1
            return f"{value:.{digits}f} {unit}"
    return f"{size} B"


def usable_end(drive: Drive) -> int:
    end = drive.size - GPT_BACKUP if drive.table == "gpt" else drive.size
    return align_down(end)


def free_regions(drive: Drive) -> list[Region]:
    """The gaps between the partitions that can hold a new one"""
    if drive.table not in TABLES:
        return []
    regions: list[Region] = []
    cursor = TABLE_START
    for partition in sorted(drive.partitions, key=lambda p: p.offset):
        if partition.offset - cursor >= SMALLEST_FREE:
            regions.append(Region(cursor, partition.offset - cursor))
        cursor = max(cursor, align_up(partition.offset + partition.size))
    end = usable_end(drive)
    if end - cursor >= SMALLEST_FREE:
        regions.append(Region(cursor, end - cursor))
    return regions


def region_around(drive: Drive, offset: int, size: int) -> Region | None:
    for region in free_regions(drive):
        if region.offset <= offset and offset + size <= region.offset + region.size:
            return region
    return None


def room_after(drive: Drive, partition: Partition) -> int:
    """How far the partition could grow: up to the next one or the end"""
    end = partition.offset + partition.size
    region = next((r for r in free_regions(drive) if r.offset == align_up(end)), None)
    if region is None:
        return 0
    return region.offset + region.size - end


# ---------- Looking things up ----------


def find_partition(drive: Drive, target: str) -> Partition | None:
    return next((p for p in drive.partitions if p.id == target), None)


def target_volume(drive: Drive, target: str) -> Volume | None:
    """The volume a step works on: a partition's, or the drive's own"""
    if target == drive.block:
        return drive.volume
    partition = find_partition(drive, target)
    return partition.volume if partition else None


def set_target_volume(drive: Drive, target: str, volume: Volume) -> None:
    if target == drive.block:
        drive.volume = volume
        return
    partition = find_partition(drive, target)
    if partition:
        partition.volume = volume
        partition.changed = True


def target_in_use(drive: Drive, target: str) -> str:
    if drive.in_use:
        return drive.in_use
    partition = find_partition(drive, target)
    return partition.in_use if partition else ""


def content(volume: Volume) -> Volume | None:
    """Where the filesystem is: inside an unlocked encrypted volume, or the
    volume itself; None while it's locked"""
    if volume.usage == "crypto":
        return volume.inner
    return volume


def is_mounted(volume: Volume) -> bool:
    inside = content(volume)
    return inside is not None and len(inside.mounts) > 0


def is_unlocked(volume: Volume) -> bool:
    return volume.usage == "crypto" and volume.inner is not None


def drive_volumes(drive: Drive) -> list[tuple[str, Volume]]:
    """(target, volume) of everything on the drive"""
    found = [(partition.id, partition.volume) for partition in drive.partitions]
    if drive.volume:
        found.append((drive.block, drive.volume))
    return found


def drive_in_use(drive: Drive) -> str:
    if drive.in_use:
        return drive.in_use
    return next((p.in_use for p in drive.partitions if p.in_use), "")


def partition_device(drive: Drive, number: int) -> str:
    """/dev/sdb and 2 → sdb2, /dev/nvme0n1 and 2 → nvme0n1p2"""
    base = drive.device.removeprefix("/dev/")
    separator = "p" if base[-1:].isdigit() else ""
    return f"{base}{separator}{number}"


def next_number(drive: Drive) -> int:
    """The number parted gives a new partition: the lowest that's free"""
    taken = {partition.number for partition in drive.partitions}
    number = 1
    while number in taken:
        number += 1
    return number


# ---------- Words ----------


def filesystem_name(fs: str) -> str:
    if fs == NO_FILESYSTEM:
        return tr("No filesystem")
    return FILESYSTEM_NAMES.get(fs, fs)


def volume_text(volume: Volume) -> str:
    """ "ext4 "Stick"", "LUKS, locked", "Empty" """
    if volume.usage == "crypto":
        name = filesystem_name(volume.fs)
        inside = volume.inner
        if inside is None:
            return tr("%1, locked", name)
        return tr("%1, unlocked: %2", name, volume_text(inside))
    if volume.fs == "":
        return tr("Unknown content") if volume.usage else tr("Empty")
    name = filesystem_name(volume.fs)
    return f'{name} "{volume.label}"' if volume.label else name


def mounts_text(volume: Volume) -> str:
    inside = content(volume)
    if inside is None or len(inside.mounts) == 0:
        return ""
    if inside.mounts[0] == PLANNED_MOUNT:
        return tr("will be mounted")
    return tr("mounted at %1", inside.mounts[0])


def partition_title(drive: Drive, partition: Partition) -> str:
    return partition_device(drive, partition.number)


def target_title(drive: Drive, target: str) -> str:
    """How a step names its target: "sdb2 (8.0 GB, ext4)" """
    if target == drive.block:
        return tr("%1 (whole drive)", drive.device.removeprefix("/dev/"))
    partition = find_partition(drive, target)
    if partition is None:
        return tr("a partition that's gone")
    title = partition_title(drive, partition)
    return f"{title} ({size_text(partition.size)}, {volume_text(partition.volume)})"


def new_volume_text(step: Step) -> str:
    text = filesystem_name(step.fs)
    if step.label:
        text = f'{text} "{step.label}"'
    if step.passphrase:
        text = tr("%1, encrypted", text)
    if step.erase:
        text = tr("%1, overwritten with zeros", text)
    return text


def table_name(table: str) -> str:
    names = {"gpt": tr("GPT"), "dos": tr("MBR (DOS)"), NO_FILESYSTEM: tr("none")}
    return names.get(table, table)


def type_name(drive: Drive, partition_type: str) -> str:
    known = PARTITION_TYPES.get(drive.table, {})
    return tr(known[partition_type]) if partition_type in known else partition_type


def step_text(drive: Drive, step: Step) -> str:
    """What the step does, in the menu's list; drive is the state before it"""
    texts: dict[str, Callable[[], str]] = {
        "table": lambda: tr("New partition table: %1, everything on the drive is lost", table_name(step.type)),
        "create": lambda: tr("New partition, %1: %2", size_text(step.size), new_volume_text(step)),
        "delete": lambda: tr("Delete %1", target_title(drive, step.target)),
        "format": lambda: tr("Format %1 as %2", target_title(drive, step.target), new_volume_text(step)),
        "resize": lambda: tr("Resize %1 to %2", target_title(drive, step.target), size_text(step.size)),
        "label": lambda: tr('Label of %1: "%2"', target_title(drive, step.target), step.value),
        "name": lambda: tr('Partition name of %1: "%2"', target_title(drive, step.target), step.value),
        "type": lambda: tr("Partition type of %1: %2", target_title(drive, step.target), type_name(drive, step.value)),
        "bootable": lambda: bootable_text(drive, step),
        "check": lambda: tr("Check %1", target_title(drive, step.target)),
        "repair": lambda: tr("Repair %1", target_title(drive, step.target)),
        "mount": lambda: tr("Mount %1", target_title(drive, step.target)),
        "unmount": lambda: tr("Unmount %1", target_title(drive, step.target)),
        "unlock": lambda: tr("Unlock %1", target_title(drive, step.target)),
        "lock": lambda: tr("Lock %1", target_title(drive, step.target)),
        "passphrase": lambda: tr("Change the passphrase of %1", target_title(drive, step.target)),
        "restore": lambda: tr("Write the image %1 to the drive, everything on it is lost", file_name(step.image)),
        "backup": lambda: tr("Save %1 as the image %2", target_title(drive, step.target), file_name(step.image)),
        "poweroff": lambda: tr("Power off the drive"),
    }
    text = texts.get(step.op)
    return text() if text else step.op


def bootable_text(drive: Drive, step: Step) -> str:
    if step.on:
        return tr("Mark %1 as bootable", target_title(drive, step.target))
    return tr("Mark %1 as not bootable", target_title(drive, step.target))


def file_name(path: str) -> str:
    return path.rsplit("/", 1)[-1]


# ---------- Checking and applying one step to the plan ----------


def check_new_volume(step: Step, capabilities: Capabilities) -> str:
    """The filesystem, label and passphrase of a create or format step"""
    if step.fs != NO_FILESYSTEM:
        capability = capabilities.get(step.fs)
        if capability is None:
            return tr("Unknown filesystem %1", step.fs)
        if not capability.format:
            return tr("Formatting %1 needs %2 installed", filesystem_name(step.fs), capability.utility)
    if step.passphrase and step.fs in (NO_FILESYSTEM, SWAP):
        return tr("Only a filesystem can be encrypted")
    return check_label(step.fs, step.label)


def check_label(fs: str, label: str) -> str:
    if label == "":
        return ""
    limit = LABEL_LIMITS.get(fs)
    if limit is None:
        return tr("%1 has no label", filesystem_name(fs))
    if len(label) > limit:
        return tr("A %1 label has at most %2 characters", filesystem_name(fs), limit)
    return ""


def new_volume(step: Step) -> Volume:
    if step.fs == NO_FILESYSTEM:
        return Volume()
    usage = "other" if step.fs == SWAP else "filesystem"
    filesystem = Volume(usage=usage, fs=step.fs, label=step.label)
    if step.passphrase:
        # udisks leaves it unlocked after formatting
        return Volume(usage="crypto", fs=LUKS, inner=filesystem)
    return filesystem


def check_released(drive: Drive, target: str, op: str) -> str:
    """Whether the target is unmounted and locked as far as op needs"""
    volume = target_volume(drive, target)
    if volume is None:
        return ""
    if op in NEEDS_UNMOUNTED and is_mounted(volume):
        return tr("%1 is mounted", target_title(drive, target))
    if op in NEEDS_LOCKED and is_unlocked(volume):
        return tr("%1 is unlocked", target_title(drive, target))
    return ""


def check_drive_released(drive: Drive) -> str:
    for target, volume in drive_volumes(drive):
        if is_mounted(volume):
            return tr("%1 is mounted", target_title(drive, target))
        if is_unlocked(volume):
            return tr("%1 is unlocked", target_title(drive, target))
    return ""


def apply_table(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    problem = drive_in_use(drive) or check_drive_released(drive)
    if problem:
        return problem
    if step.type not in (*TABLES, NO_FILESYSTEM):
        return tr("Unknown partition table %1", step.type)
    drive.table = step.type if step.type in TABLES else ""
    drive.partitions = []
    drive.volume = None
    return ""


def apply_create(drive: Drive, step: Step, index: int, capabilities: Capabilities) -> str:
    if drive.table not in TABLES:
        return tr("The drive has no partition table")
    if drive.table == "dos" and len(drive.partitions) >= DOS_PRIMARY_LIMIT:
        return tr("An MBR partition table holds at most four partitions")
    offset = align_up(step.offset)
    size = align_down(step.offset + step.size) - offset
    if size < SMALLEST_PARTITION:
        return tr("The partition is too small")
    if region_around(drive, offset, size) is None:
        return tr("The partition doesn't fit into the free space")
    problem = check_new_volume(step, capabilities)
    if problem:
        return problem
    partition = Partition(
        id=f"{NEW_PREFIX}{index}",
        number=next_number(drive),
        offset=offset,
        size=size,
        name=step.name,
        volume=new_volume(step),
        planned=True,
        changed=True,
    )
    drive.partitions.append(partition)
    drive.partitions.sort(key=lambda p: p.offset)
    return ""


def apply_delete(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    partition = find_partition(drive, step.target)
    if partition is None:
        return tr("The partition is gone")
    problem = partition.in_use or check_released(drive, step.target, step.op)
    if problem:
        return problem
    drive.partitions.remove(partition)
    return ""


def apply_format(drive: Drive, step: Step, _index: int, capabilities: Capabilities) -> str:
    if target_volume(drive, step.target) is None:
        return tr("The partition is gone")
    problem = target_in_use(drive, step.target) or check_released(drive, step.target, step.op)
    if problem:
        return problem
    problem = check_new_volume(step, capabilities)
    if problem:
        return problem
    set_target_volume(drive, step.target, new_volume(step))
    return ""


def check_resizable(partition: Partition, size: int, capabilities: Capabilities) -> str:
    volume = partition.volume
    if volume.usage == "crypto":
        return tr("Encrypted partitions can't be resized here")
    if volume.usage == "":
        return ""
    flags = capabilities.get(volume.fs, Capability()).resize
    needed = RESIZE_OFFLINE_SHRINK if size < partition.size else RESIZE_OFFLINE_GROW
    if flags & needed == 0:
        return tr("%1 can't be resized like this", filesystem_name(volume.fs))
    return ""


def apply_resize(drive: Drive, step: Step, _index: int, capabilities: Capabilities) -> str:
    partition = find_partition(drive, step.target)
    if partition is None:
        return tr("The partition is gone")
    problem = partition.in_use or check_released(drive, step.target, step.op)
    if problem:
        return problem
    size = align_down(step.size)
    if size < SMALLEST_PARTITION:
        return tr("The partition is too small")
    if size > partition.size + room_after(drive, partition):
        return tr("There's not enough free space after the partition")
    problem = check_resizable(partition, size, capabilities)
    if problem:
        return problem
    partition.size = size
    partition.changed = True
    return ""


def apply_label(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    volume = target_volume(drive, step.target)
    inside = content(volume) if volume else None
    if inside is None or inside.usage not in ("filesystem", "other"):
        return tr("There's no filesystem to label")
    problem = target_in_use(drive, step.target) or check_label(inside.fs, step.value)
    if problem:
        return problem
    inside.label = step.value
    mark_changed(drive, step.target)
    return ""


def apply_name(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    partition = find_partition(drive, step.target)
    if partition is None or drive.table != "gpt":
        return tr("Only GPT partitions have a name")
    if len(step.value) > GPT_NAME_LIMIT:
        return tr("A partition name has at most %1 characters", GPT_NAME_LIMIT)
    problem = partition.in_use
    if problem:
        return problem
    partition.name = step.value
    partition.changed = True
    return ""


def apply_type(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    partition = find_partition(drive, step.target)
    if partition is None:
        return tr("The partition is gone")
    if step.value not in PARTITION_TYPES.get(drive.table, {}):
        return tr("Unknown partition type %1", step.value)
    problem = partition.in_use
    if problem:
        return problem
    partition.type = step.value
    partition.changed = True
    return ""


def apply_bootable(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    partition = find_partition(drive, step.target)
    if partition is None or drive.table != "dos":
        return tr("Only MBR partitions have a bootable flag")
    problem = partition.in_use
    if problem:
        return problem
    if step.on:
        partition.flags |= DOS_BOOTABLE
    else:
        partition.flags &= ~DOS_BOOTABLE
    partition.changed = True
    return ""


def apply_check(drive: Drive, step: Step, _index: int, capabilities: Capabilities) -> str:
    """check and repair: nothing changes in the plan"""
    volume = target_volume(drive, step.target)
    inside = content(volume) if volume else None
    if inside is None or inside.usage != "filesystem":
        return tr("There's no filesystem to check")
    capability = capabilities.get(inside.fs, Capability())
    can = capability.check if step.op == "check" else capability.repair
    if not can:
        return tr("%1 can't be checked or repaired here", filesystem_name(inside.fs))
    return target_in_use(drive, step.target) or check_released(drive, step.target, step.op)


def apply_mount(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    volume = target_volume(drive, step.target)
    inside = content(volume) if volume else None
    if inside is None or inside.usage != "filesystem":
        return tr("There's no filesystem to mount")
    if inside.mounts:
        return tr("%1 is mounted", target_title(drive, step.target))
    problem = target_in_use(drive, step.target)
    if problem:
        return problem
    inside.mounts = [PLANNED_MOUNT]
    return ""


def apply_unmount(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    volume = target_volume(drive, step.target)
    inside = content(volume) if volume else None
    if inside is None or len(inside.mounts) == 0:
        return tr("%1 isn't mounted", target_title(drive, step.target))
    problem = target_in_use(drive, step.target)
    if problem:
        return problem
    inside.mounts = []
    return ""


def encrypted_volume(drive: Drive, target: str) -> tuple[Volume | None, str]:
    """The target's volume if it's encrypted, else why not"""
    volume = target_volume(drive, target)
    if volume is None or volume.usage != "crypto":
        return None, tr("%1 isn't encrypted", target_title(drive, target))
    problem = target_in_use(drive, target)
    return (None, problem) if problem else (volume, "")


def apply_unlock(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    volume, problem = encrypted_volume(drive, step.target)
    if volume is None:
        return problem
    if volume.inner is not None:
        return tr("%1 is unlocked", target_title(drive, step.target))
    if step.passphrase == "":
        return tr("The passphrase is missing")
    # What's inside shows only once it's unlocked
    volume.inner = Volume(usage="filesystem")
    return ""


def apply_lock(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    volume, problem = encrypted_volume(drive, step.target)
    if volume is None:
        return problem
    if volume.inner is None:
        return tr("%1 is locked", target_title(drive, step.target))
    problem = check_released(drive, step.target, step.op)
    if problem:
        return problem
    volume.inner = None
    return ""


def apply_passphrase(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    volume, problem = encrypted_volume(drive, step.target)
    if volume is None:
        return problem
    if volume.fs != LUKS:
        return tr("Only a LUKS passphrase can be changed here")
    if step.passphrase == "" or step.value == "":
        return tr("The passphrase is missing")
    return ""


def apply_restore(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    problem = drive_in_use(drive) or check_drive_released(drive)
    if problem:
        return problem
    if step.image == "":
        return tr("No image chosen")
    if step.image_size > drive.size:
        return tr("The image (%1) is bigger than the drive", size_text(step.image_size))
    drive.image = step.image
    drive.table = ""
    drive.partitions = []
    drive.volume = None
    return ""


def apply_backup(drive: Drive, step: Step, _index: int, _capabilities: Capabilities) -> str:
    if step.image == "":
        return tr("No image chosen")
    if step.target != drive.block and find_partition(drive, step.target) is None:
        return tr("The partition is gone")
    if step.target == drive.block:
        return drive_in_use(drive) or check_drive_released(drive)
    return target_in_use(drive, step.target) or check_released(drive, step.target, step.op)


def apply_poweroff(drive: Drive, _step: Step, _index: int, _capabilities: Capabilities) -> str:
    if not drive.can_power_off:
        return tr("This drive can't be powered off")
    problem = drive_in_use(drive) or check_drive_released(drive)
    if problem:
        return problem
    drive.powered_off = True
    return ""


def mark_changed(drive: Drive, target: str) -> None:
    partition = find_partition(drive, target)
    if partition:
        partition.changed = True


APPLY: dict[str, Callable[[Drive, Step, int, Capabilities], str]] = {
    "table": apply_table,
    "create": apply_create,
    "delete": apply_delete,
    "format": apply_format,
    "resize": apply_resize,
    "label": apply_label,
    "name": apply_name,
    "type": apply_type,
    "bootable": apply_bootable,
    "check": apply_check,
    "repair": apply_check,
    "mount": apply_mount,
    "unmount": apply_unmount,
    "unlock": apply_unlock,
    "lock": apply_lock,
    "passphrase": apply_passphrase,
    "restore": apply_restore,
    "backup": apply_backup,
    "poweroff": apply_poweroff,
}


def apply_step(drive: Drive, step: Step, index: int, capabilities: Capabilities) -> str:
    """Why the step can't be done, "" when it can; then the drive shows it"""
    if drive.powered_off:
        return tr("The drive is powered off by then")
    if drive.image and step.op != "poweroff":
        return tr("After writing the image, the drive's layout isn't known yet")
    apply = APPLY.get(step.op)
    if apply is None:
        return tr("Unknown step %1", step.op)
    return apply(drive, step, index, capabilities)


@dataclass
class Plan:
    drive: Drive  # as it will be
    texts: list[str]  # what each step does
    problems: list[str]  # why a step can't be done, "" where it can


def simulate(drive: Drive, steps: list[Step], capabilities: Capabilities) -> Plan:
    planned = copy.deepcopy(drive)
    texts: list[str] = []
    problems: list[str] = []
    for index, step in enumerate(steps):
        texts.append(step_text(planned, step))
        problems.append(apply_step(planned, step, index, capabilities))
    return Plan(planned, texts, problems)


# ---------- Unmount and lock before a step that needs it ----------


def release_steps(drive: Drive, target: str, op: str) -> list[Step]:
    volume = target_volume(drive, target)
    if volume is None or target_in_use(drive, target):
        return []
    steps: list[Step] = []
    if op in NEEDS_UNMOUNTED and is_mounted(volume):
        steps.append(Step("unmount", target, auto=True))
    if op in NEEDS_LOCKED and is_unlocked(volume):
        steps.append(Step("lock", target, auto=True))
    return steps


def drive_release_steps(drive: Drive) -> list[Step]:
    if drive_in_use(drive):
        return []
    steps: list[Step] = []
    for target, volume in drive_volumes(drive):
        if is_mounted(volume):
            steps.append(Step("unmount", target, auto=True))
        if is_unlocked(volume):
            steps.append(Step("lock", target, auto=True))
    return steps


def with_step(drive: Drive, steps: list[Step], step: Step, capabilities: Capabilities) -> list[Step]:
    """The steps with one more at the end, after the unmount and lock steps
    it needs; nothing is unmounted without a step for it"""
    state = simulate(drive, steps, capabilities).drive
    whole_drive_backup = step.op == "backup" and step.target == state.block
    if step.op in NEEDS_DRIVE_RELEASED or whole_drive_backup:
        needed = drive_release_steps(state)
    else:
        needed = release_steps(state, step.target, step.op)
    return [*steps, *needed, step]


# ---------- What the menu shows ----------


def partition_actions(drive: Drive, partition: Partition, capabilities: Capabilities) -> list[str]:
    if partition.in_use or drive.powered_off:
        return []
    actions = ["format", "delete"]
    if not partition.planned and partition.volume.usage != "crypto":
        actions.append("resize")
    if drive.table == "gpt":
        actions.append("name")
    actions.append("type")
    if drive.table == "dos":
        actions.append("bootable")
    actions += volume_actions(partition.volume, capabilities)
    if not partition.planned:
        actions.append("backup")
    return actions


def volume_actions(volume: Volume, capabilities: Capabilities) -> list[str]:
    """What can be done with the filesystem, and with its encryption"""
    actions: list[str] = []
    if volume.usage == "crypto":
        actions.append("lock" if volume.inner else "unlock")
    if volume.fs == LUKS:
        actions.append("passphrase")
    inside = content(volume)
    if inside is None:
        return actions
    if inside.fs in LABEL_LIMITS:
        actions.append("label")
    if inside.usage == "filesystem":
        actions.append("unmount" if inside.mounts else "mount")
    capability = capabilities.get(inside.fs, Capability())
    if capability.check:
        actions.append("check")
    if capability.repair:
        actions.append("repair")
    return actions


def drive_actions(drive: Drive) -> list[str]:
    if drive_in_use(drive) or drive.powered_off:
        return []
    actions = ["table", "erase", "restore"]
    if not drive.image:
        actions.append("backup")
    if drive.can_power_off:
        actions.append("poweroff")
    return actions


def partition_view(drive: Drive, partition: Partition, capabilities: Capabilities) -> dict[str, object]:
    volume = partition.volume
    inside = content(volume)
    details = [volume_text(volume)]
    if partition.name:
        details.append(f'"{partition.name}"')
    if partition.flags & DOS_BOOTABLE and drive.table == "dos":
        details.append(tr("bootable"))
    mounted = mounts_text(volume)
    if mounted:
        details.append(mounted)
    return {
        "kind": "partition",
        "id": partition.id,
        "title": partition_title(drive, partition),
        "detail": " · ".join(details),
        "fs": inside.fs if inside else volume.fs,
        "encrypted": volume.usage == "crypto",
        "label": inside.label if inside else "",
        "name": partition.name,
        "type": partition.type,
        "bootable": partition.flags & DOS_BOOTABLE != 0,
        "offset": partition.offset,
        "size": partition.size,
        "sizeText": size_text(partition.size),
        "maxSize": partition.size + room_after(drive, partition),
        "inUse": partition.in_use,
        "planned": partition.planned,
        "changed": partition.changed,
        "actions": partition_actions(drive, partition, capabilities),
    }


def free_view(drive: Drive, region: Region) -> dict[str, object]:
    can_create = drive.table != "dos" or len(drive.partitions) < DOS_PRIMARY_LIMIT
    return {
        "kind": "free",
        "id": f"free{region.offset}",
        "title": tr("Free space"),
        "detail": "",
        "offset": region.offset,
        "size": region.size,
        "sizeText": size_text(region.size),
        "actions": ["create"] if can_create and not drive.powered_off else [],
    }


def whole_view(drive: Drive, capabilities: Capabilities) -> dict[str, object]:
    """The drive without a partition table: what's on it, or the image"""
    volume = drive.volume or Volume()
    if drive.image:
        detail = tr("From the image %1", file_name(drive.image))
    else:
        detail = " · ".join(text for text in (volume_text(volume), mounts_text(volume)) if text)
    inside = content(volume)
    actions: list[str] = []
    if drive.volume and not drive_in_use(drive) and not drive.powered_off:
        actions = ["format", *volume_actions(drive.volume, capabilities)]
    return {
        "kind": "whole",
        "id": drive.block,
        "title": tr("Whole drive"),
        "detail": detail,
        "fs": inside.fs if inside else volume.fs,
        "encrypted": volume.usage == "crypto",
        "label": inside.label if inside else "",
        "offset": 0,
        "size": drive.size,
        "sizeText": size_text(drive.size),
        "inUse": drive.in_use,
        "changed": drive.image != "",
        "actions": actions,
    }


def segments(drive: Drive, capabilities: Capabilities) -> list[dict[str, object]]:
    """The partitions and the free space between them, from the start"""
    if drive.table not in TABLES:
        return [whole_view(drive, capabilities)]
    found = [(p.offset, partition_view(drive, p, capabilities)) for p in drive.partitions]
    found += [(region.offset, free_view(drive, region)) for region in free_regions(drive)]
    found.sort(key=lambda pair: pair[0])
    return [view for _offset, view in found]


def revision(drive: Drive) -> str:
    """Changes with the drive's layout, not with its health"""
    layout = asdict(drive)
    layout.pop("health")
    text = json.dumps(layout, sort_keys=True)
    return hashlib.sha256(text.encode()).hexdigest()[:16]


def drive_view(drive: Drive, capabilities: Capabilities) -> dict[str, object]:
    details = [size_text(drive.size)]
    if drive.table in TABLES:
        details.append(table_name(drive.table))
    if drive.health:
        details.append(drive.health)
    return {
        "id": drive.id,
        "block": drive.block,
        "device": drive.device,
        "name": drive.name,
        "detail": " · ".join(details),
        "size": drive.size,
        "removable": drive.removable,
        "table": drive.table,
        "inUse": drive_in_use(drive),
        "revision": revision(drive),
        "actions": drive_actions(drive),
        "segments": segments(drive, capabilities),
    }


def filesystem_views(capabilities: Capabilities) -> list[dict[str, object]]:
    views: list[dict[str, object]] = []
    for fs, purpose in FILESYSTEMS.items():
        capability = capabilities.get(fs, Capability(format=fs == NO_FILESYSTEM))
        views.append(
            {
                "id": fs,
                "title": filesystem_name(fs),
                "detail": tr(purpose),
                "available": capability.format,
                "utility": capability.utility,
                "labelLimit": LABEL_LIMITS.get(fs, 0),
                "encryptable": fs not in (NO_FILESYSTEM, SWAP),
            }
        )
    return views


def type_views() -> dict[str, list[dict[str, str]]]:
    return {
        table: [{"id": type_id, "title": tr(title)} for type_id, title in types.items()]
        for table, types in PARTITION_TYPES.items()
    }
