import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

Item {
  id: fitem

  property var rootRef: null
  readonly property var root: rootRef

  property string folderPath: ""
  property string name: ""
  property string icon: "folder"
  property real homeCenter: 0

  signal openStackRequested(string path, string name, real cx, real cy)
  signal menuRequested(string path, string name, real cx, real cy)

  width: root ? root.iconSlot : 0
  height: root ? root.iconSlot : 0
  z: Math.round(fitem.magnifyScale * 100)

  readonly property bool isOpen: root ? root.activeStackFolder === fitem.folderPath : false

  property real magnifyScale: {
    if (!root) return 1
    if (root.waveHover) return root.magnifyScaleAt(fitem.homeCenter)
    if (root.hoverEffect === "off") return 1
    return area.containsMouse ? root.zoomPeak : 1
  }

  readonly property real waveNudgeX: root ? root.waveOffsetAt(fitem.homeCenter) : 0

  readonly property string resolvedSource: {
    var _tv = root ? root.themeVersion : 0
    return DockModel.resolveThemedFolderIcon(fitem.icon, root ? root.currentIconThemeName : "Yaru", root ? root.folderColor : "theme")
  }
  readonly property bool isSymbolic: resolvedSource.indexOf("-symbolic.svg") >= 0 || resolvedSource.indexOf("symbolic") >= 0
  readonly property color symbolicColor: {
    if (root && root.folderColor === "white") return "#ffffff"
    if (root && root.folderColor === "black") return "#111111"
    return (Color.bar.background.hslLightness < 0.5 || Color.background.hslLightness < 0.5) ? "#ffffff" : "#111111"
  }

  Behavior on magnifyScale {
    NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
  }

  Item {
    id: iconSlot
    width: root ? root.iconSlot : 0
    height: root ? root.iconSlot : 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter

    Item {
      id: iconContainer
      width: root ? root.iconSize : 0
      height: root ? root.iconSize : 0
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.round((iconSlot.height - height) / 2)
      scale: fitem.magnifyScale
      transformOrigin: Item.Bottom
      transform: Translate { x: fitem.waveNudgeX }

      Image {
        id: folderIconImg
        anchors.fill: parent
        source: fitem.resolvedSource
        sourceSize: Qt.size((root ? root.iconSize : 36) * 4, (root ? root.iconSize : 36) * 4)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        visible: !fitem.isSymbolic
      }

      Item {
        anchors.fill: parent
        visible: fitem.isSymbolic

        Image {
          id: symbolicImg
          anchors.fill: parent
          source: fitem.resolvedSource
          sourceSize: Qt.size((root ? root.iconSize : 36) * 4, (root ? root.iconSize : 36) * 4)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          mipmap: true
          visible: false
        }

        MultiEffect {
          anchors.fill: symbolicImg
          source: symbolicImg
          colorization: 1.0
          colorizationColor: fitem.symbolicColor
        }
      }
    }
  }

  // Active stack open indicator dot
  Rectangle {
    visible: fitem.isOpen
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(1)
    anchors.horizontalCenter: parent.horizontalCenter
    transform: Translate { x: fitem.waveNudgeX }
    width: Style.space(4)
    height: Style.space(4)
    radius: width / 2
    color: Color.bar.active
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      var targetWin = root ? root.contentItemRef : null
      if (mouse.button === Qt.RightButton) {
        var mappedPos = targetWin ? fitem.mapToItem(targetWin, fitem.width / 2, 0) : null
        if (!mappedPos) return
        fitem.menuRequested(fitem.folderPath, fitem.name, mappedPos.x, 0)
      } else {
        var centerPos = targetWin ? fitem.mapToItem(targetWin, fitem.width / 2, 0) : null
        if (!centerPos) return
        fitem.openStackRequested(fitem.folderPath, fitem.name, centerPos.x, centerPos.y)
      }
    }
  }

  // Hover tooltip — uses our own HoverTooltip so textFormat: Text.PlainText is enforced.
  HoverTooltip {
    text: fitem.name + " (Folder)"
    hovered: area.containsMouse
    blocked: (!root || !root.showTooltips || root.activeStackFolder !== "")
    showTooltips: root ? root.showTooltips : true
    tooltipDelay: root ? root.tooltipDelay : 450
    contextAppId: root ? root.contextAppId : ""
    x: (fitem.width - width) / 2
    y: -height - Style.space(8)
  }
}
