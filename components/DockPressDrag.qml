import QtQuick

// MouseArea for dock items that can also be dragged: a left-button move past
// a small threshold, in any direction, starts a drag, reported in the
// coordinates of mapTarget (the dock card). The click that ends a drag is
// swallowed, so dragging an item never also opens it; plain clicks arrive
// as tapped.
MouseArea {
  id: area

  property Item mapTarget: null
  property real threshold: 8
  readonly property bool dragging: area._dragging

  property bool _dragging: false
  property bool _swallowClick: false
  property real _startX: 0
  property real _startY: 0

  signal dragStarted()
  signal dragMoved(real x, real y)
  signal dragFinished()
  signal tapped(var mouse)

  function _finish() {
    if (!area._dragging) return
    area._dragging = false
    area._swallowClick = true
    area.dragFinished()
  }

  onPressed: function(mouse) {
    area._swallowClick = false
    if (mouse.button !== Qt.LeftButton) return
    area._startX = mouse.x
    area._startY = mouse.y
    area._dragging = false
  }

  onPositionChanged: function(mouse) {
    if (!area.pressed || !(mouse.buttons & Qt.LeftButton)) return
    if (!area._dragging && Math.abs(mouse.x - area._startX) + Math.abs(mouse.y - area._startY) > area.threshold) {
      area._dragging = true
      area.dragStarted()
    }
    if (area._dragging) {
      var p = area.mapTarget ? area.mapToItem(area.mapTarget, mouse.x, mouse.y) : Qt.point(mouse.x, mouse.y)
      area.dragMoved(p.x, p.y)
    }
  }

  onReleased: area._finish()
  onCanceled: area._finish()

  onClicked: function(mouse) {
    if (area._swallowClick) {
      area._swallowClick = false
      return
    }
    area.tapped(mouse)
  }
}
