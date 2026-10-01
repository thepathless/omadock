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
  // Position among the pinned folders; a folder dragged in from outside and
  // headed for this index opens a gap before this item.
  property int slotIndex: -1
  readonly property bool gapOpen: root ? (root.dropPreviewPath !== "" && root.dropInsertIndex === fitem.slotIndex) : false
  property real gapWidth: gapOpen && root ? root.iconSlot + root.gapWidth : 0
  Behavior on gapWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

  signal openStackRequested(string path, string name, real cx, real cy)
  signal menuRequested(string path, string name, real cx, real cy)
  signal dragStarted(string path)
  signal dragMoved(string path, real x, real y)
  signal dragDropped(string path)

  // Faded while dragged, fainter still once pulled off the dock.
  opacity: area.dragging ? ((root && root.dragRemoveArmed) ? 0.12 : 0.35) : 1.0

  width: (root ? (root.iconSlot * (root.waveHover ? fitem.magnifyScale : 1)) : 0) + fitem.gapWidth
  height: root ? root.iconSlot : 0

  DropGhost {
    rootRef: fitem.rootRef
    width: fitem.gapWidth
    height: parent.height
  }

  readonly property bool isOpen: root ? root.activeStackFolder === fitem.folderPath : false

  property real magnifyScale: {
    if (!root) return 1
    if (root.waveHover) return root.magnifyScaleAt(fitem.homeCenter)
    if (root.hoverEffect === "off") return 1
    return area.containsMouse ? root.zoomPeak : 1
  }

  readonly property string resolvedSource: {
    var _tv = root ? root.themeVersion : 0
    return DockModel.resolveThemedFolderIcon(fitem.icon, root ? root.currentIconThemeName : "Yaru", root ? root.folderColor : "theme", root ? root.appLibrary : null)
  }
  readonly property bool isSymbolic: resolvedSource.indexOf("-symbolic.svg") >= 0 || resolvedSource.indexOf("symbolic") >= 0
  readonly property color symbolicColor: root ? root.symbolicIconColor : "#ffffff"

  Behavior on magnifyScale {
    NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
  }

  Item {
    id: iconSlot
    width: root ? root.iconSlot : 0
    height: root ? root.iconSlot : 0
    // Centred in the part of the item the drop gap leaves.
    x: fitem.gapWidth + Math.round((fitem.width - fitem.gapWidth - width) / 2)
    anchors.verticalCenter: parent.verticalCenter

    Item {
      id: iconContainer
      width: root ? root.baseIconArt : 0
      height: width
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root ? root.iconArtBottom : 0
      scale: fitem.magnifyScale
      // Grows upward like the app icons, never over the indicator band.
      transformOrigin: Item.Bottom

      // Symbolic icons keep their own recolouring in the original style;
      // every other case goes through the dock's icon style.
      readonly property bool themedSymbolic: fitem.isSymbolic && (!root || root.iconStyle === "original" || (root.iconHoverOriginal && area.containsMouse))

      DockIconArt {
        id: folderIconImg
        anchors.fill: parent
        source: fitem.resolvedSource
        renderSize: root ? root.maxIconArt : 64
        visible: !iconContainer.themedSymbolic
        iconStyle: root ? root.iconStyle : "original"
        tint: root ? root.iconTintColor : Color.bar.text
        grid: root ? root.iconGrid : 16
        contrast: root ? root.iconContrast : 0
        strength: root ? root.iconStrength : 1
        dropShadow: root ? root.iconShadow : false
        shadowStrength: root ? root.shadowStrength : 0.4
        showOriginal: root ? (root.iconHoverOriginal && area.containsMouse) : false
      }

      Item {
        anchors.fill: parent
        visible: iconContainer.themedSymbolic

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

  // Open stack: the same accent bar an app with focus shows.
  DockIndicator {
    rootRef: fitem.rootRef
    visible: fitem.isOpen
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(1)
    anchors.horizontalCenter: iconSlot.horizontalCenter
    kind: "active"
  }

  DockPressDrag {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    mapTarget: root ? root.dockCard : null

    onDragStarted: fitem.dragStarted(fitem.folderPath)
    onDragMoved: function(x, y) { fitem.dragMoved(fitem.folderPath, x, y) }
    onDragFinished: fitem.dragDropped(fitem.folderPath)

    onTapped: function(mouse) {
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
    y: -height - Style.space(8)
  }
}
