# pyright: strict
import unittest

from helpers import load

disk_layout = load("config/quickshell/menus/disk_layout.py")
Drive = disk_layout.Drive
Partition = disk_layout.Partition
Volume = disk_layout.Volume
Step = disk_layout.Step
Capability = disk_layout.Capability

MIB = 1024**2
GIB = 1024**3
BLOCK = "/block/sdb"
FIRST = "/block/sdb1"
SECOND = "/block/sdb2"
CAPABILITIES = {
    "ext4": Capability(format=True, resize=disk_layout.RESIZE_OFFLINE_SHRINK | disk_layout.RESIZE_OFFLINE_GROW),
    "vfat": Capability(format=True, check=True, repair=True),
    "btrfs": Capability(format=False, utility="mkfs.btrfs"),
}


def ext4(label: str = "", mounts: list[str] | None = None) -> Volume:
    return Volume(usage="filesystem", fs="ext4", label=label, mounts=mounts or [])


def stick(*partitions: Partition, table: str = "gpt") -> Drive:
    """An 8 GiB USB stick"""
    return Drive(
        id="/drive/stick",
        block=BLOCK,
        device="/dev/sdb",
        name="Stick",
        size=8 * GIB,
        removable=True,
        table=table,
        partitions=list(partitions),
        can_power_off=True,
    )


def partition(path: str, number: int, offset: int, size: int, volume: Volume | None = None) -> Partition:
    return Partition(id=path, number=number, offset=offset, size=size, volume=volume or ext4())


def plan(drive: Drive, *steps: Step) -> tuple[Drive, list[str]]:
    result = disk_layout.simulate(drive, list(steps), CAPABILITIES)
    return result.drive, result.problems


class Sizes(unittest.TestCase):
    def test_alignment(self) -> None:
        self.assertEqual(disk_layout.align_up(1), MIB)
        self.assertEqual(disk_layout.align_up(MIB), MIB)
        self.assertEqual(disk_layout.align_down(2 * MIB - 1), MIB)

    def test_size_text_is_decimal(self) -> None:
        self.assertEqual(disk_layout.size_text(64 * 10**9), "64.0 GB")
        self.assertEqual(disk_layout.size_text(512 * 10**9), "512 GB")
        self.assertEqual(disk_layout.size_text(1_500_000), "1.5 MB")
        self.assertEqual(disk_layout.size_text(12), "12 B")


class FreeSpace(unittest.TestCase):
    def test_empty_table_is_free_after_the_header(self) -> None:
        regions = disk_layout.free_regions(stick())
        self.assertEqual(len(regions), 1)
        self.assertEqual(regions[0].offset, MIB)
        # GPT keeps its copy at the end
        self.assertEqual(regions[0].offset + regions[0].size, 8 * GIB - MIB)

    def test_gaps_between_partitions(self) -> None:
        drive = stick(partition(FIRST, 1, MIB, GIB), partition(SECOND, 2, 3 * GIB, GIB))
        regions = [(r.offset, r.size) for r in disk_layout.free_regions(drive)]
        self.assertEqual(regions, [(MIB + GIB, 2 * GIB - MIB), (4 * GIB, 4 * GIB - MIB)])

    def test_alignment_leftovers_are_no_free_space(self) -> None:
        drive = stick(partition(FIRST, 1, MIB, GIB), partition(SECOND, 2, MIB + GIB + MIB, 8 * GIB - GIB - 4 * MIB))
        self.assertEqual(disk_layout.free_regions(drive), [])

    def test_no_table_no_free_space(self) -> None:
        self.assertEqual(disk_layout.free_regions(stick(table="")), [])


class Planning(unittest.TestCase):
    def test_new_table_and_partition(self) -> None:
        drive = stick(partition(FIRST, 1, MIB, GIB))
        table = Step("table", type="dos")
        create = Step("create", offset=MIB, size=2 * GIB, fs="ext4", label="Data")
        planned, problems = plan(drive, table, create)
        self.assertEqual(problems, ["", ""])
        self.assertEqual(planned.table, "dos")
        self.assertEqual(len(planned.partitions), 1)
        created = planned.partitions[0]
        self.assertEqual((created.id, created.number, created.size), ("new1", 1, 2 * GIB))
        self.assertTrue(created.planned)
        # The plan leaves the drive itself alone
        self.assertEqual(drive.table, "gpt")

    def test_partition_must_fit_into_free_space(self) -> None:
        drive = stick(partition(FIRST, 1, MIB, GIB))
        _planned, problems = plan(drive, Step("create", offset=MIB, size=GIB, fs="ext4"))
        self.assertEqual(problems, ["The partition doesn't fit into the free space"])

    def test_new_partition_takes_the_lowest_free_number(self) -> None:
        drive = stick(partition(SECOND, 2, GIB, GIB))
        planned, _problems = plan(drive, Step("create", offset=3 * GIB, size=GIB, fs="ext4"))
        self.assertEqual([p.number for p in planned.partitions], [2, 1])

    def test_mbr_holds_four_partitions(self) -> None:
        drive = stick(table="dos")
        creates = [Step("create", offset=(i + 1) * GIB, size=GIB, fs="ext4") for i in range(5)]
        _planned, problems = plan(drive, *creates)
        self.assertEqual(problems[:4], ["", "", "", ""])
        self.assertEqual(problems[4], "An MBR partition table holds at most four partitions")

    def test_filesystem_must_be_installed(self) -> None:
        _planned, problems = plan(stick(), Step("create", offset=MIB, size=GIB, fs="btrfs"))
        self.assertEqual(problems, ["Formatting btrfs needs mkfs.btrfs installed"])

    def test_label_length_by_filesystem(self) -> None:
        drive = stick(partition(FIRST, 1, MIB, GIB))
        _planned, problems = plan(drive, Step("format", FIRST, fs="vfat", label="MUCH TOO LONG"))
        self.assertEqual(problems, ["A FAT label has at most 11 characters"])

    def test_mounted_partition_needs_unmounting_first(self) -> None:
        drive = stick(partition(FIRST, 1, MIB, GIB, ext4(mounts=["/run/media/stick"])))
        _planned, problems = plan(drive, Step("delete", FIRST))
        self.assertEqual(problems, ["sdb1 (1.1 GB, ext4) is mounted"])

    def test_system_partition_stays(self) -> None:
        system = partition(FIRST, 1, MIB, GIB, ext4(mounts=["/"]))
        system.in_use = "Used by the running system"
        _planned, problems = plan(stick(system), Step("format", FIRST, fs="ext4"))
        self.assertEqual(problems, ["Used by the running system"])

    def test_steps_on_a_planned_partition(self) -> None:
        create = Step("create", offset=MIB, size=GIB, fs="ext4")
        planned, problems = plan(stick(), create, Step("label", "new0", value="Data"))
        self.assertEqual(problems, ["", ""])
        self.assertEqual(planned.partitions[0].volume.label, "Data")

    def test_deleted_partition_is_gone_for_later_steps(self) -> None:
        drive = stick(partition(FIRST, 1, MIB, GIB))
        _planned, problems = plan(drive, Step("delete", FIRST), Step("format", FIRST, fs="ext4"))
        self.assertEqual(problems, ["", "The partition is gone"])

    def test_growing_needs_free_space_after(self) -> None:
        drive = stick(partition(FIRST, 1, MIB, GIB), partition(SECOND, 2, MIB + 2 * GIB, GIB))
        planned, problems = plan(drive, Step("resize", FIRST, size=2 * GIB))
        self.assertEqual(problems, [""])
        self.assertEqual(planned.partitions[0].size, 2 * GIB)
        _planned, problems = plan(drive, Step("resize", FIRST, size=3 * GIB))
        self.assertEqual(problems, ["There's not enough free space after the partition"])

    def test_resizing_follows_the_filesystem(self) -> None:
        drive = stick(partition(FIRST, 1, MIB, GIB, Volume(usage="filesystem", fs="vfat")))
        _planned, problems = plan(drive, Step("resize", FIRST, size=GIB // 2))
        self.assertEqual(problems, ["FAT can't be resized like this"])

    def test_nothing_after_an_image(self) -> None:
        image = Step("restore", image="/images/os.img", image_size=GIB)
        _planned, problems = plan(stick(), image, Step("create", offset=MIB, size=GIB, fs="ext4"))
        self.assertEqual(problems, ["", "After writing the image, the drive's layout isn't known yet"])

    def test_image_must_fit(self) -> None:
        _planned, problems = plan(stick(), Step("restore", image="/images/big.img", image_size=9 * GIB))
        self.assertEqual(problems, ["The image (9.7 GB) is bigger than the drive"])

    def test_nothing_after_powering_off(self) -> None:
        _planned, problems = plan(stick(), Step("poweroff"), Step("table", type="gpt"))
        self.assertEqual(problems, ["", "The drive is powered off by then"])

    def test_unlock_and_lock(self) -> None:
        locked = partition(FIRST, 1, MIB, GIB, Volume(usage="crypto", fs="crypto_LUKS"))
        planned, problems = plan(stick(locked), Step("unlock", FIRST, passphrase="secret"), Step("mount", FIRST))
        self.assertEqual(problems, ["", ""])
        inner = planned.partitions[0].volume.inner
        self.assertIsNotNone(inner)
        _planned, problems = plan(stick(locked), Step("lock", FIRST))
        self.assertEqual(problems, ["sdb1 (1.1 GB, LUKS, locked) is locked"])


class Prerequisites(unittest.TestCase):
    def test_unmount_and_lock_before_formatting(self) -> None:
        unlocked = Volume(usage="crypto", fs="crypto_LUKS", inner=ext4(mounts=["/run/media/data"]))
        drive = stick(partition(FIRST, 1, MIB, GIB, unlocked))
        steps = disk_layout.with_step(drive, [], Step("format", FIRST, fs="ext4"), CAPABILITIES)
        self.assertEqual([(s.op, s.auto) for s in steps], [("unmount", True), ("lock", True), ("format", False)])
        _planned, problems = plan(drive, *steps)
        self.assertEqual(problems, ["", "", ""])

    def test_whole_drive_is_released_for_a_new_table(self) -> None:
        drive = stick(
            partition(FIRST, 1, MIB, GIB, ext4(mounts=["/run/media/a"])),
            partition(SECOND, 2, 2 * GIB, GIB, ext4(mounts=["/run/media/b"])),
        )
        steps = disk_layout.with_step(drive, [], Step("table", type="gpt"), CAPABILITIES)
        self.assertEqual([(s.op, s.target) for s in steps], [("unmount", FIRST), ("unmount", SECOND), ("table", "")])

    def test_nothing_unmounted_that_the_system_uses(self) -> None:
        system = partition(FIRST, 1, MIB, GIB, ext4(mounts=["/"]))
        system.in_use = "Used by the running system"
        steps = disk_layout.with_step(stick(system), [], Step("delete", FIRST), CAPABILITIES)
        self.assertEqual([s.op for s in steps], ["delete"])

    def test_labelling_needs_no_unmount(self) -> None:
        drive = stick(partition(FIRST, 1, MIB, GIB, ext4(mounts=["/run/media/a"])))
        steps = disk_layout.with_step(drive, [], Step("label", FIRST, value="New"), CAPABILITIES)
        self.assertEqual([s.op for s in steps], ["label"])


class View(unittest.TestCase):
    def test_locked_partition_offers_nothing(self) -> None:
        system = partition(FIRST, 1, MIB, GIB, ext4(mounts=["/"]))
        system.in_use = "Used by the running system"
        drive = stick(system)
        self.assertEqual(disk_layout.partition_actions(drive, system, CAPABILITIES), [])
        self.assertEqual(disk_layout.drive_actions(drive), [])

    def test_segments_in_order(self) -> None:
        drive = stick(partition(SECOND, 2, 3 * GIB, GIB), partition(FIRST, 1, MIB, GIB))
        segments = disk_layout.segments(drive, CAPABILITIES)
        kinds = [(segment["kind"], segment["title"]) for segment in segments]
        expected = [
            ("partition", "sdb1"),
            ("free", "Free space"),
            ("partition", "sdb2"),
            ("free", "Free space"),
        ]
        self.assertEqual(kinds, expected)

    def test_partition_names_by_device(self) -> None:
        nvme = stick()
        nvme.device = "/dev/nvme0n1"
        self.assertEqual(disk_layout.partition_device(nvme, 3), "nvme0n1p3")
        self.assertEqual(disk_layout.partition_device(stick(), 3), "sdb3")

    def test_revision_ignores_health(self) -> None:
        drive = stick()
        warm = stick()
        warm.health = "Healthy · 40 °C"
        self.assertEqual(disk_layout.revision(drive), disk_layout.revision(warm))
        mounted = stick(partition(FIRST, 1, MIB, GIB, ext4(mounts=["/run/media/a"])))
        self.assertNotEqual(disk_layout.revision(drive), disk_layout.revision(mounted))

    def test_step_from_json_skips_wrong_types(self) -> None:
        step = disk_layout.step_from_json({"op": "resize", "target": FIRST, "size": "big", "auto": True})
        self.assertEqual((step.op, step.target, step.size, step.auto), ("resize", FIRST, 0, True))


if __name__ == "__main__":
    unittest.main()
