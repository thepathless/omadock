import QtQuick 6.11
import qs.Commons
import qs.Ui

Item {
  id: mdiv

  property color ink: Color.menu.border
  property real menuRowWidth: {
    var p = parent
    while (p) {
      if (p.rowWidth !== undefined) return p.rowWidth
      p = p.parent
    }
    return 0
  }
  readonly property bool isMenuContent: false
  implicitWidth: mdiv.menuRowWidth > 0 ? mdiv.menuRowWidth : Style.space(160)
  width: mdiv.menuRowWidth > 0 ? mdiv.menuRowWidth : implicitWidth
  implicitHeight: Math.max(7, Style.space(7))
  height: Math.max(7, Style.space(7))

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    height: 1
    color: Util.alpha(mdiv.ink, 0.45)
  }
}
