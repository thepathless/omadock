import QtQuick
import Quickshell.Io

// Capped, regular-file-gated replacement for FileView on watched mutable files.
//
// Why this exists: Quickshell's FileView loads a file's entire contents into
// shell memory at the read boundary (it allocates a buffer of file.size() and
// reads into it) before any QML can inspect the bytes. A hostile large file
// can therefore bloat the long-lived shell, and a non-regular file (FIFO)
// swapped in at the path can stall a reader — a post-hoc byte ceiling like
// DockModel.readCapped(FileView.text()) is applied too late. The cap has to
// apply BEFORE the file is loaded into QML.
//
// Mechanism: FileView here is a change *watcher* only (preload: false and no
// reload()/text()/data() call ever, so it never loads content). Content enters
// QML exclusively through the gate below — a one-shot process that first
// verifies the path is a readable regular file whose stat()d size is within
// maxBytes, and only then emits bytes, bounded by the pre-validated size (so
// even a file swapped mid-read cannot emit more). The reader is additionally
// bounded in time (timeout), so a FIFO swapped past the stat check can never
// hold a worker.
//
// Behavior parity with the old FileView path:
//   - missing / non-regular / unreadable -> nothing happens (FileView's
//     loadFailed also left state untouched and never fired onLoaded)
//   - oversized regular file -> text becomes "" and loaded() fires (matches
//     DockModel.readCapped, which yields "" for over-cap input)
//   - small regular file -> text = contents, loaded() fires
//
// Writes never read the file (FileView.setText writes exactly what it is
// given), so they stay on the internal FileView: setText() passes through.
Item {
  id: root

  property string path: ""
  property int maxBytes: 65536
  property bool watchChanges: true
  property bool atomicWrites: true

  // Last accepted file content ("" for empty, oversized, or never-loaded).
  property string text: ""

  signal loaded()
  signal fileChanged()

  // One-shot gated read. Safe to call at any time: a superseded in-flight
  // read is terminated and re-queued. It is asynchronous: text is still the
  // previous content when reload() returns, so read it from onLoaded only.
  function reload() {
    if (!root.path) return
    gate.running = false
    gate.running = true
  }

  // The file now holds exactly content, so text follows it at once; a caller
  // merging into text (saveConfig) must not see the content from before.
  function setText(content) {
    watcher.setText(content)
    root.text = content
  }

  Component.onCompleted: root.reload()

  // Watcher only — see header. printErrors stays off: a missing watched file
  // is a normal desktop state (e.g. theme files), not a shell error.
  FileView {
    id: watcher
    path: root.path
    preload: false
    watchChanges: root.watchChanges
    atomicWrites: root.atomicWrites
    printErrors: false
    onFileChanged: root.fileChanged()
  }

  // $1 = path, $2 = byte ceiling. Exit 0 = content on stdout (<= $2 bytes),
  // 2 = missing / non-regular / unreadable, 3 = oversized (parity: empty).
  readonly property string gateScript: [
    '[ -f "$1" ] && [ -r "$1" ] || exit 2',
    's=$(stat -c %s -- "$1" 2>/dev/null) || exit 2',
    '[ "$s" -le "$2" ] || exit 3',
    'timeout 2 head -c "$s" -- "$1"',
  ].join("\n")

  Process {
    id: gate
    command: ["sh", "-c", root.gateScript, "omadock-capped-read", root.path, String(root.maxBytes)]
    stdout: StdioCollector {
      id: gateOut
      waitForEnd: true
    }

    // Process flushes the stdout collector (streamEnded) before emitting
    // exited, so gateOut.text is complete here.
    onExited: (exitCode, exitStatus) => {
      if (exitCode === 0) {
        root.text = gateOut.text
        root.loaded()
      } else if (exitCode === 3) {
        root.text = ""
        root.loaded()
      }
      // Anything else (exit 2 / reader killed by timeout / crash) leaves
      // state untouched, matching FileView's loadFailed behavior.
    }
  }
}
