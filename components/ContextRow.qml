import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: crow

  property string text: ""
  property string glyph: ""
  property bool checked: false
  property color textColor: Color.menu.text
  property bool danger: false
  property bool isHeader: false
  property bool isWindowRow: false
  property bool winFocused: false
  property bool winParked: false
  signal triggered()

  // Rows ask for what they need, then all get drawn at the menu's width, so
  // hover and checked fills line up down the menu instead of stepping in and
  // out with the length of each label.
  readonly property bool isMenuContent: true
  readonly property real markWidth: Style.space(14)

  property real menuRowWidth: {
    var p = parent
    while (p) {
      if (p.rowWidth !== undefined) return p.rowWidth
      p = p.parent
    }
    return 0
  }

  implicitWidth: Math.min(Style.space(260), Math.max(220, Style.space(8) + crow.markWidth + Style.space(6)
    + label.implicitWidth + Style.space(8)))
  width: crow.menuRowWidth > 0 ? crow.menuRowWidth : crow.implicitWidth
  height: crow.isHeader ? Math.max(22, Style.space(22)) : Math.max(28, Style.space(28))

  Rectangle {
    anchors.fill: parent
    visible: !crow.isHeader
    radius: Style.cornerRadius
    color: area.containsMouse
      ? (crow.danger ? Util.alpha(Color.urgent, 0.16) : Color.menu.selectedBackground)
      : (crow.checked ? Util.alpha(Color.bar.active, 0.12) : "transparent")
  }

  Row {
    id: content
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    // The mark column is always reserved, so labels stay on one left edge and
    // a row keeps its width when it gets checked.
    Item {
      id: markContainer
      width: crow.markWidth
      height: crow.markWidth
      anchors.verticalCenter: parent.verticalCenter

      // Window Dot (if isWindowRow)
      Rectangle {
        visible: crow.isWindowRow
        width: Style.space(6)
        height: Style.space(6)
        radius: width / 2
        anchors.centerIn: parent
        color: crow.winFocused
          ? Color.bar.active
          : (crow.winParked ? "transparent" : (crow.checked ? Color.bar.active : Util.alpha(Color.menu.text, 0.45)))
        border.color: crow.winFocused
          ? Color.bar.active
          : (crow.winParked ? Util.alpha(Color.menu.text, 0.4) : (crow.checked ? Color.bar.active : "transparent"))
        border.width: 1
      }

      // Standard Glyph / Checkmark (if not isWindowRow)
      Text {
        visible: !crow.isWindowRow
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        opacity: (crow.glyph !== "" || crow.checked) ? 1 : 0
        text: crow.glyph !== "" ? crow.glyph : "\ue92b"
        font.family: "omarchy"
        font.pixelSize: Style.font.caption
        color: crow.checked ? Color.bar.active : (crow.isHeader ? Util.alpha(Color.menu.text, 0.5) : crow.textColor)
      }
    }

    Text {
      id: label
      anchors.verticalCenter: parent.verticalCenter
      width: content.width - markContainer.width - content.spacing
      text: (crow.checked && crow.isWindowRow ? "› " : "") + crow.text
      textFormat: Text.PlainText
      color: crow.isHeader
        ? Util.alpha(Color.menu.text, 0.5)
        : (crow.checked || crow.winFocused
            ? Color.bar.active
            : (crow.winParked
                ? Util.alpha(Color.menu.text, 0.50)
                : (area.containsMouse && crow.danger ? Color.urgent : crow.textColor)))
      font.family: Style.font.family
      font.pixelSize: crow.isHeader ? Style.font.caption : Style.font.body
      font.weight: (crow.isHeader || crow.checked || crow.winFocused) ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    enabled: !crow.isHeader
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: crow.triggered()
  }
}
