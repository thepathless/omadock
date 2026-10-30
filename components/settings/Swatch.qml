import QtQuick 6.11
import qs.Commons
import qs.Ui

// A colour swatch button for colour pickers.

Rectangle {
  id: swatch
  property bool selected: false
  signal picked()
  activeFocusOnTab: true
  Keys.onReturnPressed: swatch.picked()
  Keys.onSpacePressed: swatch.picked()

  width: Style.space(26)
  height: Style.space(26)
  radius: Math.min(Style.space(6), Style.cornerRadius > 0 ? Style.space(6) : 0)
  border.width: selected || activeFocus ? 2 : 1
  border.color: selected || activeFocus ? Color.accent : Util.alpha(Color.menu.text, 0.3)

  Rectangle {
    visible: swatch.selected
    anchors.centerIn: parent
    width: Style.space(8)
    height: width
    radius: width / 2
    color: Color.accent
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: swatch.picked()
  }
}
