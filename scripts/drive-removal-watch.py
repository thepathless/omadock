#!/usr/bin/env python3
"""Report drives pulled out while still mounted.

Prints one JSON object per line, {"dev": "/dev/sda1", "mountpoint": "..."},
when the kernel removes a block device that is mounted at that moment. A
drive ejected properly is unmounted first, so it is never reported.

Event driven, no polling: kernel block uevents come from `udevadm monitor
--kernel` (they arrive before udisks cleans up the mount of a pulled
drive), and the mount table is re-read only when /proc/self/mounts
signals a change (POLLPRI). When both are ready, the removal is handled
first, against the mount table as it was.
"""

import json
import os
import re
import select
import subprocess
import sys

MOUNTS = "/proc/self/mounts"
_REMOVE = re.compile(r"^KERNEL\[[0-9.]+\]\s+remove\s+(\S+)\s+\(block\)\s*$")
_OCTAL = re.compile(r"\\([0-7]{3})")


def removed_device(line):
    """/dev/<name> for a kernel 'remove' event of a block device, else ""."""
    m = _REMOVE.match(line.strip())
    if not m:
        return ""
    name = m.group(1).rstrip("/").rsplit("/", 1)[-1]
    return "/dev/" + name if re.fullmatch(r"[A-Za-z0-9._-]{1,64}", name) else ""


def mounted_devices(text):
    """{"/dev/x": mountpoint} for the /dev devices in a mounts table."""
    out = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 2 or not parts[0].startswith("/dev/"):
            continue
        out[parts[0]] = _OCTAL.sub(lambda m: chr(int(m.group(1), 8)), parts[1])
    return out


def unsafe_removal(dev, mounts):
    """The report for a removed device that is still mounted, else None."""
    if not dev or dev not in mounts:
        return None
    return {"dev": dev, "mountpoint": mounts[dev]}


def read_mounts():
    try:
        with open(MOUNTS) as f:
            return mounted_devices(f.read())
    except OSError:
        return {}


def main():
    try:
        monitor = subprocess.Popen(["udevadm", "monitor", "--kernel", "--subsystem-match=block"],
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
    except OSError as error:
        print(f"[omadock] drive removal watch unavailable: {error}", file=sys.stderr)
        return 1
    mounts_file = open(MOUNTS)
    mounts = mounted_devices(mounts_file.read())
    poller = select.poll()
    poller.register(monitor.stdout, select.POLLIN | select.POLLHUP)
    poller.register(mounts_file, select.POLLPRI | select.POLLERR)
    try:
        while True:
            ready = dict(poller.poll())
            if monitor.stdout.fileno() in ready:
                line = monitor.stdout.readline()
                if not line:
                    return 0
                report = unsafe_removal(removed_device(line), mounts)
                if report:
                    print(json.dumps(report), flush=True)
            if mounts_file.fileno() in ready:
                mounts_file.seek(0)
                mounts = mounted_devices(mounts_file.read())
    except KeyboardInterrupt:
        return 0
    finally:
        monitor.kill()


if __name__ == "__main__":
    sys.exit(main())
