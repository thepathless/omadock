import QtQuick 6.11
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui
import "../DockIcons.js" as DockIcons

Item {
  id: fitem

  property var rootRef: null
  readonly property var root: rootRef
  readonly property var motion: fitem.root ? fitem.root.motion : null

  property string folderPath: ""
  // A pinned slot with a command is a button, not a folder: the click runs the
  // command and no file listing is built for it.
  property string command: ""
  readonly property bool isButton: fitem.command !== ""
  // What this slot opens: a button opens nothing.
  readonly property string activeFolderPath: fitem.isButton ? "" : fitem.folderPath
  property string name: ""
  property string icon: "folder"
  property real homeCenter: 0
  property int labelSlot: -1
  // An open hover label is drawn over the neighbours.
  z: label.overlay && label.progress > 0.01 ? 1000 : 0
  readonly property real labelExtra: label.extra
  readonly property real iconCenterX: iconSlot.x + iconSlot.width / 2
  // Position among the pinned folders; a folder dragged in from outside and
  // headed for this index opens a gap before this item.
  property int slotIndex: -1
  readonly property bool gapOpen: root ? (root.dropPreviewPath !== "" && root.dropInsertIndex === fitem.slotIndex) : false
  property real ghostWidth: gapOpen && root ? root.iconSlot + root.gapWidth : 0
  Behavior on ghostWidth { NumberAnimation { duration: (fitem.motion ? fitem.motion.base : 0); easing.type: Easing.OutCubic } }
  // A pinned folder dragged in the dock lands before this one.
  property bool dropLineHere: false
  // All the room ahead of the folder's tile: the ghost's, or the drag's.
  readonly property real gapWidth: fitem.ghostWidth + dropGapItem.width
  readonly property real dropGap: dropGapItem.width

  DropGap {
    id: dropGapItem
    rootRef: fitem.rootRef
    open: fitem.dropLineHere
  }

  signal openStackRequested(string path, string name, real cx, real cy)
  // command: "" for a folder, the button's own command for a button slot.
  signal menuRequested(string path, string name, real cx, real cy, string command)
  signal dragStarted(string path)
  signal dragMoved(string path, real x, real y)
  signal dragDropped(string path)

  width: (root ? (root.iconSlot * (root.waveHover ? fitem.magnifyScale : 1)) : 0) + fitem.gapWidth + fitem.labelExtra
  height: root ? root.iconSlot : 0

  DropGhost {
    rootRef: fitem.rootRef
    width: fitem.ghostWidth
    height: parent.height
  }

  // A button never opens a stack, and two empty strings must not count as
  // a match (that lit the "open" indicator under every button).
  readonly property bool isOpen: root ? (fitem.activeFolderPath !== "" && root.activeStackFolder === fitem.activeFolderPath) : false

  property real magnifyScale: {
    if (!root) return 1
    if (root.waveHover) return root.magnifyScaleAt(fitem.homeCenter)
    if (root.hoverEffect !== "zoom") return 1
    return area.containsMouse ? root.zoomPeak : 1
  }

  readonly property string resolvedSource: {
    var _tv = root ? root.themeVersion : 0
    return DockIcons.resolveThemedFolderIcon(fitem.icon, root ? root.currentIconThemeName : "Yaru", root ? root.folderColor : "theme", root ? root.appLibrary : null)
  }
  readonly property bool isSymbolic: resolvedSource.indexOf("-symbolic.svg") >= 0 || resolvedSource.indexOf("symbolic") >= 0
  // On a label plate a symbolic icon takes the label's ink, which reads on the plate.
  readonly property color symbolicColor: (label.plate && label.shown) ? label.ink : (root ? root.symbolicIconColor : "#ffffff")

  Behavior on magnifyScale {
    NumberAnimation { duration: (fitem.motion ? fitem.motion.hover : 0); easing.type: Easing.OutQuad }
  }

  Item {
    id: iconSlot
    width: root ? root.iconSlot : 0
    height: root ? root.iconSlot : 0
    // Centred in the part of the item the drop gap leaves.
    x: fitem.gapWidth + (label.mirror ? fitem.labelExtra - label.lead : label.lead) + Math.round((fitem.width - fitem.gapWidth - fitem.labelExtra - width) / 2)
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
        tint: (root && label.plate && label.shown) ? root.plateIconTintColor : (root ? root.iconTintColor : Color.bar.text)
        toneInvert: fitem.isSymbolic ? 1 : -1
        allowReveal: !fitem.isSymbolic
        grid: root ? root.iconGrid : 16
        outputScale: root ? root.outputScale : 1
        contrast: root ? root.iconContrast : 0
        strength: root ? root.iconStrength : 1
        dropShadow: root ? root.iconShadow : false
        shadowStrength: root ? root.shadowStrength : 0.4
        showOriginal: root ? (root.iconHoverOriginal && area.containsMouse) : false
        hovered: area.containsMouse
        hoverFx: root ? root.hoverFx : null
      }

      HoverFx {
        anchors.fill: parent
        visible: iconContainer.themedSymbolic
        hovered: area.containsMouse
        hoverFx: root ? root.hoverFx : null

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
          // Symbolic icons are dark grey; colorization keeps the source's
          // lightness, so lift it to white first or light colours come out grey.
          brightness: 1.0
          colorization: 1.0
          colorizationColor: fitem.symbolicColor
        }
      }
    }
  }

  // Open stack: the same accent bar an app with focus shows.
  DockIndicator {
    rootRef: fitem.rootRef
    visible: fitem.isOpen && !label.sideMarks
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(1) + (root ? root.indicatorLift : 0)
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

    // A button is not a folder: it is not dragged around the folder row.
    onDragStarted: if (!fitem.isButton) fitem.dragStarted(fitem.folderPath)
    onDragMoved: function(x, y) { if (!fitem.isButton) fitem.dragMoved(fitem.folderPath, x, y) }
    onDragFinished: if (!fitem.isButton) fitem.dragDropped(fitem.folderPath)

    onTapped: function(mouse) {
      var targetWin = root ? root.contentItemRef : null
      if (mouse.button === Qt.LeftButton && fitem.isButton) {
        // argv form, as the folder popup does with xdg-open; the command comes
        // from the user's own config and is length-bounded in DockModel.
        Quickshell.execDetached(["sh", "-c", fitem.command])
        return
      }
      if (mouse.button === Qt.RightButton) {
        var mappedPos = targetWin ? fitem.mapToItem(targetWin, fitem.iconCenterX, 0) : null
        if (!mappedPos) return
        fitem.menuRequested(fitem.folderPath, fitem.name, mappedPos.x, 0, fitem.command)
      } else {
        var centerPos = targetWin ? fitem.mapToItem(targetWin, fitem.iconCenterX, 0) : null
        if (!centerPos) return
        fitem.openStackRequested(fitem.folderPath, fitem.name, centerPos.x, centerPos.y)
      }
    }
  }

  // Name beside the folder (DockLabel, policy in DockLabelLogic).
  DockLabel {
    id: label
    z: -1
    rootRef: fitem.rootRef
    folded: root ? root.fitHostRef.folds("folder", true, false) : false
    kind: "folder"
    name: fitem.name
    hovered: area.containsMouse && !area.dragging
    iconBox: iconSlot
    tileLead: fitem.gapWidth
    slot: fitem.labelSlot
  }

  // Hover tooltip — uses our own HoverTooltip so textFormat: Text.PlainText is enforced.
  HoverTooltip {
    dockRoot: root
    text: fitem.isButton ? fitem.name : (fitem.name + " (Folder)")
    hovered: area.containsMouse
    blocked: (!root || !root.showTooltips || root.activeStackFolder !== "")
      || (root && !root.labelTooltipNeeded("folder", false, false, label.shortened))
    target: iconSlot
    // The name chip floats between this bubble and the bar; the preview
    // stacks above it in the clear band the name reserved.
    chipClear: label.overlay ? label.chipClear : 0
    showTooltips: root ? root.showTooltips : true
    tooltipDelay: root ? root.tooltipDelay : 450
    contextAppId: root ? root.contextAppId : ""
  }
}
