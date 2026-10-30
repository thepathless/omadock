import QtQuick 6.11
import qs.Commons

// Windows 11's taskbar feedback: a rounded wash under the button, not a
// magnified icon. The item that owns the pointer places it behind its art and
// sizes it to the button; the plate itself is the one owner of the look.
Rectangle {
  id: plate

  property var rootRef: null
  readonly property var root: rootRef
  property bool shown: false

  readonly property bool active: plate.shown && !!plate.root && plate.root.hoverEffect === "highlight"
  visible: plate.active
  color: Util.alpha(plate.root ? plate.root.dockForeground : "#f2efec", 0.08)
  radius: Style.space(4)
  z: -1
}
