import QtQuick
import Quickshell
import qs.Commons

// A tooltip above `target` in its own popup surface, so the dock layer does
// not need room for it. Display only: an empty mask lets the pointer through.
//
// The surface has one fixed size; the body sits at its bottom, centred over
// the target, and changes size inside it (a window preview arriving and
// taking the window's shape). A surface that resized with its content was
// shown at the old position for a frame, so the preview jumped.
// `level` (0..1, from TooltipLife) fades the body and, when `rises`
// (TooltipLife.rises: Full only), lifts it a little.
PopupWindow {
  id: tip

  property Item target: null
  property bool shown: false
  property Item body: null
  property real gap: Style.space(6)
  property real level: 1
  property bool rises: true

  readonly property var hostWindow: target ? target.QsWindow.window : null
  readonly property real maxWidth: Style.space(640)
  readonly property real maxHeight: Style.space(560)

  // Surface centre in host-window x, clamped so the surface stays on screen.
  property real surfaceCenterX: 0
  property real targetCenterX: 0

  // Re-place the popup over the target as it is now (the macOS callout is
  // anchored to the icon's drawn, magnified box, which moves while it grows).
  function refreshAnchor() { if (tip.visible) tip.anchor.updateAnchor() }

  color: "transparent"
  mask: Region {}
  visible: shown && hostWindow !== null && body !== null
  implicitWidth: Math.ceil(Math.min(tip.maxWidth, tip.hostWindow ? tip.hostWindow.width - Style.gapsOut * 2 : tip.maxWidth))
  implicitHeight: Math.ceil(tip.maxHeight)

  Binding {
    target: tip.body
    property: "x"
    value: Math.round(Math.max(0, Math.min(tip.implicitWidth - (tip.body ? tip.body.width : 0),
      tip.targetCenterX - (tip.surfaceCenterX - tip.implicitWidth / 2) - (tip.body ? tip.body.width : 0) / 2)))
  }
  Binding {
    target: tip.body
    property: "y"
    value: Math.round(tip.implicitHeight - (tip.body ? tip.body.height : 0) + (tip.rises ? (1 - tip.level) * Style.space(6) : 0))
  }
  Binding {
    target: tip.body
    property: "opacity"
    value: tip.level
  }

  anchor.window: hostWindow
  anchor.rect.width: 1
  anchor.rect.height: 1
  anchor.edges: Edges.Top
  anchor.gravity: Edges.Top
  anchor.adjustment: PopupAdjustment.None
  anchor.onAnchoring: {
    if (!tip.hostWindow || !tip.target) return
    var win = tip.hostWindow.contentItem
    var p = win.mapFromItem(tip.target, tip.target.width / 2, 0)
    var half = tip.implicitWidth / 2
    tip.targetCenterX = p.x
    tip.surfaceCenterX = Math.round(Math.max(Style.gapsOut + half, Math.min(win.width - Style.gapsOut - half, p.x)))
    tip.anchor.rect.x = tip.surfaceCenterX
    tip.anchor.rect.y = Math.round(p.y - tip.gap)
  }
}
