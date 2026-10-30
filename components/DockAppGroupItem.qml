import QtQuick 6.11
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel
import "strings"

Item {
  id: gitem

  property var rootRef: null
  readonly property var root: rootRef
  readonly property var motion: gitem.root ? gitem.root.motion : null

  property var groupData: null
  property real homeCenter: 0
  property int labelSlot: -1
  readonly property real labelExtra: label.extra
  // A drag in the dock lands before this group: room opens ahead of it.
  property bool dropLineHere: false
  readonly property real dropGap: dropGapItem.width

  DropGap {
    id: dropGapItem
    rootRef: gitem.rootRef
    open: gitem.dropLineHere
  }
  readonly property real iconCenterX: iconSlot.x + iconSlot.width / 2

  readonly property string groupId: (groupData && groupData.id) ? groupData.id : ""
  readonly property string groupName: (groupData && groupData.name) ? groupData.name : Tr.t("common.folder", "Folder")
  readonly property var groupApps: (groupData && DockModel.isList(groupData.apps)) ? DockModel.toArray(groupData.apps) : []

  signal openGroupRequested(var gdata, real cx, real cy)
  signal menuRequested(var gdata, real cx, real cy)
  signal dragStarted(string groupId)
  signal dragMoved(string groupId, real x, real y)
  signal dragDropped(string groupId)

  // Scroll-cycled member preview for the hover bubble's card stack: -1 until
  // the wheel is used over the tile, then the index the next click focuses.
  property int previewIndex: -1

  // Wheel over the tile cycles which member window the bubble previews.
  // The routing and cycling live in DockGroupCycleLogic; this only forwards.
  function handlePreviewWheel(wheel) {
    if (!root || !root.advancedTooltips) return
    var wins = gitem.tooltipWindows
    if (wins.length < 2) return
    var cur = gitem.previewIndex
    if (cur < 0 || cur >= wins.length) {
      var fi = root.focusedIndex(wins)
      cur = fi >= 0 ? fi : 0
    }
    gitem.previewIndex = root.groupCycleFront("group:" + gitem.groupId, wins, cur, wheel.angleDelta.y)
  }

  // A scroll-armed preview claims the next click: it focuses the member
  // window the bubble is showing and disarms, so a plain click (no scroll)
  // keeps opening the group popup exactly as before.
  function clickPreviewOr(openPopup) {
    if (gitem.previewIndex >= 0 && root && gitem.previewIndex < gitem.tooltipWindows.length) {
      root.focusPreviewedWindow(gitem.tooltipWindows, gitem.previewIndex)
      gitem.previewIndex = -1
      return
    }
    openPopup()
  }

  width: (root ? (root.iconSlot * (root.waveHover ? gitem.magnifyScale : 1)) : 0) + gitem.labelExtra + gitem.dropGap
  height: root ? root.iconSlot : 0
  // An open hover label is drawn over the neighbours.
  z: Math.round(gitem.magnifyScale * 100) + (label.overlay && label.progress > 0.01 ? 1000 : 0)

  readonly property bool isOpen: root ? root.activeAppGroupId === gitem.groupId : false
  readonly property bool isDropTarget: (root && (root.dropTargetGroupId === gitem.groupId || root.dropTargetAppId === gitem.groupId))

  // Folder badges sum their members' counts (macOS folder badge), each id
  // spelling counted once via DockModel's aliases.
  readonly property int badgeCount: {
    if (!root || !root.showNotificationBadges) return 0
    return DockModel.groupBadgeTotal(gitem.groupApps, root.notificationBadges)
  }

  // Every window of every member app, in member order, each window once.
  // The indicator row and the tooltip's previews read the same list, so a
  // foldered app's marks carry the same per-window states as a pinned app's.
  readonly property var groupWindows: {
    var out = []
    if (!root) return out
    var seenEnt = []
    var seenAddr = []
    for (var a = 0; a < gitem.groupApps.length; a++) {
      var ent = root.entryForId(gitem.groupApps[a])
      if (!ent || seenEnt.indexOf(ent.appId) >= 0) continue
      seenEnt.push(ent.appId)
      var wins = ent.windowList || []
      for (var w = 0; w < wins.length; w++) {
        var win = wins[w]
        if (!win) continue
        // An id alias can make two members resolve to the same entry.
        if (win.address && seenAddr.indexOf(win.address) >= 0) continue
        if (win.address) seenAddr.push(win.address)
        out.push(win)
      }
    }
    return out
  }

  // Minimized windows live as preview tiles on the dock itself, so hover
  // surfaces list only what is actually on screen (same as an app's tooltip).
  readonly property var tooltipWindows: root ? root.visibleWindows(gitem.groupWindows) : []

  readonly property bool hasRunningApps: {
    if (!root) return false
    for (var a = 0; a < gitem.groupApps.length; a++) {
      var ent = root.entryForId(gitem.groupApps[a])
      if (ent && ent.running) return true
    }
    return false
  }

  // One of the group's apps holds the focus (app-id match including DockModel
  // aliases, or one of its windows does). The marks name the focused window
  // directly; this is the fallback for the row's unnamed case.
  readonly property bool hasFocusedMember: {
    if (!root) return false
    for (var a = 0; a < gitem.groupApps.length; a++) {
      var ent = root.entryForId(gitem.groupApps[a])
      if (!ent) continue
      if (root.activeId && DockModel.isAppMatch(ent.appId, root.activeId)) return true
      var wins = ent.windowList || []
      for (var w = 0; w < wins.length; w++) {
        if (wins[w] && wins[w].address && wins[w].address === root.activeWindowAddress) return true
      }
    }
    return false
  }

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
    NumberAnimation { duration: (gitem.motion ? gitem.motion.hover : 0); easing.type: Easing.OutQuad }
  }

  Item {
    id: iconSlot
    width: root ? root.iconSlot : 0
    height: root ? root.iconSlot : 0
    x: gitem.dropGap + (label.mirror ? gitem.labelExtra - label.lead : label.lead) + Math.round((gitem.width - gitem.dropGap - gitem.labelExtra - width) / 2)
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
          running: gitem.isDropTarget && !!gitem.motion && gitem.motion.oneShots
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
      BadgeMark {
        parent: tileFx.contentItem
        rootRef: gitem.rootRef
        anchorRef: tileFx.contentItem
        count: gitem.badgeCount
        rim: Color.bar.background
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

        // 2x2 Mini Icons Grid Preview. The grid keeps its full 2x2 size even
        // with one or two members, so they sit in the top row where a third
        // would join them instead of a single row centred in the tile.
        Grid {
          id: miniGrid
          visible: gitem.groupApps.length > 0
          anchors.centerIn: parent
          columns: 2
          rows: 2
          spacing: Style.space(2)
          // Without a frame the grid can use the whole tile.
          readonly property real cellSize: Math.round(iconContainer.width * (folderTile.tileStyle === "none" ? 0.46 : 0.36))
          width: cellSize * 2 + spacing
          height: width

          Repeater {
            model: gitem.groupApps.slice(0, 4)
            delegate: Item {
              id: miniCell
              readonly property real miniSize: miniGrid.cellSize
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
                tint: (root && label.plate && label.shown) ? root.plateIconTintColor : (root ? root.iconTintColor : Color.bar.text)
                // Same cell size as a full icon, so the minis match it.
                grid: root ? Math.round(root.iconGrid * miniCell.miniSize / Math.max(1, root.baseIconArt)) : 8
                outputScale: root ? root.outputScale : 1
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

  // The same indicator row an app carries, one mark per member window.
  // Wrapped in a band so the click area can size to the row without entering
  // the row's own layout.
  Item {
    id: indicatorBand
    anchors.horizontalCenter: iconSlot.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root ? root.markBottomMargin : 0
    width: indicatorRow.width
    height: indicatorRow.height
    // On a plate with side indicators the label draws these as a column.
    visible: (gitem.hasRunningApps || gitem.isOpen) && !label.sideMarks
    z: 2

    DockIndicatorRow {
      id: indicatorRow
      rootRef: gitem.rootRef
      markInk: (label.plate && label.shown) ? label.ink : "transparent"
      // On a plate the marks rise with it.
      transform: Translate { y: (label.plate && label.shown) ? label.rise : 0 }
      moveKey: (label.plate && label.shown) ? label.rise : 0
      windows: gitem.groupWindows
      running: gitem.hasRunningApps || gitem.isOpen
      focused: gitem.isOpen || gitem.hasFocusedMember
    }

    // One click on the marks toggles the app they stand for; hover still
    // reaches the tile beneath so its effects and tooltip keep working.
    MouseArea {
      id: indicatorHit
      anchors.fill: parent
      anchors.margins: -Style.space(3)
      enabled: gitem.indicatorAppId !== ""
      cursorShape: Qt.PointingHandCursor
      onWheel: function(wheel) { gitem.handlePreviewWheel(wheel) }

      onClicked: {
        gitem.clickPreviewOr(function() { if (root) root.activate(gitem.indicatorAppId) })
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

    onWheel: function(wheel) { gitem.handlePreviewWheel(wheel) }
    onContainsMouseChanged: if (!groupArea.containsMouse) gitem.previewIndex = -1

    onTapped: function(mouse) {
      var targetWin = root ? root.contentItemRef : null
      if (mouse.button === Qt.RightButton) {
        var mappedPos = targetWin ? gitem.mapToItem(targetWin, gitem.iconCenterX, 0) : null
        if (!mappedPos) return
        gitem.menuRequested(gitem.groupData, mappedPos.x, 0)
      } else {
        gitem.clickPreviewOr(function() {
          var centerPos = targetWin ? gitem.mapToItem(targetWin, gitem.iconCenterX, 0) : null
          if (!centerPos) return
          gitem.openGroupRequested(gitem.groupData, centerPos.x, centerPos.y)
        })
      }
    }
  }

  // Name beside the tile (DockLabel, policy in DockLabelLogic).
  DockLabel {
    id: label
    z: -1
    rootRef: gitem.rootRef
    folded: root ? root.fitHostRef.folds("group", true, false) : false
    kind: "group"
    name: gitem.groupName
    hovered: groupArea.containsMouse && !groupArea.dragging
    iconBox: iconSlot
    tileLead: gitem.dropGap
    slot: gitem.labelSlot
    marksFrom: indicatorRow
  }

  // Hover tooltip: the member windows as preview cards, like an app's.
  HoverTooltip {
    dockRoot: root
    text: Tr.tn("tooltip.groupApps", gitem.groupApps.length, gitem.groupApps.length === 1 ? "%1 (%2 app)" : "%1 (%2 apps)").arg(gitem.groupName).arg(gitem.groupApps.length)
    windows: gitem.tooltipWindows
    cycleIndex: gitem.previewIndex
    fallbackIcon: Quickshell.iconPath("folder", true)
    hovered: groupArea.containsMouse
    blocked: (!root || !root.showTooltips || root.activeAppGroupId !== "")
      || (root && !root.labelTooltipNeeded("group", gitem.tooltipWindows.length > 0, false, label.shortened))
    target: iconSlot
    // The name chip floats between this bubble and the bar; the preview
    // stacks above it in the clear band the name reserved.
    chipClear: label.overlay ? label.chipClear : 0
    showTooltips: root ? root.showTooltips : true
    tooltipDelay: root ? root.tooltipDelay : 450
    contextAppId: root ? root.contextAppId : ""
  }
}
