import QtQuick

// One delayed re-measure of the dock's overlap after a "no overlap" snapshot.
//
// A window event triggers the 60 ms snapshot, but a scrolling layout moves its
// columns in and out of the viewport without emitting a window event: the
// snapshot can be taken mid-move and say "no overlap" while the settled layout
// covers the dock. Without a second look the dock stays visible until some
// unrelated event asks for another snapshot (#75).
//
// This is that second look. It is armed only after a "no overlap" answer,
// fires once, and never re-arms itself: the confirming run is marked by
// `fired` until DockStateLogic.settleOverlap consumes it, and a normal
// snapshot cancels it. Idle therefore costs nothing, and a stale answer gets
// one fresh measurement ~1.2 s later instead of a polling loop.
Item {
  id: confirmation
  visible: false

  // The dock root, which owns the debounce timer this restarts.
  property var dock: null
  // A confirmation is pending (`armed`) or its debounce run is the one that
  // must not schedule another (`fired`). A normal snapshot in the meantime
  // cancels it, so an event can never be mistaken for the second look.
  property bool armed: false
  property bool fired: false

  function arm() {
    armed = true
    fired = false
    timer.restart()
  }

  function cancel() {
    timer.stop()
    armed = false
    fired = false
  }

  Timer {
    id: timer
    interval: 1200
    repeat: false
    onTriggered: {
      if (!confirmation.dock) { confirmation.cancel(); return }
      if (!confirmation.dock.autohide || !confirmation.dock.intelligentAutohide) {
        confirmation.cancel()
        return
      }
      confirmation.fired = true
      confirmation.dock.debounceOverlapTimerRef.restart()
    }
  }
}
