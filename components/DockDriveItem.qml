import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

Item {
  id: ditem

  property var rootRef: null
  readonly property var root: rootRef

  property string dev: ""
  property string mountpoint: ""
  property string name: "USB Drive"
  property string size: ""
  property string space: ""
  property string fstype: ""
  property string icon: "folder"
  property real homeCenter: 0

  signal openStackRequested(string path, string name, real cx, real cy)
  signal menuRequested(string dev, string mountpoint, string name, string space, real cx, real cy)

  width: root ? (root.iconSlot * (root.waveHover ? ditem.magnifyScale : 1)) : 0
  height: root ? root.iconSlot : 0
  z: Math.round(ditem.magnifyScale * 100)

  readonly property bool isOpen: root ? root.activeStackFolder === ditem.mountpoint : false

  property real magnifyScale: {
    if (!root) return 1
    if (root.waveHover) return root.magnifyScaleAt(ditem.homeCenter)
    if (root.hoverEffect === "off") return 1
    return driveArea.containsMouse ? root.zoomPeak : 1
  }

  readonly property string resolvedSource: {
    var _tv = root ? root.themeVersion : 0
    var iconName = ditem.icon || "drive-removable-media-usb"
    if (iconName.indexOf("/") === 0 || iconName.indexOf("file://") === 0) return iconName
    var fileUri = DockModel.resolveDriveIcon(iconName, root ? root.currentIconThemeName : "Yaru")
    if (fileUri && fileUri !== "") return fileUri
    return "file:///usr/share/icons/Yaru/256x256/devices/drive-removable-media-usb.png"
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

    Image {
      id: driveIconImg
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.round((iconSlot.height - (root ? root.baseIconArt : 32)) / 2)
      width: (root ? root.baseIconArt : 32) * ditem.magnifyScale
      height: width
      source: ditem.resolvedSource
      sourceSize: Qt.size(
        Math.max(32, Math.round((root ? root.iconSize : 36) * 4)),
        Math.max(32, Math.round((root ? root.iconSize : 36) * 4))
      )
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      visible: source !== ""
    }
  }

  // Active stack open indicator dot
  Rectangle {
    visible: ditem.isOpen
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(1)
    anchors.horizontalCenter: parent.horizontalCenter
    width: Style.space(4)
    height: Style.space(4)
    radius: width / 2
    color: Color.accent
  }

  MouseArea {
    id: driveArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      var targetWin = root ? root.contentItemRef : null
      if (mouse.button === Qt.RightButton) {
        var mappedPos = targetWin ? ditem.mapToItem(targetWin, ditem.width / 2, 0) : null
        if (!mappedPos) return
        ditem.menuRequested(ditem.dev, ditem.mountpoint, ditem.name, ditem.space, mappedPos.x, 0)
      } else {
        var centerPos = targetWin ? ditem.mapToItem(targetWin, ditem.width / 2, 0) : null
        if (!centerPos) return
        ditem.openStackRequested(ditem.mountpoint, ditem.name, centerPos.x, centerPos.y)
      }
    }
  }

  // Hover tooltip
  HoverTooltip {
    text: ditem.name + (ditem.space !== "" ? (" (USB • " + ditem.space + ")") : " (USB Drive)")
    hovered: driveArea.containsMouse
    blocked: (!root || !root.showTooltips || root.activeStackFolder !== "")
    showTooltips: root ? root.showTooltips : true
    tooltipDelay: root ? root.tooltipDelay : 450
    contextAppId: root ? root.contextAppId : ""
    y: -height - Style.space(8)
  }
}
