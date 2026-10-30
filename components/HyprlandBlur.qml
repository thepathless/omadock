import Quickshell
import Quickshell.Io

// Reads the compositor's own blur switch, for the dock's blur override.
//
// Hyprland blurs layers through layer rules, but every one of them is gated by
// one global switch (decoration.blur:enabled) - so a dock whose look asks for
// blur behind it has to turn that switch on, and has to know the user's own
// value first to put it back when the look stops asking. That read is all this
// file does; the dock's state stays on the root.
//
// The read runs only when the blur path asks for it (request()), never on its
// own: a dock that never asks for blur never touches the setting.
Process {
  id: probe

  property var rootRef: null
  readonly property var root: rootRef

  // Did the read answer? Set on the root too, so the caller can wait for it.
  property bool answered: false

  running: false
  command: ["hyprctl", "getoption", "decoration:blur:enabled", "-j"]

  function request() {
    if (!running) running = true
  }

  stdout: StdioCollector {
    onStreamFinished: {
      var on = true
      try {
        var opt = JSON.parse(this.text)
        if (typeof opt.bool === "boolean") on = opt.bool
      } catch (e) {
        console.warn("[omadock] Failed to read decoration:blur:enabled:", e)
      }
      probe.answered = true
      if (probe.root) {
        probe.root.systemBlurEnabled = on
        probe.root._blurProbed = true
        probe.root.ensureHyprBlur(false)
      }
    }
  }
}
