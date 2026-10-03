#!/usr/bin/env python3
"""Read only Omarchy's active popup files, never history or a second D-Bus server."""
import ctypes
import json
import os
import pwd
import select
import stat
import struct
import sys

MAX_FILE_BYTES = 65536
MAX_TOTAL_BYTES = 2097152
MAX_ROWS = 128


def state_dir():
    # Match the notification service's stateDir exactly; it uses HOME/.local/state
    # even when XDG_STATE_HOME points elsewhere.
    home = os.environ.get('HOME') or pwd.getpwuid(os.getuid()).pw_dir
    return os.path.join(home, '.local', 'state', 'omarchy', 'notifications')


def snapshots(directory):
    rows = []
    budget = MAX_TOTAL_BYTES
    try:
        with os.scandir(directory) as entries:
            for index, entry in enumerate(entries):
                if index >= 1024 or len(rows) >= MAX_ROWS or budget <= 0:
                    break
                if not entry.name.endswith('.json'):
                    continue
                try:
                    fd = os.open(entry.path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
                    with os.fdopen(fd, 'rb') as stream:
                        info = os.fstat(stream.fileno())
                        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_FILE_BYTES:
                            continue
                        data = stream.read(min(MAX_FILE_BYTES + 1, budget + 1))
                    budget -= len(data)
                    if len(data) > MAX_FILE_BYTES or budget < 0:
                        continue
                    row = json.loads(data)
                    if not isinstance(row, dict):
                        continue
                    item = {key: row.get(key, '')[:4096] if isinstance(row.get(key, ''), str) else ''
                            for key in ('app', 'appIcon', 'summary', 'body')}
                    # The popup's timestamp tells a new notification from one
                    # already seen (urgency fires once per new popup). A row
                    # without a valid one carries no field at all, so it is
                    # never mistaken for a popup stamped 0.
                    stamp = row.get('timestamp')
                    if isinstance(stamp, int) and not isinstance(stamp, bool) and stamp > 0:
                        item['timestamp'] = stamp
                    rows.append(item)
                except (OSError, ValueError, RecursionError):
                    continue
    except OSError:
        pass
    return rows


def emit(directory):
    print(json.dumps(snapshots(directory)), flush=True)


def watch(directory):
    # Watch the popup directory and its closest existing ancestor. A fresh
    # install can start the dock before the notification service creates it.
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    fd = libc.inotify_init1(os.O_CLOEXEC | os.O_NONBLOCK)
    if fd < 0:
        raise OSError(ctypes.get_errno(), 'cannot watch notification popups')
    watches = {}
    mask = 0x00000FCC | 0x01000000  # create/close/rename/delete/attrib; ONLYDIR

    def reconcile():
        ancestor = os.path.dirname(directory)
        while not os.path.isdir(ancestor) and ancestor != os.path.dirname(ancestor):
            ancestor = os.path.dirname(ancestor)
        wanted = {ancestor}
        if os.path.isdir(directory):
            wanted.add(directory)
        for wd, path in list(watches.items()):
            if path not in wanted or not os.path.isdir(path):
                libc.inotify_rm_watch(fd, wd)
                del watches[wd]
        for path in wanted - set(watches.values()):
            wd = libc.inotify_add_watch(fd, os.fsencode(path), mask)
            if wd >= 0:
                watches[wd] = path
        if not watches:
            raise OSError('no notification directory watch available')

    try:
        reconcile()
        emit(directory)
        while True:
            select.select([fd], [], [])
            events = os.read(fd, 65536)
            offset = 0
            while offset + 16 <= len(events):
                wd, event_mask, _, name_len = struct.unpack_from('iIII', events, offset)
                offset += 16 + name_len
                if event_mask & 0x00008000:  # IN_IGNORED: deleted inode or removed watch
                    watches.pop(wd, None)
            reconcile()
            # Recompute from files even after queue overflow; never count events.
            emit(directory)
    finally:
        os.close(fd)


def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else state_dir()
    if '--once' in sys.argv:
        emit(directory)
        return
    # Blocking inotify reads consume no idle CPU, including before creation.
    try:
        watch(os.path.abspath(directory))
    except OSError as error:
        print(f'[omadock] Notification popup watch unavailable: {error}', file=sys.stderr)
        emit(directory)
        sys.exit(1)


if __name__ == '__main__':
    main()
