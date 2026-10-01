import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

Item {
  id: gitem

  property var rootRef: null
  readonly property var root: rootRef

  property var groupData: null
  property real homeCenter: 0

  readonly property string groupId: (groupData && groupData.id) ? groupData.id : ""
  readonly property string groupName: (groupData && groupData.name) ? groupData.name : "Folder"
  readonly property var groupApps: (groupData && DockModel.isList(groupData.apps)) ? DockModel.toArray(groupData.apps) : []

  signal openGroupRequested(var gdata, real cx, real cy)
  signal menuRequested(var gdata, real cx, real cy)
  signal dragStarted(string groupId)
  signal dragMoved(string groupId, real x, real y)
  signal dragDropped(string groupId)

  // Faded while dragged, fainter still once pulled off the dock.
  opacity: groupArea.dragging ? ((root && root.dragRemoveArmed) ? 0.12 : 0.35) : 1.0

  width: root ? (root.iconSlot * (root.waveHover ? gitem.magnifyScale : 1)) : 0
  height: root ? root.iconSlot : 0
  z: Math.round(gitem.magnifyScale * 100)

  readonly property bool isOpen: root ? root.activeAppGroupId === gitem.groupId : false
  readonly property bool isDropTarget: (root && (root.dropTargetGroupId === gitem.groupId || root.dropTargetAppId === gitem.groupId))

  // Check running / active / window stats for apps in this group
  readonly property var groupRunningInfo: {
    var hasRun = false
    var hasActive = false
    var count = 0
    if (!root) return { running: false, active: false, count: 0 }
    var running = root.runningSection || []
    var grouped = root.groupedSection || []
    var all = running.concat(grouped)
    for (var a = 0; a < gitem.groupApps.length; a++) {
      var aid = gitem.groupApps[a]
      for (var r = 0; r < all.length; r++) {
        var ent = all[r]
        if (ent && (ent.appId === aid || DockModel.isAppMatch(ent.appId, aid))) {
          if (ent.running) {
            hasRun = true
            count += (ent.windows || 1)
            if (ent.appId === root.activeId) hasActive = true
          }
        }
      }
    }
    return { running: hasRun, active: hasActive, count: count }
  }

  readonly property bool hasRunningApps: groupRunningInfo.running

  property real magnifyScale: {
    if (!root) return 1
    if (root.waveHover) return root.magnifyScaleAt(gitem.homeCenter)
    if (root.hoverEffect === "off") return 1
    return groupArea.containsMouse ? root.zoomPeak : 1
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
      width: root ? root.baseIconArt : 0
      height: width
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root ? root.iconArtBottom : 0
      scale: gitem.magnifyScale
      transformOrigin: Item.Bottom

      // Without a dock card, the tile casts its own shadow like the icons.
      layer.enabled: root ? root.iconShadow : false
      layer.smooth: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: root ? root.shadowStrength : 0.4
        shadowBlur: 0.45
        shadowVerticalOffset: Math.max(1, Math.round(iconContainer.height * 0.05))
        autoPaddingEnabled: true
      }

      // Drop target halo
      Rectangle {
        visible: gitem.isDropTarget
        anchors.centerIn: parent
        width: parent.width + Style.space(8)
        height: width
        // Follows the tile's own shape, a little wider.
        radius: folderTile.radius > 0 ? folderTile.radius + Style.space(4) : 0
        color: Util.alpha(Color.accent, 0.22)
        border.color: Color.accent
        border.width: 1.5
        z: -1
        SequentialAnimation on opacity {
          running: gitem.isDropTarget
          loops: Animation.Infinite
          NumberAnimation { from: 0.5; to: 1.0; duration: 350; easing.type: Easing.InOutQuad }
          NumberAnimation { from: 1.0; to: 0.5; duration: 350; easing.type: Easing.InOutQuad }
        }
      }

      // Folder tile (macOS / iOS Launchpad folder style). groupStyle picks
      // the frame: a softly rounded rim, a square rim, or none at all (just
      // the mini-icon grid).
      Rectangle {
        id: folderTile
        readonly property string tileStyle: root ? root.groupStyle : "rounded"
        anchors.fill: parent
        radius: tileStyle === "rounded" ? Math.round(width * 0.18) : 0
        color: tileStyle === "none" ? "transparent" : Util.alpha(Color.bar.background, 0.4)
        border.color: Util.alpha(Color.menu.border, 0.45)
        border.width: tileStyle === "none" ? 0 : 1

        // Empty folder fallback icon
        Image {
          visible: gitem.groupApps.length === 0
          anchors.centerIn: parent
          width: Math.round(parent.width * 0.55)
          height: width
          source: Quickshell.iconPath("folder", true)
          fillMode: Image.PreserveAspectFit
          smooth: true
        }

        // 2x2 Mini Icons Grid Preview
        Grid {
          visible: gitem.groupApps.length > 0
          anchors.centerIn: parent
          columns: 2
          rows: 2
          spacing: Style.space(2)

          Repeater {
            model: gitem.groupApps.slice(0, 4)
            delegate: Item {
              id: miniCell
              // Without a frame the grid can use the whole tile.
              readonly property real miniSize: Math.round(iconContainer.width * (folderTile.tileStyle === "none" ? 0.46 : 0.36))
              width: miniSize
              height: miniSize

              readonly property string appIconName: {
                var dEntry = root ? DockModel.entryFor(root.appRows, modelData) : null
                if (dEntry && dEntry.icon) return dEntry.icon
                return String(modelData || "")
              }

              readonly property string miniSource: {
                if (root && root.appLibrary) {
                  var src = DockModel.resolveAppIcon(root.appLibrary, root.appRows, modelData)
                  if (src) return src
                }
                var p = Quickshell.iconPath(miniCell.appIconName, true)
                if (p && p !== "") return p
                return Quickshell.iconPath("application-x-executable", true)
              }

              DockIconArt {
                anchors.fill: parent
                source: miniCell.miniSource
                renderSize: miniCell.miniSize * 2
                iconStyle: root ? root.iconStyle : "original"
                tint: root ? root.iconTintColor : Color.bar.text
                // Same cell size as a full icon, so the minis match it.
                grid: root ? Math.round(root.iconGrid * miniCell.miniSize / Math.max(1, root.baseIconArt)) : 8
                contrast: root ? root.iconContrast : 0
                strength: root ? root.iconStrength : 1
                showOriginal: root ? (root.iconHoverOriginal && groupArea.containsMouse) : false
              }
            }
          }
        }
      }
    }
  }

  // Running indicator dot underneath the folder if any child app is running
  // 3-state running indicator row underneath the folder if any child app is running
  Row {
    id: indicatorRow
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(1)
    spacing: Style.space(3)
    visible: gitem.hasRunningApps || gitem.isOpen

    // Same marks as an app: the first turns into the accent bar while one
    // of the group's apps has focus or the group is open.
    Repeater {
      model: Math.min(3, Math.max(1, gitem.groupRunningInfo.count))
      delegate: DockIndicator {
        rootRef: gitem.rootRef
        anchors.verticalCenter: parent.verticalCenter
        kind: index === 0 && (gitem.groupRunningInfo.active || gitem.isOpen) ? "active" : "window"
      }
    }
  }

  DockPressDrag {
    id: groupArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    mapTarget: root ? root.dockCard : null

    onDragStarted: gitem.dragStarted(gitem.groupId)
    onDragMoved: function(x, y) { gitem.dragMoved(gitem.groupId, x, y) }
    onDragFinished: gitem.dragDropped(gitem.groupId)

    onTapped: function(mouse) {
      var targetWin = root ? root.contentItemRef : null
      if (mouse.button === Qt.RightButton) {
        var mappedPos = targetWin ? gitem.mapToItem(targetWin, gitem.width / 2, 0) : null
        if (!mappedPos) return
        gitem.menuRequested(gitem.groupData, mappedPos.x, 0)
      } else {
        var centerPos = targetWin ? gitem.mapToItem(targetWin, gitem.width / 2, 0) : null
        if (!centerPos) return
        gitem.openGroupRequested(gitem.groupData, centerPos.x, centerPos.y)
      }
    }
  }

  // Hover tooltip
  HoverTooltip {
    text: gitem.groupName + " (" + gitem.groupApps.length + (gitem.groupApps.length === 1 ? " app)" : " apps)")
    hovered: groupArea.containsMouse
    blocked: (!root || !root.showTooltips || root.activeAppGroupId !== "")
    showTooltips: root ? root.showTooltips : true
    tooltipDelay: root ? root.tooltipDelay : 450
    contextAppId: root ? root.contextAppId : ""
    y: -height - Style.space(8)
  }
}
