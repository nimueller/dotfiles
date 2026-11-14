# pyright: strict
"""The drives as udisks2 describes them, read into disk_layout's Drive for
the partition editor (disks.py). `objects` is GetManagedObjects' answer,
unpacked: {object path: {interface: {property: value}}}, byte strings as
lists of numbers. Pure, for the tests.

What the running system uses can't be changed: a partition with a system
mount point (also inside an unlocked LUKS volume), active swap, members of a
RAID or LVM. The rest of that drive stays editable.
"""

from typing import Any

from disk_layout import Drive, Partition, Volume
from i18n import tr

PREFIX = "org.freedesktop.UDisks2."
BLOCK = PREFIX + "Block"
DRIVE = PREFIX + "Drive"
ATA = PREFIX + "Drive.Ata"
NVME = PREFIX + "NVMe.Controller"
PARTITION = PREFIX + "Partition"
TABLE = PREFIX + "PartitionTable"
FILESYSTEM = PREFIX + "Filesystem"
ENCRYPTED = PREFIX + "Encrypted"
SWAPSPACE = PREFIX + "Swapspace"
LOOP = PREFIX + "Loop"
NO_OBJECT = "/"
SYSTEM_MOUNTS = ("/", "/boot", "/boot/efi", "/efi", "/home", "/nix", "/usr", "/var")
KELVIN = 273.15

Objects = dict[str, dict[str, dict[str, Any]]]


def text(value: object) -> str:
    """A byte string from udisks (a list of numbers, ending in 0) as text"""
    if isinstance(value, str):
        return value
    if not isinstance(value, list):
        return ""
    numbers = [n for n in value if isinstance(n, int)]  # pyright: ignore[reportUnknownVariableType]
    return bytes(numbers).rstrip(b"\0").decode(errors="replace")


def mount_points(interfaces: dict[str, dict[str, Any]]) -> list[str]:
    points: list[object] = interfaces.get(FILESYSTEM, {}).get("MountPoints", [])
    return [text(point) for point in points]


def cleartext_of(objects: Objects, path: str) -> str:
    """The unlocked device of an encrypted block, "" while it's locked"""
    for other, interfaces in objects.items():
        if interfaces.get(BLOCK, {}).get("CryptoBackingDevice") == path:
            return other
    return ""


def read_volume(objects: Objects, path: str) -> Volume:
    interfaces = objects.get(path, {})
    block = interfaces.get(BLOCK, {})
    volume = Volume(
        usage=str(block.get("IdUsage", "")),
        fs=str(block.get("IdType", "")),
        label=str(block.get("IdLabel", "")),
        mounts=mount_points(interfaces),
    )
    if ENCRYPTED in interfaces:
        cleartext = cleartext_of(objects, path)
        volume.inner = read_volume(objects, cleartext) if cleartext else None
    return volume


def in_use(objects: Objects, path: str) -> str:
    """Why the running system needs this block, "" when it doesn't"""
    interfaces = objects.get(path, {})
    block = interfaces.get(BLOCK, {})
    if any(point in SYSTEM_MOUNTS for point in mount_points(interfaces)):
        return tr("Used by the running system")
    if interfaces.get(SWAPSPACE, {}).get("Active"):
        return tr("Swap in use")
    if block.get("MDRaidMember", NO_OBJECT) != NO_OBJECT or block.get("IdUsage") == "raid":
        return tr("Part of a RAID or LVM")
    if interfaces.get(PARTITION, {}).get("IsContainer"):
        return tr("Holds logical partitions")
    cleartext = cleartext_of(objects, path) if ENCRYPTED in interfaces else ""
    return in_use(objects, cleartext) if cleartext else ""


def read_partitions(objects: Objects, table: str) -> list[Partition]:
    partitions: list[Partition] = []
    for path, interfaces in objects.items():
        partition = interfaces.get(PARTITION)
        if partition is None or partition.get("Table") != table:
            continue
        partitions.append(
            Partition(
                id=path,
                number=int(partition.get("Number", 0)),
                offset=int(partition.get("Offset", 0)),
                size=int(partition.get("Size", 0)),
                type=str(partition.get("Type", "")),
                name=str(partition.get("Name", "")),
                flags=int(partition.get("Flags", 0)),
                volume=read_volume(objects, path),
                in_use=in_use(objects, path),
            )
        )
    return sorted(partitions, key=lambda p: p.offset)


def whole_block(objects: Objects, drive: str) -> str:
    """The block of the whole drive: not a partition, not an unlocked LUKS"""
    for path, interfaces in objects.items():
        block = interfaces.get(BLOCK)
        if block is None or block.get("Drive") != drive or PARTITION in interfaces:
            continue
        if block.get("CryptoBackingDevice", NO_OBJECT) == NO_OBJECT:
            return path
    return ""


def health(interfaces: dict[str, dict[str, Any]]) -> str:
    """ "Healthy · 34 °C" from SMART, "" without it"""
    ata = interfaces.get(ATA, {})
    nvme = interfaces.get(NVME, {})
    if ata.get("SmartEnabled"):
        state = tr("Failing") if ata.get("SmartFailing") else tr("Healthy")
        kelvin = float(ata.get("SmartTemperature", 0))
    elif nvme.get("SmartUpdated"):
        state = tr("Failing") if nvme.get("SmartCriticalWarning") else tr("Healthy")
        kelvin = float(nvme.get("SmartTemperature", 0))
    else:
        return ""
    if kelvin <= 0:
        return state
    return f"{state} · {round(kelvin - KELVIN)} °C"


def drive_name(drive: dict[str, Any], device: str) -> str:
    name = f"{drive.get('Vendor', '')} {drive.get('Model', '')}".strip()
    return name or device


def drive_lock(drive: dict[str, Any]) -> str:
    """Why nothing on the drive can be changed"""
    if drive.get("Optical"):
        return tr("Optical drives aren't supported")
    if not drive.get("MediaAvailable", True):
        return tr("No medium inserted")
    return ""


def read_drive(objects: Objects, path: str) -> Drive | None:
    block_path = whole_block(objects, path)
    if block_path == "":
        return None
    interfaces = objects[path]
    drive = interfaces[DRIVE]
    block_interfaces = objects[block_path]
    device = text(block_interfaces[BLOCK].get("PreferredDevice") or block_interfaces[BLOCK].get("Device"))
    return fill_layout(
        objects,
        Drive(
            id=path,
            block=block_path,
            device=device,
            name=drive_name(drive, device),
            size=int(block_interfaces[BLOCK].get("Size", 0)),
            removable=bool(drive.get("Removable") or drive.get("MediaRemovable")),
            in_use=drive_lock(drive),
            can_power_off=bool(drive.get("CanPowerOff")),
            health=health(interfaces),
        ),
    )


def read_loop(objects: Objects, path: str) -> Drive | None:
    """A loop device with a file behind it, as a drive of its own"""
    interfaces = objects[path]
    block = interfaces[BLOCK]
    size = int(block.get("Size", 0))
    if size == 0:
        return None
    backing = text(interfaces[LOOP].get("BackingFile", ""))
    device = text(block.get("Device"))
    return fill_layout(
        objects,
        Drive(
            id=path,
            block=path,
            device=device,
            name=tr("Loop device %1", backing.rsplit("/", 1)[-1] or device),
            size=size,
            removable=False,
        ),
    )


def fill_layout(objects: Objects, drive: Drive) -> Drive:
    """Its partitions, or what's on it without a partition table"""
    interfaces = objects[drive.block]
    table = interfaces.get(TABLE)
    if table is not None:
        drive.table = str(table.get("Type", ""))
        drive.partitions = read_partitions(objects, drive.block)
        return drive
    volume = read_volume(objects, drive.block)
    drive.volume = volume if volume.usage or volume.fs else None
    drive.in_use = drive.in_use or in_use(objects, drive.block)
    return drive


def read_drives(objects: Objects) -> list[Drive]:
    """Every drive and loop device, removable ones first"""
    drives: list[Drive] = []
    for path, interfaces in objects.items():
        found = None
        if DRIVE in interfaces:
            found = read_drive(objects, path)
        elif LOOP in interfaces and BLOCK in interfaces:
            found = read_loop(objects, path)
        if found is not None:
            drives.append(found)
    return sorted(drives, key=lambda d: (not d.removable, d.device))
