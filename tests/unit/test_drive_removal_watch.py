"""scripts/drive-removal-watch.py: spotting a drive pulled while mounted."""
import importlib.util
import pathlib
import sys
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("drive_removal_watch", SCRIPTS / "drive-removal-watch.py")
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)

MOUNTS = """/dev/nvme0n1p2 / ext4 rw,relatime 0 0
/dev/sda1 /run/media/u/UPDATE vfat rw,nosuid,nodev 0 0
/dev/sdb1 /run/media/u/My\\040Disk exfat rw 0 0
tmpfs /tmp tmpfs rw 0 0
"""


class Parse(unittest.TestCase):
    def test_removed_device_from_kernel_event(self):
        line = "KERNEL[12345.678901] remove   /devices/pci0000:00/0000:00:14.0/usb2/2-1/2-1:1.0/host6/target6:0:0/6:0:0:0/block/sda/sda1 (block)"
        self.assertEqual(watch.removed_device(line), "/dev/sda1")

    def test_other_events_are_ignored(self):
        self.assertEqual(watch.removed_device("KERNEL[1.0] add      /devices/x/block/sda/sda1 (block)"), "")
        self.assertEqual(watch.removed_device("KERNEL[1.0] change   /devices/x/block/sda (block)"), "")
        self.assertEqual(watch.removed_device("monitor will print the received events for:"), "")
        self.assertEqual(watch.removed_device(""), "")

    def test_mounted_devices(self):
        mounts = watch.mounted_devices(MOUNTS)
        self.assertEqual(mounts["/dev/sda1"], "/run/media/u/UPDATE")
        self.assertEqual(mounts["/dev/sdb1"], "/run/media/u/My Disk")
        self.assertNotIn("tmpfs", mounts)


class Decide(unittest.TestCase):
    def test_pulled_while_mounted_is_unsafe(self):
        mounts = watch.mounted_devices(MOUNTS)
        self.assertEqual(watch.unsafe_removal("/dev/sda1", mounts),
                         {"dev": "/dev/sda1", "mountpoint": "/run/media/u/UPDATE"})

    def test_unmounted_first_is_safe(self):
        self.assertIsNone(watch.unsafe_removal("/dev/sdc1", watch.mounted_devices(MOUNTS)))
        self.assertIsNone(watch.unsafe_removal("", watch.mounted_devices(MOUNTS)))


if __name__ == "__main__":
    unittest.main()
