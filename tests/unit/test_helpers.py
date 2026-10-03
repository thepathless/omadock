#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import mock_open, patch

ROOT = Path(__file__).resolve().parents[2]


def load_helper(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


popups = load_helper('notification-popups')
terminals = load_helper('terminal-hosts')
folders = load_helper('list-folder')


class PopupTests(unittest.TestCase):
    def test_bounded_regular_files_only(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            (base / 'valid.json').write_text(json.dumps({'app': 'Firefox', 'body': 'x' * 5000}))
            (base / 'large.json').write_bytes(b'x' * (popups.MAX_FILE_BYTES + 1))
            (base / 'invalid.json').write_text('{')
            (base / 'array.json').write_text('[]')
            (base / 'deep.json').write_text('[' * 1200 + '0' + ']' * 1200)
            (base / 'history').mkdir()
            (base / 'history' / 'old.json').write_text('{"app":"Old"}')
            (base / 'link.json').symlink_to(base / 'valid.json')
            os.mkfifo(base / 'fifo.json')
            rows = popups.snapshots(folder)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]['app'], 'Firefox')
            self.assertEqual(len(rows[0]['body']), 4096)
            self.assertEqual(set(rows[0]), {'app', 'appIcon', 'summary', 'body'})

    def test_timestamp_identifies_each_popup(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            (base / 'a.json').write_text(json.dumps({'app': 'A', 'timestamp': 1791036122238}))
            (base / 'b.json').write_text(json.dumps({'app': 'B', 'timestamp': '17'}))
            (base / 'c.json').write_text(json.dumps({'app': 'C', 'timestamp': True}))
            stamps = {row['app']: row.get('timestamp') for row in popups.snapshots(folder)}
            self.assertEqual(stamps, {'A': 1791036122238, 'B': None, 'C': None})

    def test_row_limit_and_missing_directory(self):
        self.assertEqual(popups.snapshots('/nonexistent/omadock-test'), [])
        with patch.dict(os.environ, {'HOME': '/tmp/home', 'XDG_STATE_HOME': '/tmp/ignored'}):
            self.assertEqual(popups.state_dir(), '/tmp/home/.local/state/omarchy/notifications')
        with patch.dict(os.environ, {}, clear=True), patch.object(popups.pwd, 'getpwuid',
                return_value=type('User', (), {'pw_dir': '/tmp/home'})()):
            self.assertEqual(popups.state_dir(), '/tmp/home/.local/state/omarchy/notifications')
        with tempfile.TemporaryDirectory() as folder:
            for i in range(popups.MAX_ROWS + 4):
                (Path(folder) / f'{i}.json').write_text('{"app":"Firefox"}')
            self.assertEqual(len(popups.snapshots(folder)), popups.MAX_ROWS)

    def read_until(self, process, expected):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            ready, _, _ = select.select([process.stdout], [], [], max(0, deadline - time.monotonic()))
            if ready:
                line = process.stdout.readline()
                self.assertTrue(line, process.stderr.read() if process.poll() is not None else 'watch exited')
                if json.loads(line) == expected:
                    return
        self.fail(f'watch did not emit {expected}')

    def test_watch_creation_replacement_removal_and_recreation(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder) / 'state' / 'notifications'
            process = subprocess.Popen([sys.executable, str(ROOT / 'scripts/notification-popups.py'), str(directory)],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
            try:
                self.read_until(process, [])
                directory.mkdir(parents=True)
                notice = directory / 'one.json'
                notice.write_text('{"app":"Firefox"}')
                row = {'app': 'Firefox', 'appIcon': '', 'summary': '', 'body': ''}
                self.read_until(process, [row])
                notice.write_text('{"app":"btop"}')
                self.read_until(process, [{**row, 'app': 'btop'}])
                notice.unlink()
                self.read_until(process, [])
                directory.rmdir()
                directory.mkdir()
                notice.write_text('{"app":"Firefox"}')
                self.read_until(process, [row])
                self.assertIsNone(process.poll())
            finally:
                process.terminate()
                process.communicate(timeout=3)


class TerminalTests(unittest.TestCase):
    def test_terminal_lookup_walks_a_bounded_parent_chain(self):
        with patch.object(terminals.os, 'readlink', return_value='/usr/bin/kitty'):
            self.assertEqual(terminals.process_identity(20)[0], 'kitty')
        stat_data = {'/proc/20/stat': '20 (bash) S 21 0'}
        def opened(path, *args, **kwargs):
            return mock_open(read_data=stat_data[path])()
        with patch.object(terminals.os, 'readlink', side_effect=['/usr/bin/bash', '/usr/bin/ghostty']), \
                patch.object(terminals, 'cli_app_below', return_value=''), \
                patch('builtins.open', side_effect=opened):
            self.assertEqual(terminals.process_identity(20), ('com.mitchellh.ghostty', ''))

    def test_missing_process_and_parent_cycles(self):
        with patch.object(terminals.os, 'readlink', side_effect=FileNotFoundError):
            self.assertEqual(terminals.process_identity(20), ('', ''))
        with patch.object(terminals.os, 'readlink', return_value='/usr/bin/bash'), \
                patch('builtins.open', mock_open(read_data='20 (bash) S 20 0')):
            self.assertEqual(terminals.process_identity(20), ('', ''))
        self.assertEqual(terminals.process_identity(None), ('', ''))

    def test_terminal_children_find_only_known_cli_basenames(self):
        comms = {10: 'ghostty', 11: 'bash', 12: 'btop'}
        with patch.object(terminals, 'child_pids', side_effect=lambda pid: {10: [11], 11: [12]}.get(pid, [])), \
                patch('builtins.open', side_effect=lambda path, *args, **kwargs:
                      mock_open(read_data=comms[int(path.split('/')[-2])])()):
            self.assertEqual(terminals.cli_app_below(10), 'btop')
        with patch.object(terminals, 'child_pids', side_effect=lambda pid: {10: [11]}.get(pid, [])), \
                patch('builtins.open', side_effect=lambda path, *args, **kwargs:
                      mock_open(read_data='unknown-tui')()):
            self.assertEqual(terminals.cli_app_below(10), '')

    def test_product_identity_from_live_btop_window(self):
        comms = {10: 'ghostty', 11: 'bash', 12: 'btop'}
        with patch.object(terminals.os, 'readlink', side_effect=['/usr/bin/ghostty', '/usr/bin/bash']):
            with patch.object(terminals, 'process_stat', return_value=('S', 10)):
                with patch.object(terminals, 'child_pids', side_effect=lambda pid: {10: [11], 11: [12]}.get(pid, [])):
                    with patch('builtins.open', side_effect=lambda path, *args, **kwargs:
                            mock_open(read_data=comms[int(path.split('/')[-2])])()):
                        self.assertEqual(terminals.process_identity(10), ('com.mitchellh.ghostty', 'btop'))


class FolderTests(unittest.TestCase):
    def test_natural_sort_unicode_digits_and_superscripts(self):
        self.assertEqual(folders.natural_key('²'), ['²'])
        self.assertEqual(folders.natural_key('١٢.txt'), ['', 12, '.txt'])
        self.assertLess(folders.natural_key('file2.txt'), folders.natural_key('file10.txt'))
        with tempfile.TemporaryDirectory() as folder:
            for name in ('²', 'file2.txt', 'file10.txt', '١٢.txt'):
                (Path(folder) / name).write_text('test')
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/list-folder.py'), folder, 'name'],
                                    capture_output=True, text=True, timeout=3, check=True)
            self.assertEqual(json.loads(result.stdout)['count'], 4)


class CappedReadTests(unittest.TestCase):
    def test_actual_qml_gate_handles_symlinks_ceiling_and_fifo(self):
        qml = (ROOT / 'components/CappedFileView.qml').read_text()
        lines = qml.split('readonly property string gateScript: [', 1)[1].split('].join', 1)[0]
        script = '\n'.join(line.strip()[1:-2] for line in lines.splitlines() if line.strip().startswith("'"))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'data'
            path.write_text('abcd')
            link = Path(folder) / 'link'
            link.symlink_to(path)
            fifo = Path(folder) / 'fifo'
            os.mkfifo(fifo)
            for target, cap, code, text in [(path, 4, 0, 'abcd'), (link, 4, 0, 'abcd'),
                                             (link, 3, 3, ''), (fifo, 4, 2, ''),
                                             (Path(folder) / 'missing', 4, 2, '')]:
                result = subprocess.run(['sh', '-c', script, 'test', str(target), str(cap)],
                                        capture_output=True, text=True, timeout=3)
                self.assertEqual((result.returncode, result.stdout), (code, text))


if __name__ == '__main__':
    unittest.main()
