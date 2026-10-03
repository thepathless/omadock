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

  // Folder badges sum their members' counts (macOS folder badge), each id
  // spelling counted once via DockModel's aliases.
  readonly property int badgeCount: {
    if (!root || !root.showNotificationBadges) return 0
    return DockModel.groupBadgeTotal(gitem.groupApps, root.notificationBadges)
  }

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

  // What the indicator row stands for: the folder's focused app, else its
  // first running one. Clicking the row toggles that app like its icon would.
  readonly property string indicatorAppId: {
    if (!root) return ""
    var fallback = ""
    for (var a = 0; a < gitem.groupApps.length; a++) {
      var ent = root.entryForId(gitem.groupApps[a])
      if (!ent || !ent.running) continue
      var focused = root.activeId && DockModel.isAppMatch(ent.appId, root.activeId)
      if (!focused) {
        var wins = ent.windowList || []
        for (var w = 0; w < wins.length; w++) {
          if (wins[w] && wins[w].address && wins[w].address === root.activeWindowAddress) {
            focused = true
            break
          }
        }
      }
      if (focused) return ent.appId
      if (fallback === "") fallback = ent.appId
    }
    return fallback
  }

  property real magnifyScale: {
    if (!root) return 1
    if (root.waveHover) return root.magnifyScaleAt(gitem.homeCenter)
    if (root.hoverEffect !== "zoom") return 1
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

      // Hover effects apply to the whole tile, which is drawn inside this.
      HoverFx {
        id: tileFx
        anchors.fill: parent
        hovered: groupArea.containsMouse
        hoverFx: root ? root.hoverFx : null
      }

      // Badge: the folder's summed count, same mark as an app badge.
      Rectangle {
        visible: gitem.badgeCount > 0
        parent: tileFx.contentItem
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: -Style.space(3)
        anchors.topMargin: -Style.space(3)
        width: Math.max(Style.space(17), groupBadgeText.implicitWidth + Style.space(8))
        height: Style.space(17)
        radius: height / 2
        color: Color.accent
        border.width: 1
        border.color: Color.bar.background
        z: 2
        Text {
          id: groupBadgeText
          anchors.centerIn: parent
          text: gitem.badgeCount > 99 ? "99+" : String(gitem.badgeCount)
          textFormat: Text.PlainText
          color: root && root.isLight(Color.accent) ? "#12100f" : "#f2efec"
          font.family: Style.font.family
          font.pixelSize: Style.space(10)
          font.bold: true
        }
      }

      // Folder tile (macOS / iOS Launchpad folder style). groupStyle picks
      // the frame: a softly rounded rim, a square rim, or none at all (just
      // the mini-icon grid).
      Rectangle {
        id: folderTile
        parent: tileFx.contentItem
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
                hoverFx: root ? root.hoverFx : null
              }
            }
          }
        }
      }
    }
  }

  // 3-state running indicator row underneath the folder if any child app is
  // running. Wrapped in a band so the click area can size to the row without
  // entering the Row's own layout.
  Item {
    id: indicatorBand
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(1)
    width: indicatorRow.width
    height: indicatorRow.height
    visible: gitem.hasRunningApps || gitem.isOpen
    z: 2

    Row {
      id: indicatorRow
      spacing: Style.space(3)

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

    // One click on the marks toggles the app they stand for; hover still
    // reaches the tile beneath so its effects and tooltip keep working.
    MouseArea {
      id: indicatorHit
      anchors.fill: parent
      anchors.margins: -Style.space(3)
      enabled: gitem.indicatorAppId !== ""
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (root) root.activate(gitem.indicatorAppId)
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
    dockRoot: root
    text: gitem.groupName + " (" + gitem.groupApps.length + (gitem.groupApps.length === 1 ? " app)" : " apps)")
    hovered: groupArea.containsMouse
    blocked: (!root || !root.showTooltips || root.activeAppGroupId !== "")
    showTooltips: root ? root.showTooltips : true
    tooltipDelay: root ? root.tooltipDelay : 450
    contextAppId: root ? root.contextAppId : ""
  }
}
