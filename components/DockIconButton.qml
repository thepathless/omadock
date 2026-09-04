import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Item {
  id: btn

  property var rootRef: null
  readonly property var root: rootRef
  property var dockCard: root ? root.dockCard : null

  property string glyph: ""
  property string tooltip: ""
  property color glyphColor: root ? root.dockForeground : Color.bar.text
  property real glyphSize: root ? root.iconSize * 0.42 : 16
  signal pressed()
  signal middleClicked()
  signal wheelScrolled(int dir)
  signal menuRequested(real x, real y)

  property real homeCenter: 0
  property real magnifyScale: {
    if (!root) return 1
    if (root.waveHover) return root.magnifyScaleAt(btn.homeCenter)
    if (root.hoverEffect === "off") return 1
    return area.containsMouse ? root.zoomPeak : 1
  }

  Behavior on magnifyScale {
    NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
  }

  readonly property real waveNudgeX: 0

  width: {
    if (!root) return 0
    if (root.waveHover) return Math.round(root.iconSlot * (1 + (btn.magnifyScale - 1) * 0.70))
    return root.iconSlot
  }
  height: root ? root.iconSlot : 0
  z: Math.round(btn.magnifyScale * 100)

  Text {
    anchors.centerIn: parent
    text: btn.glyph
    textFormat: Text.PlainText
    font.family: "omarchy"
    font.pixelSize: btn.glyphSize
    color: area.containsMouse ? Color.accent : btn.glyphColor
    scale: btn.magnifyScale * (area.pressed ? 0.92 : 1.0)
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        var targetWin = root ? root.contentItemRef : null
        var pt = targetWin ? btn.mapToItem(targetWin, btn.width / 2, 0) : null
        var gx = pt ? pt.x : (btn.width / 2)
        btn.menuRequested(gx, 0)
      } else if (mouse.button === Qt.MiddleButton) {
        btn.middleClicked()
      } else {
        btn.pressed()
      }
    }
    onWheel: function(wheel) {
      if (wheel.angleDelta.y !== 0) btn.wheelScrolled(wheel.angleDelta.y > 0 ? -1 : 1)
    }
  }

  HoverTooltip {
    text: btn.tooltip
    hovered: area.containsMouse
    showTooltips: root ? root.showTooltips : true
    tooltipDelay: root ? root.tooltipDelay : 450
    contextAppId: root ? root.contextAppId : ""
    x: (btn.width - width) / 2
    y: -height - Style.space(8)
  }
}
