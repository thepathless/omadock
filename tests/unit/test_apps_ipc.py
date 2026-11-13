"""Exercise the shipped IPC handler and AppGridHost without desktop surfaces.

The tiny native-grid fixture implements only its public loader contract. The
actual IPC routing, lazy load, button-mode separation and fallback are production
QML. No live shell, settings, compositor or launcher is touched.
"""
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
QS = shutil.which('qs')


@unittest.skipUnless(QS, 'requires Quickshell for the IPC boundary')
class AppsIpc(unittest.TestCase):
    def test_apps_toggles_grid_independently_of_button_mode_and_falls_back(self):
        with tempfile.TemporaryDirectory(prefix='omadock-apps-ipc-') as tmp:
            tmp = Path(tmp)
            home = tmp / 'home'
            home.mkdir()
            native = tmp / 'native'
            grid = native / 'shell/plugins/dock'
            library = native / 'shell/services'
            grid.mkdir(parents=True)
            library.mkdir(parents=True)
            (library / 'AppLibrary.qml').write_text('import QtQuick\nItem {}\n')
            (grid / 'AppGrid.qml').write_text('''import QtQuick
import Quickshell.Io
Item {
  property var appLibrary
  property var dock
  property bool opened: false
  function open() { opened = true }
  function toggle() { opened = !opened }
  IpcHandler { target: "fixture-grid"; function isOpen(): bool { return opened } }
}
''')
            shim = tmp / 'bin'
            shim.mkdir()
            menu = shim / 'omarchy-menu'
            menu.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$HOME/menu-invocations"\n')
            menu.chmod(0o755)
            # Run the real handler as a unit. Creating the full DockHost would
            # create PanelWindows and require a compositor, even when hidden.
            source = (ROOT / 'DockHost.qml').read_text()
            handler = re.search(r'^  IpcHandler \{\n.*?^  \}', source, re.M | re.S).group()
            (tmp / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import %s as Components
ShellRoot {
  Components.AppGridHost { id: appGridHost; omarchyPath: %s }
  IpcHandler {
    target: "fixture-control"
    function available(): bool { return appGridHost.available }
    function mode(value: string): void { appGridHost.mode = value }
    function missing(): void { appGridHost.omarchyPath = %s }
  }
%s
}
''' % (json.dumps((ROOT / 'components').as_uri()), json.dumps(str(native)), json.dumps(str(tmp / 'missing')), handler))
            env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / 'state'),
                       QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
                       QT_QUICK_CONTROLS_STYLE='Basic', QS_DISABLE_FILE_WATCHER='1',
                       PATH=str(shim) + os.pathsep + os.environ['PATH'])
            env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            with (tmp / 'shell.log').open('w') as log:
                process = subprocess.Popen([QS, '-p', str(tmp)], env=env, stdout=log,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    def call(target, method, *args):
                        return subprocess.run([QS, '-p', str(tmp), 'ipc', 'call', target, method, *args],
                                              env=env, text=True, capture_output=True, timeout=3)

                    def wait(predicate):
                        until = time.monotonic() + 5
                        while time.monotonic() < until:
                            if predicate():
                                return
                            if process.poll() is not None:
                                break
                            time.sleep(0.05)
                        self.fail('IPC condition failed:\n' + (tmp / 'shell.log').read_text())

                    wait(lambda: call('fixture-control', 'available').stdout.strip() == 'true')
                    listing = subprocess.run([QS, '-p', str(tmp), 'ipc', 'show'], env=env, text=True,
                                             capture_output=True, check=True, timeout=3).stdout
                    self.assertNotIn('target omarchy.dock\n', listing)
                    for mode, opened in [('menu', 'true'), ('start', 'false'), ('grid', 'true')]:
                        self.assertEqual(call('fixture-control', 'mode', mode).returncode, 0)
                        result = call('omadock', 'apps')
                        self.assertEqual(result.returncode, 0, result.stderr)
                        wait(lambda: call('fixture-grid', 'isOpen').stdout.strip() == opened)
                    self.assertFalse((home / 'menu-invocations').exists())
                    call('fixture-control', 'missing')
                    wait(lambda: call('fixture-control', 'available').stdout.strip() == 'false')
                    self.assertEqual(call('omadock', 'apps').returncode, 0)
                    wait(lambda: (home / 'menu-invocations').exists())
                    self.assertEqual((home / 'menu-invocations').read_text().strip(), 'toggle root')
                    self.assertNotRegex((tmp / 'shell.log').read_text(), r'TypeError|ReferenceError|is not a function')
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGTERM)
                        process.wait(timeout=5)
