# pyright: strict
import unittest
from typing import Any

from helpers import load

# disk_objects.py imports it
load("config/quickshell/menus/disk_layout.py")
disk_objects = load("config/quickshell/menus/disk_objects.py")

PREFIX = "org.freedesktop.UDisks2."
STICK = "/org/freedesktop/UDisks2/drives/Stick"
SSD = "/org/freedesktop/UDisks2/drives/SSD"
DEVICES = "/org/freedesktop/UDisks2/block_devices/"


def path_bytes(text: str) -> list[int]:
    """A path as udisks sends it: bytes ending in 0"""
    return [*text.encode(), 0]


def block(device: str, drive: str = "/", **properties: Any) -> dict[str, Any]:
    return {
        "Device": path_bytes(device),
        "PreferredDevice": path_bytes(device),
        "Drive": drive,
        "Size": properties.pop("Size", 0),
        "IdUsage": properties.pop("IdUsage", ""),
        "IdType": properties.pop("IdType", ""),
        "IdLabel": properties.pop("IdLabel", ""),
        "CryptoBackingDevice": properties.pop("CryptoBackingDevice", "/"),
        "MDRaidMember": "/",
        **properties,
    }


def mounted(*points: str) -> dict[str, Any]:
    return {"MountPoints": [path_bytes(point) for point in points]}


def partition(table: str, number: int, offset: int, size: int) -> dict[str, Any]:
    return {"Table": table, "Number": number, "Offset": offset, "Size": size, "Type": "", "Name": "", "Flags": 0}


GIB = 1024**3
OBJECTS: dict[str, dict[str, dict[str, Any]]] = {
    STICK: {
        PREFIX + "Drive": {"Vendor": "Brand", "Model": "Stick", "Removable": True, "CanPowerOff": True},
    },
    DEVICES + "sdb": {
        PREFIX + "Block": block("/dev/sdb", STICK, Size=8 * GIB),
        PREFIX + "PartitionTable": {"Type": "gpt"},
    },
    DEVICES + "sdb1": {
        PREFIX + "Block": block("/dev/sdb1", STICK, Size=GIB, IdUsage="filesystem", IdType="exfat", IdLabel="Photos"),
        PREFIX + "Partition": partition(DEVICES + "sdb", 1, 1024**2, GIB),
        PREFIX + "Filesystem": mounted("/run/media/someone/Photos"),
    },
    SSD: {
        PREFIX + "Drive": {"Vendor": "", "Model": "SSD", "Removable": False},
        PREFIX + "Drive.Ata": {"SmartEnabled": True, "SmartFailing": False, "SmartTemperature": 308.15},
    },
    DEVICES + "sda": {
        PREFIX + "Block": block("/dev/sda", SSD, Size=256 * GIB),
        PREFIX + "PartitionTable": {"Type": "gpt"},
    },
    DEVICES + "sda2": {
        PREFIX + "Block": block("/dev/sda2", SSD, Size=200 * GIB, IdUsage="crypto", IdType="crypto_LUKS"),
        PREFIX + "Partition": partition(DEVICES + "sda", 2, 2 * GIB, 200 * GIB),
        PREFIX + "Encrypted": {},
    },
    # The unlocked root filesystem: no drive of its own
    DEVICES + "dm_2d0": {
        PREFIX + "Block": block(
            "/dev/dm-0", IdUsage="filesystem", IdType="ext4", CryptoBackingDevice=DEVICES + "sda2", Size=200 * GIB
        ),
        PREFIX + "Filesystem": mounted("/"),
    },
    DEVICES + "sda1": {
        PREFIX + "Block": block("/dev/sda1", SSD, Size=GIB, IdUsage="other", IdType="swap"),
        PREFIX + "Partition": partition(DEVICES + "sda", 1, 1024**2, GIB),
        PREFIX + "Swapspace": {"Active": True},
    },
    DEVICES + "loop0": {
        PREFIX + "Block": block("/dev/loop0", Size=GIB, IdUsage="filesystem", IdType="vfat"),
        PREFIX + "Loop": {"BackingFile": path_bytes("/home/someone/test.img")},
        PREFIX + "Filesystem": mounted(),
    },
    # A loop device without a file
    DEVICES + "loop1": {
        PREFIX + "Block": block("/dev/loop1"),
        PREFIX + "Loop": {"BackingFile": path_bytes("")},
    },
}


class Reading(unittest.TestCase):
    def setUp(self) -> None:
        self.drives = {drive.device: drive for drive in disk_objects.read_drives(OBJECTS)}

    def test_drives_removable_first(self) -> None:
        devices = [drive.device for drive in disk_objects.read_drives(OBJECTS)]
        self.assertEqual(devices, ["/dev/sdb", "/dev/loop0", "/dev/sda"])

    def test_stick(self) -> None:
        stick = self.drives["/dev/sdb"]
        self.assertEqual((stick.name, stick.table, stick.removable, stick.in_use), ("Brand Stick", "gpt", True, ""))
        (photos,) = stick.partitions
        self.assertEqual((photos.volume.fs, photos.volume.label), ("exfat", "Photos"))
        self.assertEqual(photos.volume.mounts, ["/run/media/someone/Photos"])
        self.assertEqual(photos.in_use, "")

    def test_system_drive(self) -> None:
        ssd = self.drives["/dev/sda"]
        self.assertEqual(ssd.health, "Healthy · 35 °C")
        swap, root = ssd.partitions
        self.assertEqual(swap.in_use, "Swap in use")
        # The root filesystem is inside the LUKS volume
        self.assertEqual(root.in_use, "Used by the running system")
        self.assertIsNotNone(root.volume.inner)

    def test_loop_device_without_table(self) -> None:
        loop = self.drives["/dev/loop0"]
        self.assertEqual(loop.name, "Loop device test.img")
        self.assertEqual(loop.table, "")
        self.assertIsNotNone(loop.volume)
        self.assertNotIn("/dev/loop1", self.drives)

    def test_byte_strings(self) -> None:
        self.assertEqual(disk_objects.text(path_bytes("/run/media/a")), "/run/media/a")
        self.assertEqual(disk_objects.text("/dev/sdb"), "/dev/sdb")
        self.assertEqual(disk_objects.text(None), "")


if __name__ == "__main__":
    unittest.main()
