import QtQuick

// The life of one tooltip, shared by every tooltip in the dock.
// `want` is the caller's condition (hovered, dwell done, not blocked).
// The tooltip fades in when wanted, stays hideDelay ms after it no longer
// is, then fades out; `alive` keeps its popup window until the fade ends.
// A warm dock skips the dwell between icons. Each dock gives one tooltip
// ownership of its popup so previews cannot cover one another.
Item {
  id: life

  property var dockRoot: null
  property bool want: false
  property int hideDelay: 75
  property int fadeMs: dockRoot ? dockRoot.motion.fast : 120
  readonly property bool rises: false

  property bool alive: false
  // 0 = hidden, 1 = shown. Losing ownership resets the fade immediately.
  property real level: 0
  Behavior on level {
    enabled: life.alive
    NumberAnimation { duration: life.fadeMs; easing.type: Easing.OutCubic }
  }

  width: 0
  height: 0

  readonly property bool ownsTooltip: !dockRoot || dockRoot.tooltipOwner === life

  onOwnsTooltipChanged: {
    if (life.ownsTooltip) return
    enter.stop()
    hold.stop()
    life.alive = false
    life.level = 0
  }

  onWantChanged: {
    if (life.want) {
      hold.stop()
      if (life.dockRoot) life.dockRoot.tooltipOwner = life
      life.alive = true
      if (life.fadeMs > 0) enter.restart()
      else life.level = 1
    } else if (life.alive) {
      enter.stop()
      if (life.level === 0) life.alive = false
      else hold.restart()
    }
  }

  Timer {
    id: enter
    interval: 16
    onTriggered: life.level = 1
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
  Component.onDestruction: {
    if (life._counted && life.dockRoot) life.dockRoot.tooltipsAlive--
    if (life.dockRoot && life.dockRoot.tooltipOwner === life) life.dockRoot.tooltipOwner = null
  }
}
