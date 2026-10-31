import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

// A menu above the dock card in its own popup surface, so the dock layer
// only needs to be as tall as the card.
//
// The surface keeps one fixed size for its whole life: the room above the
// dock (popupMaxHeight) by maxWidth. The menu (body) sits at its bottom,
// centred over centerX, and grows or shrinks inside it; the rest of the
// surface is transparent and outside the input mask. A popup that changed
// its surface size with its content (a folder being listed, another folder
// opened, the stack closing) showed the new size at the old position for a
// frame or two until the compositor repositioned it, flashing over the dock.
//
// Placement (onAnchoring, the pattern of Omarchy's Ui/PopupCard.qml): the
// anchor point is Style.space(6) above the card; the surface hangs above it,
// centred and clamped to the screen. No compositor adjustment, so
// toDockWindow() can rely on it.
PopupWindow {
  id: popup

  property var dockRoot: null
  property bool open: false
  property real centerX: 0
  property Item body: null
  // True while a text field inside the body is being edited: the popup then
  // has to hold the keyboard itself. Hyprland's focus grab gives the keyboard
  // to one of the grabbed surfaces, and with several listed the one it
  // happens to pick is arbitrary (hash order) — and when it picks the dock
  // window the keystrokes are dropped there, because the dock's layer surface
  // takes no keyboard. Dropping the dock window from the list while editing
  // leaves this popup's own surface as the only candidate.
  property bool holdsKeyboard: false
  // The popup's life (PopupLife, owned by the dock so it outlives this
  // window): it fades and rises in, and fades out showing its last frame.
  property var life: null
  readonly property real level: popup.life ? popup.life.level : 1
  readonly property bool closing: !!(popup.life && popup.life.closing)
  readonly property real rise: (popup.dockRoot && popup.dockRoot.motion.rise) ? Math.round((1 - popup.level) * Style.space(6)) : 0

  signal dismissed()

  readonly property var dockWindow: dockRoot ? dockRoot.dockWindowRef : null
  readonly property real gap: Style.space(6)
  readonly property real maxWidth: Style.space(900)

  // Surface centre in dock-window x, clamped so the surface stays on screen.
  readonly property real surfaceCenterX: {
    var w = popup.dockWindow ? popup.dockWindow.width : 1920
    var half = popup.implicitWidth / 2
    return Math.round(Math.max(Style.gapsOut + half, Math.min(w - Style.gapsOut - half, popup.centerX)))
  }

  color: "transparent"
  visible: open && body !== null
  implicitWidth: Math.ceil(Math.min(popup.maxWidth, popup.dockWindow ? popup.dockWindow.width - Style.gapsOut * 2 : popup.maxWidth))
  // Whole device pixels tall: at a fractional output scale a surface a
  // half pixel short lost the menu's bottom border row to the compositor's
  // rounding (at 1.5x, every menu of an odd height).
  implicitHeight: {
    var h = Math.ceil(popup.dockRoot ? popup.dockRoot.popupMaxHeight : 600)
    var s = popup.dockRoot ? popup.dockRoot.outputScale : 1
    for (var i = 0; i < 4 && s > 0 && Math.abs(h * s - Math.round(h * s)) > 1e-6; i++) h++
    return h
  }

  // Input only over the menu itself, and none while it fades out.
  mask: Region { item: popup.closing ? null : popup.body }

  // The body at the bottom of the surface, centred over centerX and kept
  // inside the surface (which may itself be clamped at a screen edge).
  Binding {
    target: popup.body
    property: "x"
    value: Math.round(Math.max(0, Math.min(popup.implicitWidth - (popup.body ? popup.body.width : 0),
      popup.centerX - (popup.surfaceCenterX - popup.implicitWidth / 2) - (popup.body ? popup.body.width : 0) / 2)))
  }
  Binding {
    target: popup.body
    property: "y"
    value: Math.round(popup.implicitHeight - (popup.body ? popup.body.height : 0)) + popup.rise
  }
  Binding {
    target: popup.contentItem
    property: "opacity"
    value: popup.level
  }

  // The body's last frame. It keeps rendering (almost transparent) while the
  // popup is open, because a hidden ShaderEffectSource stops updating; on
  // close it freezes and takes the body's place, since the body empties the
  // moment the popup's state clears.
  ShaderEffectSource {
    id: frozen
    parent: popup.contentItem
    sourceItem: popup.body
    live: !popup.closing
    // A body that has faded out (an app dragged out of it) stays gone.
    opacity: popup.closing ? (popup.body ? popup.body.opacity : 1) : 0.001
    property real lastX: 0
    property real lastY: 0
    property real lastW: 0
    property real lastH: 0
    x: frozen.lastX
    y: frozen.lastY + popup.rise
    width: frozen.lastW
    height: frozen.lastH
  }
  Binding { target: frozen; property: "lastX"; value: popup.body ? popup.body.x : 0; when: !popup.closing; restoreMode: Binding.RestoreNone }
  Binding { target: frozen; property: "lastY"; value: popup.body ? popup.body.y - popup.rise : 0; when: !popup.closing; restoreMode: Binding.RestoreNone }
  Binding { target: frozen; property: "lastW"; value: popup.body ? popup.body.width : 0; when: !popup.closing; restoreMode: Binding.RestoreNone }
  Binding { target: frozen; property: "lastH"; value: popup.body ? popup.body.height : 0; when: !popup.closing; restoreMode: Binding.RestoreNone }
  // The body sizes itself to 0 the moment its state clears, and a
  // ShaderEffectSource with an empty source draws nothing: while closing the
  // body keeps its last size, so the frozen frame has something to show.
  Binding { target: popup.body; property: "width"; value: frozen.lastW; when: popup.closing }
  Binding { target: popup.body; property: "height"; value: frozen.lastH; when: popup.closing }

  anchor.window: dockWindow
  anchor.rect.width: 1
  anchor.rect.height: 1
  anchor.edges: Edges.Top
  anchor.gravity: Edges.Top
  anchor.adjustment: PopupAdjustment.None
  anchor.onAnchoring: {
    if (!popup.dockWindow || !popup.dockRoot || !popup.dockRoot.dockCard) return
    var win = popup.dockWindow.contentItem
    var cardTop = win.mapFromItem(popup.dockRoot.dockCard, 0, 0).y
    popup.anchor.rect.x = popup.surfaceCenterX
    popup.anchor.rect.y = Math.round(cardTop - popup.gap)
  }

  // The surface only moves when it should sit over another item.
  onSurfaceCenterXChanged: if (popup.visible) popup.anchor.updateAnchor()

  // A point in an item hosted by this popup, in dock-window coordinates.
  function toDockWindow(item, x, y) {
    var p = item.mapToItem(popup.contentItem, x, y)
    return Qt.point(popup.surfaceCenterX - Math.round(popup.implicitWidth / 2) + p.x,
                    popup.anchor.rect.y - popup.implicitHeight + p.y)
  }

  // A point in dock-window coordinates, in this popup's content item.
  function fromDockWindow(x, y) {
    return Qt.point(x - (popup.surfaceCenterX - Math.round(popup.implicitWidth / 2)),
                    y - (popup.anchor.rect.y - popup.implicitHeight))
  }

  // Read-only, for the live suite: whether the compositor is routing the
  // keyboard to this popup right now (the grab is what makes an outside click
  // or focus change dismiss it).
  readonly property bool grabActive: focusGrab.active

  // A click outside the menu and the dock closes it, as the full-surface
  // dismiss area used to.
  HyprlandFocusGrab {
    id: focusGrab
    active: popup.visible && !popup.closing
    windows: (popup.dockWindow && !popup.holdsKeyboard) ? [popup, popup.dockWindow] : [popup]
    onCleared: popup.dismissed()
  }
}
