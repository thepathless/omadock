// Body for tests/live/autohide.sh (probe.sh's PROBE_BODY hook).
//
// Issue #75: a scrolling layout moves its columns in and out of the viewport
// without a Hyprland window event, so the dock's overlap snapshot can be taken
// mid-move and answer "no overlap" while the settled layout covers the dock.
// The dock must re-measure once after the motion settles, with no pointer visit
// and no further window event, and then hide on the fresh "overlap" answer.
//
// This body drives the same entry points the dock uses: the debounce timer a
// window event restarts (`autohide-arm`), the flag the snapshot writes
// (`autohide-overlap`) and the visible state the decision produces
// (`autohide-read`). No pointer and no new window are involved.
//
// Every step is gated on PROBE_SCREEN, the output the probe dock must be on:
// the suite pins the config copy to a fresh headless output, so all of this
// happens away from the owner's screen and no real window can overlap it.

  Od.DockHost { id: host }

  readonly property string mustBeOn: String(Quickshell.env("PROBE_SCREEN") || "")

  // The confirmation's own record: how often it fired after this arm, and
  // whether it armed another confirmation as its own run settled. Unrelated
  // Hyprland events restart the same overlap debounce, so a raw snapshot count
  // cannot answer "one-shot"; the timer's state can, sampled one event-loop
  // turn after `fired` is consumed - before any later event can arm a fresh
  // confirmation, and after the settle that would have re-armed it.
  property var dockRef: null
  readonly property var confirmTimer: dockRef ? dockRef.overlapConfirmTimer : null
  property int confirmsFired: 0
  property bool armedAfterConfirm: false

  Connections {
    target: confirmTimer
    function onFiredChanged() {
      if (confirmTimer && confirmTimer.fired) {
        confirmsFired += 1
      } else {
        Qt.callLater(function() {
          armedAfterConfirm = confirmTimer ? confirmTimer.armed : true
        })
      }
    }
  }

  function dock() {
    var list = host.orderedDocks ? host.orderedDocks() : []
    return list.length > 0 ? list[0] : null
  }

  function gate(d) {
    if (mustBeOn === "") return "PROBE_SCREEN is not set"
    if (!d) return "no dock"
    if (!d.dockScreen) return "the dock has no screen"
    if (String(d.dockScreen.name) !== mustBeOn) return "the dock is on " + d.dockScreen.name + ", not " + mustBeOn
    return ""
  }

  IpcHandler {
    id: ipc
    target: "omadock-test"

    function run(step: string): string {
      var d = dock()
      var why = gate(d)
      if (why !== "") return JSON.stringify({ ok: false, why: why })

      // The state a window event leaves behind: intelligent autohide on, the
      // dock visible, and one debounced snapshot about to run. The snapshot
      // sees an empty output, so it answers "no overlap" - the stale-looking
      // answer the confirmation must look at again.
      if (step === "autohide-arm") {
        d.autohide = true
        d.intelligentAutohide = true
        d.windowsOverlapDock = false
        d.dockVisible = true
        d.overlapConfirmTimer.cancel()
        dockRef = d
        confirmsFired = 0
        armedAfterConfirm = false
        d.debounceOverlapTimerRef.stop()
        d.debounceOverlapTimerRef.restart()
        return JSON.stringify({ ok: true, visible: d.dockVisible })
      }

      if (step === "autohide-state") {
        var c = d.overlapConfirmTimer
        return JSON.stringify({ ok: true, armed: c.armed, fired: c.fired,
          confirms: confirmsFired, armedAfterConfirm: armedAfterConfirm })
      }

      if (step === "autohide-read") {
        return JSON.stringify({ ok: true, visible: d.dockVisible,
          overlap: d.windowsOverlapDock })
      }

      // A fresh snapshot's "overlap" answer, driven the way the process writes
      // it; the hide path is the dock's own onWindowsOverlapDockChanged.
      if (step === "autohide-overlap") {
        d.windowsOverlapDock = true
        return JSON.stringify({ ok: true, visible: d.dockVisible })
      }

      return JSON.stringify({ ok: false, why: "unknown step " + step })
    }
  }
