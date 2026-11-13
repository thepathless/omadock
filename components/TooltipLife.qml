import QtQuick

// The life of one tooltip, shared by every tooltip in the dock.
// `want` is the caller's condition (hovered, dwell done, not blocked).
// The tooltip fades in when wanted, stays hideDelay ms after it no longer
// is, then fades out; `alive` keeps its popup window until the fade ends.
// While any tooltip is alive the dock is "warm" (dockRoot.tooltipsAlive),
// and callers skip the dwell, so moving from icon to icon cross-fades
// instead of making the user wait again.
Item {
  id: life

  property var dockRoot: null
  property bool want: false
  property int hideDelay: 200
  property int fadeMs: dockRoot ? dockRoot.motion.fast : 120
  // Whether the tooltip lifts as it fades in (Full only), for TooltipWindow.
  readonly property bool rises: dockRoot ? dockRoot.motion.rise : true

  property bool alive: false
  // 0 = hidden, 1 = shown; drives opacity and the small rise.
  property real level: 0
  Behavior on level { NumberAnimation { duration: life.fadeMs; easing.type: Easing.OutCubic } }

  width: 0
  height: 0

  readonly property bool warm: dockRoot ? dockRoot.tooltipsAlive > 0 : false

  onWantChanged: {
    if (life.want) {
      hold.stop()
      life.alive = true
      life.level = 1
    } else if (life.alive) {
      hold.restart()
    }
  }

  Timer {
    id: hold
    interval: life.hideDelay
    onTriggered: life.level = 0
  }

  onLevelChanged: if (life.level === 0 && !life.want) life.alive = false

  property bool _counted: false
  onAliveChanged: {
    if (!life.dockRoot) return
    if (life.alive && !life._counted) { life.dockRoot.tooltipsAlive++; life._counted = true }
    else if (!life.alive && life._counted) { life.dockRoot.tooltipsAlive--; life._counted = false }
  }
  Component.onDestruction: if (life._counted && life.dockRoot) life.dockRoot.tooltipsAlive--
}
