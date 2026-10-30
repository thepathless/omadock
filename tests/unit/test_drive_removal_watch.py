"""scripts/drive-removal-watch.py: spotting a drive pulled while mounted."""
import importlib.util
import os
import pathlib
import shutil
import signal
import subprocess
import sys
import time
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


def children(pid):
    try:
        return [int(c) for c in pathlib.Path(f"/proc/{pid}/task/{pid}/children").read_text().split()]
    except OSError:
        return []


def wait_for(predicate, timeout=5.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


def alive(pid):
    try:
        return pathlib.Path(f"/proc/{pid}/stat").read_text().split(") ")[1][0] != "Z"
    except OSError:
        return False


@unittest.skipUnless(shutil.which("udevadm"), "udevadm not installed")
class Lifecycle(unittest.TestCase):
    def watcher_with_monitor(self):
        proc = subprocess.Popen([sys.executable, str(SCRIPTS / "drive-removal-watch.py")],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(proc.wait)
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        if not wait_for(lambda: children(proc.pid)):
            self.skipTest("udevadm monitor cannot run here")
        monitor = children(proc.pid)[0]
        self.addCleanup(lambda: alive(monitor) and os.kill(monitor, signal.SIGKILL))
        return proc, monitor

    def test_sigterm_reaps_udevadm(self):
        proc, monitor = self.watcher_with_monitor()
        proc.send_signal(signal.SIGTERM)
        self.assertEqual(proc.wait(timeout=5), 0)
        self.assertTrue(wait_for(lambda: not alive(monitor)), "udevadm outlived SIGTERM")

    def test_sigkill_still_takes_udevadm_down(self):
        proc, monitor = self.watcher_with_monitor()
        proc.kill()
        proc.wait(timeout=5)
        self.assertTrue(wait_for(lambda: not alive(monitor)), "udevadm outlived SIGKILL")


if __name__ == "__main__":
    unittest.main()
