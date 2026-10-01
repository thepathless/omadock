import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

Item {
  id: cardWrapper

  property var rootRef: null
  readonly property var root: rootRef

  property alias dockCard: dockCard
  property alias cardHover: cardHover
  property alias dockHitbox: dockHitbox
  property alias hitboxHover: hitboxHover
  property alias row: row
  property alias pinnedRowRepeater: pinnedRowRepeater
  property alias minimizedTilesRepeater: minimizedTilesRepeater
  property alias foldersRepeater: foldersRepeater
  property alias drivesRepeater: drivesRepeater
  readonly property bool folderDropActive: folderDrop.containsDrag

  // Insert index among the pinned folders for a pointer at row x: before the
  // first folder whose icon centre lies right of it. The icon sits right of
  // any open gap, so moving through the gap keeps the same index.
  // The folder section of the row: from the folder divider on, or, with no
  // divider (no folders or drives yet, or nothing before them), the last
  // three quarters of a slot at the end of the row and beyond.
  function inPinZone(px) {
    if (folderSeparator.visible) return px >= folderSeparator.x - (root ? root.gapWidth : 0)
    if (foldersRepeater.count > 0) {
      var first = foldersRepeater.itemAt(0)
      if (first) return px >= first.x
    }
    return px >= row.width - (root ? root.iconSlot * 0.75 : 0)
  }

  function folderInsertIndex(px) {
    var n = foldersRepeater ? foldersRepeater.count : 0
    for (var i = 0; i < n; i++) {
      var it = foldersRepeater.itemAt(i)
      if (!it) continue
      var iconCenter = it.x + it.width - (root ? root.iconSlot : it.width) / 2
      if (px < iconCenter) return i
    }
    return n
  }

  // A drag pulled this far above the card takes the item off the dock.
  function offDockAt(my) {
    return root ? my < -(root.iconSlot * 0.75) : false
  }

  function handleDragMoved(aid, mx, my) {
    if (!root) return
    root.dropBeforeId = ""
    root.dropTargetAppId = ""
    root.dropTargetGroupId = ""
    root.dragPointerX = mx
    root.dragPointerY = my

    // Only a pin can be taken off; a running app that is not pinned stays.
    root.dragRemoveArmed = root.dragSourceGroupId === "" && DockModel.isPinned(root.pinnedIds, aid) && cardWrapper.offDockAt(my)
    if (root.dragRemoveArmed) return

    // Over the middle of a group: add to it. Over the middle of another
    // pinned app: make a group of the two. Otherwise a place in the run.
    var rx = mx - row.x
    var n = pinnedRowRepeater.count
    for (var i = 0; i < n; i++) {
      var slot = pinnedRowRepeater.itemAt(i)
      var it = slot ? slot.item : null
      if (!it) continue
      var centre = slot.x + slot.width / 2
      if (slot.isGroup) {
        if (Math.abs(rx - centre) < slot.width * 0.45) {
          root.dropTargetGroupId = it.groupId
          root.dropRowIndex = -1
          return
        }
      } else if (it.appId !== aid && Math.abs(rx - centre) < slot.width * 0.38) {
        root.dropTargetAppId = it.appId
        root.dropRowIndex = -1
        return
      }
    }

    var idx = cardWrapper.rowInsertIndex(rx)
    root.dropRowIndex = idx
    if (idx < 0) return
    root.dropIndicatorX = cardWrapper.rowIndicatorX(idx)
    // The first app at or after the drop, for moves that work in pin order.
    for (var j = idx; j < n; j++) {
      var s2 = pinnedRowRepeater.itemAt(j)
      if (s2 && !s2.isGroup && s2.item && s2.item.appId !== aid) {
        root.dropBeforeId = s2.item.appId
        break
      }
    }
  }

  // Insert index in the pinned run for a pointer at row x: before the first
  // item whose centre lies right of it, so past the end of the run (over the
  // running apps, say) means its end. -1 when the run is empty.
  function rowInsertIndex(rx) {
    var n = pinnedRowRepeater.count
    if (n === 0) return -1
    for (var i = 0; i < n; i++) {
      var slot = pinnedRowRepeater.itemAt(i)
      if (slot && rx < slot.x + slot.width / 2) return i
    }
    return n
  }

  function rowIndicatorX(idx) {
    var n = pinnedRowRepeater.count
    if (idx < n) return row.x + pinnedRowRepeater.itemAt(idx).x - row.spacing / 2 - Style.space(1)
    var last = pinnedRowRepeater.itemAt(n - 1)
    return row.x + last.x + last.width + row.spacing / 2 - Style.space(1)
  }

  function handleDragDropped(aid) {
    if (!root) return
    var dragId = root.dragAppId
    var targetGroupId = root.dropTargetGroupId
    var targetAppId = root.dropTargetAppId
    var beforeId = root.dropBeforeId
    var sourceGroupId = root.dragSourceGroupId
    var removeArmed = root.dragRemoveArmed
    var rowIdx = root.dropRowIndex

    root.dragAppId = ""
    root.dropBeforeId = ""
    root.dropTargetGroupId = ""
    root.dropTargetAppId = ""
    root.dropRowIndex = -1
    root.dragRemoveArmed = false

    if (dragId !== "" && removeArmed) {
      root.dragSourceGroupId = ""
      root.togglePin(dragId)
    } else if (dragId !== "") {
      if (sourceGroupId !== "") {
        if (targetGroupId === sourceGroupId) {
          root.dragSourceGroupId = ""
          root.syncVisibility()
          return
        }
        root.removeAppFromGroup(sourceGroupId, dragId)
      }

      if (targetGroupId !== "") {
        root.addAppToGroup(targetGroupId, dragId)
      } else if (targetAppId !== "" && targetAppId !== dragId) {
        root.createAppGroupFromDrop(targetAppId, dragId)
      } else {
        var isAlreadyPinned = Boolean(root.pinnedIds && root.pinnedIds.indexOf(dragId) >= 0)
        var rowNow = root.pinnedRow
        if (sourceGroupId !== "") {
          // Out of an open group: the group has just changed under the drag,
          // so place the app by pin order alone.
          root.setPinned(DockModel.reorderPinned(root.pinnedIds, dragId, beforeId))
        } else if (rowIdx >= 0 && (isAlreadyPinned || rowIdx < rowNow.length)) {
          // A pinned app moves within the run; a running one dropped before
          // any item of it gets pinned there. Groups keep their places.
          var from = -1
          for (var r = 0; r < rowNow.length; r++) {
            if (rowNow[r].kind === "app" && rowNow[r].appId === dragId) { from = r; break }
          }
          var nextRow
          if (from >= 0) {
            nextRow = DockModel.moveBefore(rowNow, from, rowIdx)
          } else {
            nextRow = rowNow.slice()
            nextRow.splice(rowIdx, 0, { kind: "app", appId: dragId })
          }
          if (nextRow !== rowNow) root.applyPinnedRow(nextRow)
        }
      }
      root.dragSourceGroupId = ""
    } else {
      root.dragSourceGroupId = ""
    }
    root.syncVisibility()
  }

  // ---------------------------------------------- folder and group drags

  function handleFolderDragStarted(path) {
    if (!root) return
    root.dragFolderPath = path
    root.dropFolderIndex = -1
    root.dragRemoveArmed = false
  }

  // Reorders within the folder section: from the gap before the first
  // folder to the gap after the last one.
  function handleFolderDragMoved(path, mx, my) {
    if (!root) return
    root.dragPointerX = mx
    root.dragPointerY = my
    root.dragRemoveArmed = cardWrapper.offDockAt(my)
    var n = foldersRepeater.count
    var first = n > 0 ? foldersRepeater.itemAt(0) : null
    var last = n > 0 ? foldersRepeater.itemAt(n - 1) : null
    var rx = mx - row.x
    if (root.dragRemoveArmed || !first || !last
        || rx < first.x - row.spacing || rx > last.x + last.width + row.spacing) {
      root.dropFolderIndex = -1
      return
    }
    var idx = cardWrapper.folderInsertIndex(rx)
    root.dropFolderIndex = idx
    root.dropIndicatorX = idx < n
      ? row.x + foldersRepeater.itemAt(idx).x - row.spacing / 2 - Style.space(1)
      : row.x + last.x + last.width + row.spacing / 2 - Style.space(1)
  }

  function handleFolderDragDropped(path) {
    if (!root) return
    var removeArmed = root.dragRemoveArmed
    var idx = root.dropFolderIndex
    root.dragFolderPath = ""
    root.dropFolderIndex = -1
    root.dragRemoveArmed = false
    if (removeArmed) root.toggleFolderPin(path, "", "")
    else if (idx >= 0) root.moveFolder(path, idx)
    root.syncVisibility()
  }

  // App groups move anywhere in the pinned run, among the pinned apps; an
  // accent line marks where the group lands.
  function handleGroupDragStarted(gid) {
    if (!root) return
    root.dragGroupId = gid
    root.dropRowIndex = -1
    root.dragRemoveArmed = false
  }

  function handleGroupDragMoved(gid, mx, my) {
    if (!root) return
    root.dragPointerX = mx
    root.dragPointerY = my
    root.dragRemoveArmed = cardWrapper.offDockAt(my)
    var idx = root.dragRemoveArmed ? -1 : cardWrapper.rowInsertIndex(mx - row.x)
    root.dropRowIndex = idx
    if (idx >= 0) root.dropIndicatorX = cardWrapper.rowIndicatorX(idx)
  }

  function handleGroupDragDropped(gid) {
    if (!root) return
    var removeArmed = root.dragRemoveArmed
    var idx = root.dropRowIndex
    root.dragGroupId = ""
    root.dropRowIndex = -1
    root.dragRemoveArmed = false
    if (removeArmed) root.removeAppGroup(gid)
    else if (idx >= 0) root.moveAppGroup(gid, idx)
    root.syncVisibility()
  }

  // Keyed models for the pinned run and the running apps (KeyedListModel):
  // a list replaced by an equal or slightly changed one keeps its delegates.
  KeyedListModel { id: pinnedRowModel }
  KeyedListModel { id: runningModel }

  Connections {
    target: cardWrapper.root
    function onPinnedRowKeysChanged() { pinnedRowModel.sync(cardWrapper.root.pinnedRowKeys) }
    function onRunningKeysChanged() { runningModel.sync(cardWrapper.root.runningKeys) }
  }

  Component.onCompleted: {
    if (!root) return
    pinnedRowModel.sync(root.pinnedRowKeys)
    runningModel.sync(root.runningKeys)
  }

  // Dimensions driven by dockCard
  width: dockCard.width
  height: dockCard.height

  anchors.bottom: parent ? parent.bottom : undefined
  anchors.bottomMargin: (root && root.dockVisible) ? Style.gapsOut : -(dockCard.height + Style.gapsOut + 10)

  x: {
    if (!parent) return 0
    if (root && root.alignment === "left") return Style.gapsOut * 2
    if (root && root.alignment === "right") return parent.width - width - (Style.gapsOut * 2)
    return Math.round((parent.width - width) / 2)
  }

  Behavior on anchors.bottomMargin {
    NumberAnimation {
      duration: (root && root.dockVisible) ? 300 : 260
      easing.type: (root && root.dockVisible) ? Easing.OutCubic : Easing.InCubic
    }
  }

  opacity: (root && root.dockVisible) ? 1 : 0
  Behavior on opacity {
    NumberAnimation {
      duration: (root && root.dockVisible) ? 220 : 260
      easing.type: (root && root.dockVisible) ? Easing.OutQuad : Easing.InQuad
    }
  }

  // Expanded interactive hitbox: eliminates dead gaps below dockCard and adds generous hysteresis
  Item {
    id: dockHitbox
    x: -Style.space(24)
    y: (root && root.dockVisible) ? -Style.space(18) : 0
    width: dockCard.width + Style.space(48)
    height: dockCard.height + ((root && root.dockVisible) ? (Style.gapsOut + Style.space(18)) : 0)
    z: -1

    HoverHandler {
      id: hitboxHover
      onHoveredChanged: if (root) root.syncVisibility()
    }

    // Folders dragged in from a file manager get pinned as stacks, at the
    // spot the pointer picks among the pinned folders. Dropping on an app
    // icon (its own DropArea, above this one) opens the item instead, and
    // that comes first: pinning only happens in the folder section, after
    // the pointer has rested there for pinDwell. Anywhere else the drag is
    // refused, so a folder let go over the apps is never pinned by accident.
    DropArea {
      id: folderDrop
      anchors.fill: parent
      keys: ["text/uri-list"]

      function track(drag) {
        if (!root) return
        var rx = folderDrop.mapToItem(row, drag.x, drag.y).x
        if (cardWrapper.inPinZone(rx)) {
          root.dropInsertIndex = cardWrapper.folderInsertIndex(rx)
          if (!root.dropPinArmed && !pinDwell.running) pinDwell.restart()
          drag.accepted = true
        } else {
          pinDwell.stop()
          root.dropPinArmed = false
          drag.accepted = false
        }
      }

      onEntered: function(drag) {
        if (root) {
          root.externalDragOver = true
          root.previewDraggedFolder(drag.urls)
        }
        folderDrop.track(drag)
      }
      onPositionChanged: function(drag) { folderDrop.track(drag) }
      onExited: {
        pinDwell.stop()
        if (root) root.externalDragOver = false
      }
      onDropped: function(drop) {
        pinDwell.stop()
        if (!root) return
        var armed = root.dropPinArmed && root.dropCandidatePath !== ""
        root.externalDragOver = false
        if (armed) {
          root.pinDroppedFolders(drop.urls)
          drop.accept(Qt.LinkAction)
        } else {
          drop.accepted = false
        }
      }
    }

    // How long the pointer rests in the folder section before the gap opens
    // and a drop would pin.
    Timer {
      id: pinDwell
      interval: 450
      onTriggered: if (root) root.dropPinArmed = true
    }
  }

  // Horizontal extents of the background panels, in card coordinates. One
  // panel spans the card; with split sections each visible separator cuts
  // it, and every panel reaches the card inset past its outer items, as the
  // card itself does. Each cut snaps its left edge to the window's device
  // pixel grid and adds the gap snapped once, so every gap comes out the
  // same number of device pixels wide; snapping both edges on their own
  // let neighbouring gaps differ by a pixel.
  readonly property var segments: {
    var full = [{ x: 0, width: dockCard.width }]
    if (!root || !root.splitSections) return full
    var dpr = dockCard.dpr
    var origin = cardWrapper.x + dockCard.x
    var inset = dockCard.contentLeftInset
    var gap = Math.max(1, Math.round(root.sectionGap * dpr)) / dpr
    var seps = [leftTileSeparator, separator, folderSeparator, driveSeparator]
    var out = []
    var start = 0
    for (var i = 0; i < seps.length; i++) {
      var sep = seps[i]
      if (!sep.visible) continue
      var end = Math.round((row.x + sep.x - row.spacing + inset + origin) * dpr) / dpr - origin
      out.push({ x: start, width: Math.max(0, end - start) })
      start = end + gap
    }
    out.push({ x: start, width: Math.max(0, dockCard.width - start) })
    return out
  }

  // Card shadow: each panel's own shape (same radius), blurred and dropped a
  // little, so a square card casts a square-ish shadow instead of a soft
  // oval. Only drawn under a visible background; without one, each icon
  // casts its own shadow instead (see DockIconArt). All shadows sit under
  // all panels, so one panel's shadow never darkens its neighbour.
  // The model is a count, not the segment list: the list is rebuilt whenever
  // a separator moves, and delegates should follow it, not be recreated.
  Repeater {
    model: cardWrapper.segments.length
    delegate: Item {
      id: cardShadow
      readonly property var segment: cardWrapper.segments[index] || { x: 0, width: 0 }
      readonly property real spread: Style.space(12)
      visible: root ? (root.showShadow && root.showBackground && root.shadowStrength > 0) : true
      // Follows the card out of view; a blur left behind would hang on screen
      // after the dock has gone.
      opacity: cardWrapper.opacity
      x: dockCard.x + segment.x - spread
      y: dockCard.y - spread + Style.space(3)
      width: segment.width + spread * 2
      height: dockCard.height + spread * 2
      z: 0
      layer.enabled: true
      layer.effect: MultiEffect {
        blurEnabled: true
        blur: 1.0
        blurMax: 20
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: cardShadow.spread
        radius: dockCard.radius
        color: Qt.rgba(0, 0, 0, root ? root.shadowStrength : 0.4)
      }
    }
  }

  BorderSurface {
    id: dockCard

    // Whole device pixels for the rim and the padding: at a fractional scale
    // (1.5) a 1.5 px rim puts everything inside the card a fraction of a pixel
    // off the grid, and the unsmoothed square indicators then lose or gain a
    // row depending on the border setting.
    readonly property real dpr: root ? root.outputScale : 1
    function devSnap(v) { return v <= 0 ? 0 : Math.max(1, Math.round(v * dockCard.dpr)) / dockCard.dpr }
    readonly property real effectiveBorderWidth: dockCard.devSnap(root ? root.borderWidth : 1.5)

    // The panels below paint the fill and the rim. The card keeps a clear
    // rim of the same width, so its content insets do not depend on how many
    // panels there are.
    color: "transparent"
    borderSpec: (root && !root.showBorder)
      ? Border.none()
      : Border.flat("transparent", dockCard.effectiveBorderWidth)
    radius: root ? root.cardRadius(height) : Style.cornerRadius
    padding: dockCard.devSnap(Style.space(5))
    z: 1

    Repeater {
      model: cardWrapper.segments.length
      delegate: DockSurface {
        readonly property var segment: cardWrapper.segments[index] || { x: 0, width: 0 }
        rootRef: cardWrapper.rootRef
        borderWidth: dockCard.effectiveBorderWidth
        x: segment.x
        width: segment.width
        height: dockCard.height
      }
    }

    HoverHandler {
      id: cardHover
      onHoveredChanged: if (root) root.syncVisibility()
    }

    width: row.implicitWidth + contentLeftInset + contentRightInset
    height: row.implicitHeight + contentTopInset + contentBottomInset

    // Click on card padding dismisses context menu
    MouseArea {
      id: cardArea
      anchors.fill: parent
      z: 0
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (!root) return
        if (mouse.button === Qt.RightButton) {
          // Right-click on the dock background opens the dock menu too, so it
          // stays reachable when the Omarchy button is hidden.
          var pt = root.contentItemRef ? cardArea.mapToItem(root.contentItemRef, mouse.x, 0) : null
          root.openDockSettingsMenu(pt ? pt.x : mouse.x, 0)
          return
        }
        if (root.contextAppId !== "") root.closeContext()
      }
      onReleased: {
        if (root && root.dragAppId !== "") {
          root.dragAppId = ""
          root.dropBeforeId = ""
          root.dropTargetAppId = ""
          root.dropTargetGroupId = ""
          root.dragSourceGroupId = ""
          root.syncVisibility()
        }
      }
    }

    Row {
      id: row
      z: 1
      spacing: Style.space(root ? root.itemSpacing : 4)

      x: dockCard.contentLeftInset
      y: dockCard.contentTopInset

      DockIconButton {
        rootRef: cardWrapper.rootRef
        visible: root ? root.showAppsButton : true
        homeCenter: root ? root.slotHomeCenter(0, 0, false) : 0
        glyph: "\ue900"
        glyphColor: root ? root.dockForeground : Color.bar.text
        tooltip: "Omarchy"
        onPressed: Quickshell.execDetached(["omarchy-menu", "toggle", "root"])
        onMiddleClicked: Quickshell.execDetached(["omarchy-launch-terminal"])
        onWheelScrolled: function(dir) { if (root) root.cycleWorkspace(dir) }
        onMenuRequested: function(cx, cy) {
          if (root) root.openDockSettingsMenu(cx, cy)
        }
      }

      // Pinned apps and app groups share one run (root.pinnedRow): each
      // group stands where its "before" app puts it.
      Repeater {
        id: pinnedRowRepeater
        model: pinnedRowModel
        delegate: Loader {
          id: rowSlot
          required property string key
          required property int index
          readonly property bool isGroup: key.indexOf("group:") === 0
          // Looked up by key; kept through the moment a removed key has left
          // the lookup but not yet the model.
          property var modelData: ({})
          Binding on modelData {
            value: root ? root.pinnedRowByKey[rowSlot.key] : undefined
            when: !!(root && root.pinnedRowByKey[rowSlot.key])
            restoreMode: Binding.RestoreNone
          }
          readonly property real home: root ? root.slotHomeCenter(root.appsSlots + index, root.appsSlots + index, false) : 0
          sourceComponent: isGroup ? groupSlotComp : appSlotComp
          // A zoomed icon raises itself over its neighbours; in the Row that
          // takes the slot's z.
          z: item ? item.z : 0

          Component {
            id: appSlotComp
            DockItem {
              readonly property var entry: rowSlot.modelData.entry || ({})
              rootRef: cardWrapper.rootRef
              appId: entry.appId || ""
              name: entry.name || ""
              icon: entry.icon || ""
              running: !!entry.running
              windows: entry.windows || 0
              windowList: entry.windowList || []
              homeCenter: rowSlot.home
              pinned: true
              active: root ? (entry.appId === root.activeId) : false
              onActivateRequested: function(aid) { if (root) root.activate(aid) }
              onNewWindowRequested: function(aid) { if (root) root.launchApp(aid, null) }
              onMenuRequested: function(aid, cx, cy) { if (root) root.openContext(aid, cx, cy) }
              onWheelScrolled: function(aid, dir) { if (root) root.cycleApp(aid, dir) }
              onDragStarted: function(aid) {
                if (root) {
                  root.dragAppId = aid
                  root.dropBeforeId = ""
                  root.dropTargetAppId = ""
                  root.dropTargetGroupId = ""
                  root.dropRowIndex = -1
                }
              }
              onDragMoved: function(aid, mx, my) { cardWrapper.handleDragMoved(aid, mx, my) }
              onDragDropped: function(aid) { cardWrapper.handleDragDropped(aid) }
            }
          }

          Component {
            id: groupSlotComp
            DockAppGroupItem {
              rootRef: cardWrapper.rootRef
              groupData: rowSlot.modelData.group || ({})
              homeCenter: rowSlot.home
              onOpenGroupRequested: function(gdata, cx, cy) {
                if (root) root.openAppGroup(gdata, cx, cy)
              }
              onMenuRequested: function(gdata, cx, cy) {
                if (root) root.openAppGroupContext(gdata, cx, cy)
              }
              onDragStarted: function(gid) { cardWrapper.handleGroupDragStarted(gid) }
              onDragMoved: function(gid, mx, my) { cardWrapper.handleGroupDragMoved(gid, mx, my) }
              onDragDropped: function(gid) { cardWrapper.handleGroupDragDropped(gid) }
            }
          }
        }
      }

      // Divider between pinned apps and the minimized-tile section.
      Item {
        id: leftTileSeparator
        visible: root ? root.hasLeftTileSeparator : false
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root ? root.iconCenterOffset : 0
        width: root ? root.separatorWidth : Style.space(1)
        height: root ? (root.iconSize * 0.7) : 24

        // The line, centred in its slot. With split sections the slot is
        // the gap between two panels and no line is drawn.
        Rectangle {
          visible: !(root && root.splitSections)
          anchors.centerIn: parent
          width: Style.space(1)
          height: parent.height
          color: root ? root.dividerColor : Util.alpha(Color.bar.text, 0.25)
        }
      }

      // ------------------------------------------ minimized window tiles
      // macOS-style section: every parked window shows up as a small live
      // preview tile. Click a tile to bring that exact window back.
      Repeater {
        id: minimizedTilesRepeater
        model: root ? root.tileModel : []

        delegate: PreviewTile {
          rootRef: cardWrapper.rootRef
          tileData: modelData
          tileIndex: index
        }
      }

      Item {
        id: separator
        visible: root ? root.hasSeparator : false
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root ? root.iconCenterOffset : 0
        width: root ? root.separatorWidth : Style.space(1)
        height: root ? (root.iconSize * 0.7) : 24

        // The line, centred in its slot. With split sections the slot is
        // the gap between two panels and no line is drawn.
        Rectangle {
          visible: !(root && root.splitSections)
          anchors.centerIn: parent
          width: Style.space(1)
          height: parent.height
          color: root ? root.dividerColor : Util.alpha(Color.bar.text, 0.25)
        }
      }

      Repeater {
        id: runningRepeater
        model: runningModel
        delegate: DockItem {
          id: runningDockItem
          required property string key
          required property int index
          // Looked up by key, as in the pinned run.
          property var entry: ({})
          Binding on entry {
            value: root ? root.runningByKey[runningDockItem.key] : undefined
            when: !!(root && root.runningByKey[runningDockItem.key])
            restoreMode: Binding.RestoreNone
          }
          rootRef: cardWrapper.rootRef
          appId: entry.appId || ""
          name: entry.name || ""
          icon: entry.icon || ""
          running: !!entry.running
          windows: entry.windows || 0
          windowList: entry.windowList || []
          // Wave geometry must count only icons that actually render — a
          // hidden (fully-tiled) entry occupies zero width in the Row.
          readonly property int visibleIdx: root ? root.visibleRunningSlotBefore(index) : 0
          homeCenter: root ? root.slotHomeCenter(
            root.appsSlots + root.pinnedSection.length + root.groupSlots + (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + root.tileElements + visibleIdx,
            root.appsSlots + root.pinnedSection.length + root.groupSlots + visibleIdx,
            (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0),
            root.tilesFixedWidth) : 0
          pinned: false
          active: root ? (entry.appId === root.activeId) : false
          onActivateRequested: function(aid) { if (root) root.activate(aid) }
          onNewWindowRequested: function(aid) { if (root) root.launchApp(aid, null) }
          onMenuRequested: function(aid, cx, cy) { if (root) root.openContext(aid, cx, cy) }
          onWheelScrolled: function(aid, dir) { if (root) root.cycleApp(aid, dir) }
          onDragStarted: function(aid) {
            if (root) {
              root.dragAppId = aid
              root.dropBeforeId = ""
              root.dropTargetAppId = ""
              root.dropTargetGroupId = ""
            }
          }
          onDragMoved: function(aid, mx, my) { cardWrapper.handleDragMoved(aid, mx, my) }
          onDragDropped: function(aid) { cardWrapper.handleDragDropped(aid) }

          // When an unpinned app has ALL its windows minimized and tiles are
          // showing, the tile section already represents it — hide the icon
          // slot entirely so only the tile (with hollow dot) is visible.
          // Live resolver: same source as the running-dot indicator, so the
          // icon can never outlive its own tile after a lagged park.
          readonly property bool isFullyTiled: (root && root.showMinimizedTiles)
            && DockModel.allWindowsMinimized(entry.windowList || [], root ? root.liveWsNameOf : null, root ? root.minimizedWorkspace : "special:minimized")
          visible: !isFullyTiled
        }
      }

      Item {
        id: folderSeparator
        visible: root ? root.hasFolderSeparator : false
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root ? root.iconCenterOffset : 0
        width: root ? root.separatorWidth : Style.space(1)
        height: root ? (root.iconSize * 0.7) : 24

        // The line, centred in its slot. With split sections the slot is
        // the gap between two panels and no line is drawn.
        Rectangle {
          visible: !(root && root.splitSections)
          anchors.centerIn: parent
          width: Style.space(1)
          height: parent.height
          color: root ? root.dividerColor : Util.alpha(Color.bar.text, 0.25)
        }
      }

      Repeater {
        id: foldersRepeater
        model: root ? root.pinnedFolders : []
        delegate: DockFolderItem {
          rootRef: cardWrapper.rootRef
          folderPath: modelData.path
          name: modelData.name || "Folder"
          icon: modelData.icon || DockModel.folderIconFor(modelData.path, "")
          slotIndex: index
          homeCenter: root ? root.slotHomeCenter(
            root.appsSlots + root.pinnedSection.length + root.groupSlots + (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + root.tileElements + root.visibleRunningCount + (root.hasFolderSeparator ? 1 : 0) + index,
            root.appsSlots + root.pinnedSection.length + root.groupSlots + root.visibleRunningCount + index,
            (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + (root.hasFolderSeparator ? 1 : 0),
            root.tilesFixedWidth) : 0
          onOpenStackRequested: function(fpath, fname, cx, cy) {
            if (root) root.openFolderStack(fpath, fname, cx)
          }
          onMenuRequested: function(fpath, fname, cx, cy) {
            if (root) root.openFolderContext(fpath, fname, cx, cy)
          }
          onDragStarted: function(fpath) { cardWrapper.handleFolderDragStarted(fpath) }
          onDragMoved: function(fpath, mx, my) { cardWrapper.handleFolderDragMoved(fpath, mx, my) }
          onDragDropped: function(fpath) { cardWrapper.handleFolderDragDropped(fpath) }
        }
      }

      // Drop gap after the last pinned folder (see DockFolderItem.gapWidth).
      DropGhost {
        id: trailingDropGap
        rootRef: cardWrapper.rootRef
        readonly property bool open: root ? (root.dropPreviewPath !== "" && root.dropInsertIndex >= foldersRepeater.count) : false
        width: open && root ? root.iconSlot : 0
        height: root ? root.iconSlot : 0
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }

      Item {
        id: driveSeparator
        visible: root ? root.hasDriveSeparator : false
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root ? root.iconCenterOffset : 0
        width: root ? root.separatorWidth : Style.space(1)
        height: root ? (root.iconSize * 0.7) : 24

        // The line, centred in its slot. With split sections the slot is
        // the gap between two panels and no line is drawn.
        Rectangle {
          visible: !(root && root.splitSections)
          anchors.centerIn: parent
          width: Style.space(1)
          height: parent.height
          color: root ? root.dividerColor : Util.alpha(Color.bar.text, 0.25)
        }
      }

      Repeater {
        id: drivesRepeater
        model: (root && root.showRemovableDrives) ? root.mountedDrives : []
        delegate: DockDriveItem {
          rootRef: cardWrapper.rootRef
          dev: modelData.dev || ""
          mountpoint: modelData.mountpoint || ""
          name: modelData.name || "USB Drive"
          size: modelData.size || ""
          space: modelData.space || ""
          fstype: modelData.fstype || ""
          icon: modelData.icon || "drive-removable-media"
          homeCenter: root ? root.slotHomeCenter(
            root.appsSlots + root.pinnedSection.length + root.groupSlots + (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + root.tileElements + root.visibleRunningCount + (root.hasFolderSeparator ? 1 : 0) + root.pinnedFolders.length + (root.hasDriveSeparator ? 1 : 0) + index,
            root.appsSlots + root.pinnedSection.length + root.groupSlots + root.visibleRunningCount + root.pinnedFolders.length + index,
            (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + (root.hasFolderSeparator ? 1 : 0) + (root.hasDriveSeparator ? 1 : 0),
            root.tilesFixedWidth) : 0
          onOpenStackRequested: function(fpath, fname, cx, cy) {
            if (root) root.openFolderStack(fpath, fname, cx)
          }
          onMenuRequested: function(d, mp, n, s, cx, cy) {
            if (root) root.openDriveContext(d, mp, n, s, cx, cy)
          }
        }
      }
    }

    // Outline while a drag from outside hovers the dock (see folderDrop).
    Rectangle {
      anchors.fill: parent
      visible: root ? root.externalDragOver : false
      color: Util.alpha(Color.accent, 0.08)
      radius: dockCard.radius
      border.color: Color.accent
      border.width: 2
      z: 20
    }

    // Drop indicator line
    Rectangle {
      visible: root ? (!root.dragRemoveArmed
        && ((root.dragAppId !== "" && root.dropTargetAppId === "" && root.dropTargetGroupId === "" && root.dropRowIndex >= 0)
          || (root.dragFolderPath !== "" && root.dropFolderIndex >= 0)
          || (root.dragGroupId !== "" && root.dropRowIndex >= 0))) : false
      x: root ? root.dropIndicatorX : 0
      anchors.verticalCenter: row.verticalCenter
      width: Style.space(2)
      height: root ? (root.iconSize + Style.space(4)) : 36
      radius: 1
      color: Color.accent
      z: 10
    }

    // Over the pointer while a drag is pulled off the dock: letting go here
    // takes the item away. Styled like the hover tooltips.
    BorderSurface {
      visible: root ? root.dragRemoveArmed : false
      z: 300
      color: Color.tooltip.background
      borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
      radius: Style.cornerRadius
      padding: Style.space(4)
      width: removeLabel.implicitWidth + contentLeftInset + contentRightInset
      height: removeLabel.implicitHeight + contentTopInset + contentBottomInset
      x: Math.round((root ? root.dragPointerX : 0) - width / 2)
      y: Math.round((root ? root.dragPointerY : 0) - height - Style.space(16))

      Text {
        id: removeLabel
        anchors.centerIn: parent
        text: root && root.dragGroupId !== "" ? "Remove group" : "Unpin"
        textFormat: Text.PlainText
        color: Color.tooltip.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
