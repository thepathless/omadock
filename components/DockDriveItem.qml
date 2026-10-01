import QtQuick
import QtQuick.Effects
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
    var fileUri = DockModel.resolveDriveIcon(iconName, root ? root.currentIconThemeName : "Yaru", root ? root.appLibrary : null, root ? root.folderColor : "theme")
    if (fileUri && fileUri !== "") return fileUri
    return root && root.appLibrary ? root.appLibrary.iconSource("drive-removable-media-usb") : "file:///usr/share/icons/Yaru/256x256/devices/drive-removable-media-usb.png"
  }

  readonly property bool isSymbolic: resolvedSource.indexOf("symbolic") >= 0

  Behavior on magnifyScale {
    NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
  }

  Item {
    id: iconSlot
    width: root ? root.iconSlot : 0
    height: root ? root.iconSlot : 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter

    // Symbolic icons are grey templates; in the original style they take
    // the folder colour, as folder icons do. Every other case goes through
    // the dock's icon style.
    readonly property bool themedSymbolic: ditem.isSymbolic && (!root || root.iconStyle === "original" || (root.iconHoverOriginal && driveArea.containsMouse))

    DockIconArt {
      id: driveIconImg
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root ? root.iconArtBottom : 0
      width: (root ? root.baseIconArt : 32) * ditem.magnifyScale
      height: width
      source: ditem.resolvedSource
      renderSize: root ? root.maxIconArt : 64
      visible: String(source) !== "" && !iconSlot.themedSymbolic
      iconStyle: root ? root.iconStyle : "original"
      tint: root ? root.iconTintColor : Color.bar.text
      grid: root ? root.iconGrid : 16
      contrast: root ? root.iconContrast : 0
      strength: root ? root.iconStrength : 1
      dropShadow: root ? root.iconShadow : false
      shadowStrength: root ? root.shadowStrength : 0.4
      showOriginal: root ? (root.iconHoverOriginal && driveArea.containsMouse) : false
    }

    Item {
      anchors.fill: driveIconImg
      visible: iconSlot.themedSymbolic

      Image {
        id: symbolicImg
        anchors.fill: parent
        source: ditem.resolvedSource
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
        colorizationColor: root ? root.symbolicIconColor : "#ffffff"
      }
    }
  }

  // Open stack: the same accent bar an app with focus shows.
  DockIndicator {
    rootRef: ditem.rootRef
    visible: ditem.isOpen
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(1)
    anchors.horizontalCenter: parent.horizontalCenter
    kind: "active"
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
