"""The app grid draws through the dock's icon index, not the library's own.

Runs the shipped AppGridHost offscreen against a fixture AppLibrary/AppGrid and
a fixture dock. No live shell, settings, compositor or launcher is touched.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
QS = shutil.which('qs')


@unittest.skipUnless(QS, 'requires Quickshell')
class AppGridIcons(unittest.TestCase):
    def test_grid_library_takes_the_dock_index_and_keeps_it_after_a_rescan(self):
        with tempfile.TemporaryDirectory(prefix='omadock-grid-icons-') as tmp:
            tmp = Path(tmp)
            home = tmp / 'home'
            home.mkdir()
            native = tmp / 'native'
            (native / 'shell/plugins/dock').mkdir(parents=True)
            (native / 'shell/services').mkdir(parents=True)
            # Omarchy's library keeps the first file per name: here a 16px PNG.
            (native / 'shell/services/AppLibrary.qml').write_text('''import QtQuick
import Quickshell.Io
Item {
  property var iconIndex: ({ steam: "/hicolor/16x16/apps/steam.png" })
  IpcHandler {
    target: "fixture-library"
    function steam(): string { return iconIndex.steam || "" }
    function rescan(): void { iconIndex = ({ steam: "/hicolor/16x16/apps/steam.png" }) }
  }
}
''')
            (native / 'shell/plugins/dock/AppGrid.qml').write_text('''import QtQuick
Item {
  property var appLibrary
  property var dock
  function open() {}
  function toggle() {}
}
''')
            (tmp / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import %s as Components
ShellRoot {
  QtObject {
    id: dockFixture
    property QtObject iconThemeRef: QtObject { property var iconIndex: ({}) }
  }
  Components.AppGridHost { id: appGridHost; omarchyPath: %s; docks: function() { return [dockFixture] } }
  IpcHandler {
    target: "fixture-control"
    function available(): bool { return appGridHost.available }
    function open(): void { appGridHost.openGrid() }
    function dockIndexed(): void {
      dockFixture.iconThemeRef.iconIndex = ({ steam: "/hicolor/256x256/apps/steam.png" })
    }
    function themeChanged(): void {
      dockFixture.iconThemeRef.iconIndex = ({ steam: "/Yaru/256x256/apps/steam.png" })
    }
  }
}
''' % (json.dumps((ROOT / 'components').as_uri()), json.dumps(str(native))))
            env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / 'state'),
                       QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
                       QT_QUICK_CONTROLS_STYLE='Basic', QS_DISABLE_FILE_WATCHER='1')
            env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            with (tmp / 'shell.log').open('w') as log:
                process = subprocess.Popen([QS, '-p', str(tmp)], env=env, stdout=log,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    def call(target, method):
                        return subprocess.run([QS, '-p', str(tmp), 'ipc', 'call', target, method],
                                              env=env, text=True, capture_output=True, timeout=3)

                    def wait(predicate):
                        until = time.monotonic() + 5
                        while time.monotonic() < until:
                            if predicate():
                                return
                            if process.poll() is not None:
                                break
                            time.sleep(0.05)
                        self.fail('condition failed:\n' + (tmp / 'shell.log').read_text())

                    def steam():
                        return call('fixture-library', 'steam').stdout.strip()

                    wait(lambda: call('fixture-control', 'available').stdout.strip() == 'true')
                    # A dock that has not indexed yet must not blank the grid.
                    call('fixture-control', 'open')
                    wait(lambda: steam() == '/hicolor/16x16/apps/steam.png')
                    # The dock finishes indexing while the grid is loaded: no reopen needed.
                    call('fixture-control', 'dockIndexed')
                    wait(lambda: steam() == '/hicolor/256x256/apps/steam.png')
                    # A new dock index (an icon-theme change) reaches the loaded grid too.
                    call('fixture-control', 'themeChanged')
                    wait(lambda: steam() == '/Yaru/256x256/apps/steam.png')
                    # The library rescans on every grid open; the dock's choice survives it.
                    call('fixture-library', 'rescan')
                    wait(lambda: steam() == '/Yaru/256x256/apps/steam.png')
                    self.assertNotRegex((tmp / 'shell.log').read_text(),
                                        r'TypeError|ReferenceError|is not a function')
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGTERM)
                        process.wait(timeout=5)


if __name__ == '__main__':
    unittest.main()
