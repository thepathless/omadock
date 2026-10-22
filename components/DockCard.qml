import QtQuick 6.11
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui
import "logic"
import "../DockModel.js" as DockModel
import "../DockLabels.js" as DockLabels
import "../DockLayout.js" as DockLayout
import "../DockKeys.js" as DockKeys

Item {
  id: cardWrapper

  property var rootRef: null
  readonly property var root: rootRef
  readonly property var motion: root ? root.motion : null
  readonly property var folderSeparatorRef: rightRow.folderSeparator
  readonly property var separatorRef: separator
  readonly property var rightRowRef: rightRow

  property alias dockCard: dockCard
  property alias cardHover: cardHover
  property alias dockHitbox: dockHitbox
  property alias hitboxHover: hitboxHover
  property alias row: row
  property alias pinnedRowRepeater: pinnedRowRepeater
  property alias minimizedTilesRepeater: minimizedTilesRepeater
  readonly property var foldersRepeater: rightRow.foldersRepeater
  readonly property var drivesRepeater: rightRow.drivesRepeater
  property alias runningRepeater: runningRepeater
  readonly property bool folderDropActive: folderDrop.containsDrag
  // The card's box when it spans the window (panel, or a spread dock); null
  // while it hugs its icons. innerWidth is the room for the row inside it.
  readonly property var stretch: (root && parent) ? DockLayout.stretchedBox(root.placement, parent.width, Style.gapsOut * 2) : null
  readonly property real innerWidth: dockCard.width - dockCard.contentLeftInset - dockCard.contentRightInset
  // Label plates keep their edges on whole device pixels (the floating card
  // snaps its x for them).
  readonly property real plateDpr: (root && root.labelPlates) ? root.outputScale : 0
  readonly property real rowOffset: (root && stretch) ? DockLayout.rowOffset(root.placement.align, innerWidth, row.implicitWidth, plateDpr) : 0
  // Both sides: how far the right group rests past a packed row, from the
  // resting widths, so the magnification wave never measures itself. The
  // gap and the spacing after it together take the card's free width.
  readonly property real spreadShift: (root && root.placement.align === "spread")
    ? DockLayout.spreadHomeShift(innerWidth, (root.fitHostRef.plan.overflowFrom >= 0) ? root.fitHostRef.plan.rest : root.baseRowWidth + DockLabels.extrasTotal(root.labelExtras)) : 0
  // Which label plates stand at their panel's edge, by label slot
  // (DockLabels.plateEdges): the row's sections in order, cut where split
  // sections cut the card into panels (as segments does).
  readonly property var plateEdges: (root && root.labelPlates) ? DockLabels.plateEdges([
    { n: root.fitHostRef.shown.button, labelled: true, cut: false },
    { n: root.fitHostRef.shown.pinned, labelled: true, cut: false },
    { n: root.fitHostRef.shown.tiles, labelled: false, cut: root.placement.split && root.hasLeftTileSeparator },
    { n: root.fitHostRef.shown.running, labelled: true, cut: root.placement.split && root.hasSeparator },
    { n: root.fitHostRef.shown.folders, labelled: true, cut: root.placement.split && (root.hasFolderSeparator || root.placement.align === "spread") },
    { n: root.fitHostRef.shown.drives, labelled: true, cut: root.placement.split && root.hasDriveSeparator },
    // The "»" tile ends the row (DockOverflowTile).
    { n: root.fitHostRef.plan.overflowFrom >= 0 ? 1 : 0, labelled: true, cut: false }
  ]) : []
  // Where the accent line of a drag inside the dock stands (DropGap): the
  // insert index in the pinned run or among the folders, -1 for none.
  // A drag held over a group or an app keeps its gap where it was, so
  // nothing moves while it is aimed there (DockLift.dwell).
  readonly property int dropLineRow: (root && !root.dragRemoveArmed && root.dropRowIndex >= 0
    && (root.dragAppId !== "" || root.dragGroupId !== "" || cardWrapper.gridDragHere))
    ? root.dropRowIndex : -1
  // An app dragged out of Omarchy's app grid is over this dock (AppGridHost).
  readonly property bool gridDragHere: !!root && !!root.sharedState && root.sharedState.appGrid.dragScreen !== ""
    && !!root.dockScreen && root.sharedState.appGrid.dragScreen === String(root.dockScreen.name || "")
  readonly property int dropLineFolder: (root && !root.dragRemoveArmed && root.dragFolderPath !== "") ? root.dropFolderIndex : -1

  DockDragLogic { id: dragLogic }

  // The RowSlots of a Repeater's live rows (not leaving, not hidden), in
  // order: the drag logic and itemGeometry measure these, never a row on its
  // way out. A slot's x and width are in the row's coordinates; its element
  // is slot.child.
  function liveSlots(repeater) {
    var out = []
    for (var i = 0; i < (repeater ? repeater.count : 0); i++) {
      var s = repeater.itemAt(i)
      if (s && !s.leaving && s.shown !== false && s.child) out.push(s)
    }
    return out
  }

  // The live RowSlot with this liftKey, in the pinned run, the running apps
  // or the folders; null when there is none.
  function slotByLiftKey(key) {
    var reps = [pinnedRowRepeater, runningRepeater, rightRow.foldersRepeater]
    for (var r = 0; r < reps.length; r++) {
      for (var i = 0; i < (reps[r] ? reps[r].count : 0); i++) {
        var s = reps[r].itemAt(i)
        if (s && !s.leaving && s.liftKey === key) return s
      }
    }
    return null
  }

  function liftOf() { return dragLogic.liftOf(root, cardWrapper) }

  function inPinZone(px) { return dragLogic.inPinZone(root, cardWrapper, px) }

  function folderInsertIndex(px) { return dragLogic.folderInsertIndex(root, cardWrapper, px) }

  function offDockAt(my) { return dragLogic.offDockAt(root, cardWrapper, my) }

  function overRunningAt(rx) { return dragLogic.overRunningAt(root, cardWrapper, rx) }

  function handleDragMoved(aid, mx, my) { return dragLogic.handleDragMoved(root, cardWrapper, aid, mx, my) }

  function rowInsertIndex(rx) { return dragLogic.rowInsertIndex(root, cardWrapper, rx) }


  function handleDragDropped(aid) { return dragLogic.handleDragDropped(root, cardWrapper, aid) }

  // ---------------------------------------------- folder and group drags

  function handleFolderDragStarted(path) { return dragLogic.handleFolderDragStarted(root, cardWrapper, path) }

  function handleFolderDragMoved(path, mx, my) { return dragLogic.handleFolderDragMoved(root, cardWrapper, path, mx, my) }

  function handleFolderDragDropped(path) { return dragLogic.handleFolderDragDropped(root, cardWrapper, path) }

  function handleGroupDragStarted(gid) { return dragLogic.handleGroupDragStarted(root, cardWrapper, gid) }

  function handleGroupDragMoved(gid, mx, my) { return dragLogic.handleGroupDragMoved(root, cardWrapper, gid, mx, my) }

  function handleGroupDragDropped(gid) { return dragLogic.handleGroupDragDropped(root, cardWrapper, gid) }

  // Keyed models for the pinned run and the running apps (KeyedListModel):
  // a list replaced by an equal or slightly changed one keeps its delegates.
  KeyedListModel { id: pinnedRowModel; exitMs: cardWrapper.root ? cardWrapper.root.motion.base : 0 }
  KeyedListModel { id: runningModel; exitMs: cardWrapper.root ? cardWrapper.root.motion.base : 0 }
  // Minimized tiles, keyed by window (or by app for a grouped tile).
  KeyedListModel { id: tileRowModel; exitMs: cardWrapper.root ? cardWrapper.root.motion.base : 0 }
  readonly property var tileList: root ? root.tileModel : []
  readonly property var tileByKey: {
    var m = {}
    for (var i = 0; i < tileList.length; i++) m[DockKeys.tileKey(tileList[i])] = tileList[i]
    return m
  }
  onTileListChanged: tileRowModel.sync(tileList.map(DockKeys.tileKey))

  Connections {
    target: cardWrapper.root
    function onPinnedRowKeysChanged() { pinnedRowModel.sync(cardWrapper.root.pinnedRowKeys) }
    function onRunningKeysChanged() { runningModel.sync(cardWrapper.root.runningKeys) }
  }

  Component.onCompleted: {
    if (!root) return
    pinnedRowModel.sync(root.pinnedRowKeys)
    runningModel.sync(root.runningKeys)
    tileRowModel.sync(tileList.map(DockKeys.tileKey))
  }

  // Dimensions driven by dockCard
  width: dockCard.width
  height: dockCard.height

  // With shadows on, the card lifts by the room the drop shadow needs below
  // it (the gapsOut margin the layout already models); without one it sits
  // where it always has. The panel's reserved band carries the same lift
  // (Dock.qml exclusiveZone), so the card's top edge never crosses into it.
  readonly property real shadowRoom: (root && !root.placement.panel && root.showShadow && root.showBackground && root.shadowStrength > 0) ? Style.space(5) : 0
  anchors.bottom: parent ? parent.bottom : undefined
  anchors.bottomMargin: (root && root.dockVisible) ? root.edgeGap + cardWrapper.shadowRoom : -(dockCard.height + (root ? root.edgeGap : 0) + cardWrapper.shadowRoom + 10)
  transformOrigin: Item.Bottom

  x: {
    if (!parent) return 0
    if (cardWrapper.stretch) return cardWrapper.stretch.x
    var ax = DockLabels.anchoredX(parent.width, width, Style.gapsOut * 2, root ? root.placement.align : "center", 0)
    // Plate rows start on a whole device pixel, so every plate edge does.
    return (root && root.labelPlates) ? DockLabels.gridRound(ax, root.outputScale) : ax
  }

  // Autohide: slides and fades at Full; at Reduced it only fades, the card
  // moving off screen once the fade is over (and back before it fades in);
  // Off is instant.
  // The direction (showing: margin >= 0, opacity 1) is read from each
  // Behavior's target, set before its animation starts; bound to
  // dockVisible the easing and the pause could start with the old values.
  Behavior on anchors.bottomMargin {
    id: marginMotion
    enabled: !!cardWrapper.motion && cardWrapper.motion.fade
    SequentialAnimation {
      PauseAnimation {
        duration: (cardWrapper.motion && !cardWrapper.motion.layout && marginMotion.targetValue < 0) ? cardWrapper.motion.base : 0
      }
      NumberAnimation {
        duration: (cardWrapper.motion && cardWrapper.motion.layout) ? cardWrapper.motion.slow : 0
        easing.type: marginMotion.targetValue >= 0 ? Easing.OutCubic : Easing.InCubic
      }
    }
  }

  opacity: (root && root.dockVisible) ? 1 : 0
  Behavior on opacity {
    id: opacityMotion
    enabled: !!cardWrapper.motion && cardWrapper.motion.fade
    NumberAnimation {
      duration: cardWrapper.motion ? cardWrapper.motion.base : 0
      easing.type: opacityMotion.targetValue > 0.5 ? Easing.OutCubic : Easing.InCubic
    }
  }

  // Expanded interactive hitbox: eliminates dead gaps below dockCard and adds generous hysteresis
  Item {
    id: dockHitbox
    x: (root && root.placement.panel) ? 0 : -Style.space(24)
    y: (root && root.dockVisible) ? -Style.space(18) : 0
    width: dockCard.width + ((root && root.placement.panel) ? 0 : Style.space(48))
    height: dockCard.height + ((root && root.dockVisible) ? (root.edgeGap + Style.space(18)) : 0)
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
    if (!root || !root.placement.split) return full
    var dpr = dockCard.dpr
    var origin = cardWrapper.x + dockCard.x
    var inset = dockCard.contentLeftInset
    var gap = Math.max(1, Math.round(root.sectionGap * dpr)) / dpr
    var snap = function(v) { return Math.round((v + origin) * dpr) / dpr - origin }
    // Each cut: the row x of the item the panel before it ends at and, for
    // the Both sides gap, where the next panel starts.
    var cuts = []
    if (leftTileSeparator.visible) cuts.push({ at: leftTileSeparator.x })
    if (separator.visible) cuts.push({ at: separator.x })
    var fsep = rightRow.folderSeparator
    var dsep = rightRow.driveSeparator
    if (spreadGap.visible) cuts.push({ at: spreadGap.x, next: rightRow.x + (fsep.visible ? fsep.x + fsep.width + row.spacing : 0) })
    else if (fsep.visible) cuts.push({ at: rightRow.x + fsep.x })
    if (dsep.visible) cuts.push({ at: rightRow.x + dsep.x })
    var out = []
    var start = 0
    for (var i = 0; i < cuts.length; i++) {
      var end = snap(row.x + cuts[i].at - row.spacing + inset)
      out.push({ x: start, width: Math.max(0, end - start) })
      start = cuts[i].next !== undefined ? snap(row.x + cuts[i].next - inset) : end + gap
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
  //
  // Room for the halo is asymmetric on purpose. A blur only fades out inside
  // its own texture, so the padding wants to exceed the blur radius or the
  // halo ends in a hard edge; above and beside the card there is room (the
  // window's headroom and its full width), and below it the card carries its
  // own shadowRoom margin. The body therefore drops into that room and its
  // texture stops at the window edge exactly: the shadow fills the margin
  // instead of being sliced off mid-blur.
  Repeater {
    model: cardWrapper.segments.length
    delegate: Item {
      id: cardShadow
      readonly property var segment: cardWrapper.segments[index] || { x: 0, width: 0 }
      readonly property real pad: Style.space(30)
      readonly property real drop: Style.space(2)
      readonly property real padBottom: Math.max(0, (root ? root.edgeGap : 0) + cardWrapper.shadowRoom - cardShadow.drop)
      visible: root ? (root.showShadow && root.showBackground && root.shadowStrength > 0) : true
      // Follows the card out of view; a blur left behind would hang on screen
      // after the dock has gone.
      opacity: cardWrapper.opacity
      x: dockCard.x + segment.x - cardShadow.pad
      y: dockCard.y + cardShadow.drop - cardShadow.pad
      width: segment.width + cardShadow.pad * 2
      height: dockCard.height + cardShadow.pad + cardShadow.padBottom
      z: 0
      // No offscreen texture while the shadow is off.
      layer.enabled: cardShadow.visible
      layer.effect: MultiEffect {
        blurEnabled: true
        blur: 1.0
        blurMax: 20
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: cardShadow.pad
        anchors.bottomMargin: cardShadow.padBottom
        radius: dockCard.radius
        color: Qt.rgba(0, 0, 0, root ? root.shadowStrength : 0.4)
      }
    }
  }

  BorderSurface {
    id: dockCard
    transformOrigin: Item.Bottom
    anchors.bottom: parent ? parent.bottom : undefined
    // The element a drag in the dock holds (DockLift), for the row's slots
    // and drop gaps.
    readonly property var liftRef: dockLift

    // Whole device pixels for the rim and the padding: at a fractional scale
    // (1.5) a 1.5 px rim puts everything inside the card a fraction of a pixel
    // off the grid, and the unsmoothed square indicators then lose or gain a
    // row depending on the border setting.
    readonly property real dpr: root ? root.outputScale : 1
    function devSnap(v) { return v <= 0 ? 0 : Math.max(1, Math.round(v * dockCard.dpr)) / dockCard.dpr }
    readonly property real effectiveBorderWidth: dockCard.devSnap(root ? root.borderWidth : 1.5)

    // Section divider lines, in card coordinates: a share of the height
    // inside the rim, so 100% runs from the rim to the rim without covering
    // it, centred on the card on whole device pixels.
    readonly property real dividerRoom: Math.max(0, dockCard.height - dockCard.borderTop - dockCard.borderBottom)
    readonly property real dividerLength: dockCard.devSnap(dockCard.dividerRoom * (root ? root.dividerHeight : 70) / 100)
    readonly property real dividerWidth: dockCard.devSnap(root ? root.dividerLineWidth : 1)
    readonly property real dividerTop: Math.round((dockCard.borderTop + (dockCard.dividerRoom - dockCard.dividerLength) / 2) * dockCard.dpr) / dockCard.dpr

    // The panels below paint the fill and the rim. The card keeps a clear
    // rim of the same width, so its content insets do not depend on how many
    // panels there are.
    color: "transparent"
    borderSpec: (root && !root.showBorder)
      ? Border.none()
      : Border.flat("transparent", (root && root.placement.panel) ? dockCard.effectiveBorderWidth + " 0 0 0" : dockCard.effectiveBorderWidth)
    radius: root ? root.cardRadius(height) : Style.cornerRadius
    padding: dockCard.devSnap(Style.space(5))
    // With label plates the sides match the gap between plates.
    leftPadding: (root && root.labelPlates) ? root.plateSpacing.edge : padding
    rightPadding: (root && root.labelPlates) ? root.plateSpacing.edge : padding
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

    width: cardWrapper.stretch ? cardWrapper.stretch.width : row.implicitWidth + contentLeftInset + contentRightInset
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
      // Plate rows keep the spacing on the device-pixel grid.
      spacing: root ? root.gapWidth : Style.space(4)

      x: dockCard.contentLeftInset + cardWrapper.rowOffset
      y: dockCard.contentTopInset

      RowSlot {
        rootRef: cardWrapper.rootRef
        shown: root ? (root.showAppsButton && !root.fitHostRef.hidden["button"]) : true
        DockIconButton {
          rootRef: cardWrapper.rootRef
          homeCenter: root ? root.slotHomeCenter(0, 0, false) : 0
          glyph: "\ue900"
          glyphColor: root ? root.dockForeground : Color.bar.text
          tooltip: "Omarchy"
          onPressed: root && root.sharedState ? root.sharedState.appGrid.openLauncher() : Quickshell.execDetached(["omarchy-menu", "toggle", "root"])
          onMiddleClicked: Quickshell.execDetached(["omarchy-launch-terminal"])
          onMenuRequested: function(cx, cy) {
            if (root) root.openDockSettingsMenu(cx, cy)
          }
        }
      }

      // Pinned apps and app groups share one run (root.pinnedRow): each
      // group stands where its "before" app puts it.
      Repeater {
        id: pinnedRowRepeater
        model: pinnedRowModel
        // RowSlot eases the element in and out (KeyedListModel's leaving and
        // fresh); slot, not index, is its place among the live rows.
        delegate: RowSlot {
          id: rowWrap
          required property string key
          required leaving
          required fresh
          required property int slot
          rootRef: cardWrapper.rootRef
          liftKey: "pin:" + rowWrap.key
          // Moved into "»" by the dock's fit (DockFitHost).
          shown: !(root && root.fitHostRef.hidden["pin:" + rowWrap.key])
          Loader {
            id: rowSlot
            readonly property string key: rowWrap.key
            readonly property int index: rowWrap.slot
            readonly property bool isGroup: key.indexOf("group:") === 0
            // Looked up by key; kept through the moment a removed key has left
            // the lookup but not yet the model.
            property var modelData: ({})
            // Taken only while the key is in the lookup: a leaving row keeps
            // the data it had (a Binding would read the gap first).
            readonly property var _lookedUp: root ? root.pinnedRowByKey[rowSlot.key] : undefined
            on_LookedUpChanged: if (_lookedUp) modelData = _lookedUp
            Component.onCompleted: if (_lookedUp) modelData = _lookedUp
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
                labelSlot: (root && !rowWrap.leaving) ? root.appsSlots + rowSlot.index : -1
                dropLineHere: !rowWrap.leaving && cardWrapper.dropLineRow === rowSlot.index
                pinned: true
                active: root ? (entry.appId === root.activeId) : false
                onActivateRequested: function(aid) { if (root) root.activate(aid) }
                onNewWindowRequested: function(aid) { if (root) root.launchApp(aid, null) }
                onMenuRequested: function(aid, cx, cy) { if (root) root.openContext(aid, cx, cy) }
                onDragStarted: function(aid) {
                  if (root) {
                    dockLift.begin(rowWrap.liftKey, rowSlot.item)
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
                labelSlot: (root && !rowWrap.leaving) ? root.appsSlots + rowSlot.index : -1
                dropLineHere: !rowWrap.leaving && cardWrapper.dropLineRow === rowSlot.index
                onOpenGroupRequested: function(gdata, cx, cy) {
                  if (root) root.openAppGroup(gdata, cx, cy)
                }
                onMenuRequested: function(gdata, cx, cy) {
                  if (root) root.openAppGroupContext(gdata, cx, cy)
                }
                onDragStarted: function(gid) {
                  dockLift.begin(rowWrap.liftKey, rowSlot.item)
                  cardWrapper.handleGroupDragStarted(gid)
                }
                onDragMoved: function(gid, mx, my) { cardWrapper.handleGroupDragMoved(gid, mx, my) }
                onDragDropped: function(gid) { cardWrapper.handleGroupDragDropped(gid) }
              }
            }
          }
        }
      }

      // A drag landing after the last pinned app or group.
      DropGap {
        rootRef: cardWrapper.rootRef
        spacer: true
        open: cardWrapper.dropLineRow >= 0 && cardWrapper.dropLineRow === pinnedRowModel.liveCount
      }

      // Divider between pinned apps and the minimized-tile section.
      RowDivider {
        id: leftTileSeparator
        rootRef: cardWrapper.rootRef
        cardRef: dockCard
        rowY: row.y
        shown: root ? (root.hasLeftTileSeparator && root.fitHostRef.shown.tiles > 0 && root.fitHostRef.shown.pinned > 0) : false
        lineHidden: !!(root && root.placement.split)
      }

      // ------------------------------------------ minimized window tiles
      // macOS-style section: every parked window shows up as a small live
      // preview tile. Click a tile to bring that exact window back.
      Repeater {
        id: minimizedTilesRepeater
        model: tileRowModel

        delegate: RowSlot {
          id: minimizedTilesRepeaterWrap
          required property string key
          required leaving
          required fresh
          required property int slot
          rootRef: cardWrapper.rootRef
          shown: !(root && root.fitHostRef.hidden["tile:" + minimizedTilesRepeaterWrap.key])
          PreviewTile {
            // Looked up by key; kept while the row leaves.
            property var modelData: ({})
            // Taken only while the key is in the lookup: a leaving row keeps
            // the data it had (a Binding would read the gap first).
            readonly property var _lookedUp: cardWrapper.tileByKey[minimizedTilesRepeaterWrap.key]
            on_LookedUpChanged: if (_lookedUp) modelData = _lookedUp
            Component.onCompleted: if (_lookedUp) modelData = _lookedUp
            readonly property int index: minimizedTilesRepeaterWrap.slot
            rootRef: cardWrapper.rootRef
            tileData: modelData || ({})
            tileIndex: index
          }
        }
      }

      RowDivider {
        id: separator
        rootRef: cardWrapper.rootRef
        cardRef: dockCard
        rowY: row.y
        shown: root ? (root.hasSeparator && root.fitHostRef.shown.running > 0) : false
        lineHidden: !!(root && root.placement.split)
      }

      Repeater {
        id: runningRepeater
        model: runningModel
        delegate: RowSlot {
          id: runWrap
          required property string key
          required leaving
          required fresh
          required property int slot
          rootRef: cardWrapper.rootRef
          liftKey: "run:" + runWrap.key
          // A fully tiled app leaves the run like a closed one.
          shown: !runningDockItem.isFullyTiled && !(root && root.fitHostRef.hidden["run:" + runWrap.key])
          DockItem {
            readonly property string key: runWrap.key
            readonly property int index: runWrap.slot
            id: runningDockItem
            // Looked up by key, as in the pinned run.
            property var entry: ({})
            // Taken only while the key is in the lookup: a leaving row keeps
            // the data it had (a Binding would read the gap first).
            readonly property var _lookedUp: root ? root.runningByKey[runningDockItem.key] : undefined
            on_LookedUpChanged: if (_lookedUp) entry = _lookedUp
            Component.onCompleted: if (_lookedUp) entry = _lookedUp
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
            labelSlot: (root && !runWrap.leaving) ? root.appsSlots + root.pinnedSection.length + root.groupSlots + visibleIdx : -1
            pinned: false
            active: root ? (entry.appId === root.activeId) : false
            onActivateRequested: function(aid) { if (root) root.activate(aid) }
            onNewWindowRequested: function(aid) { if (root) root.launchApp(aid, null) }
            onMenuRequested: function(aid, cx, cy) { if (root) root.openContext(aid, cx, cy) }
            onDragStarted: function(aid) {
              if (root) {
                dockLift.begin(runWrap.liftKey, runningDockItem)
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
          }
        }
      }

      // Both sides: the free width between the groups.
      Item {
        id: spreadGap
        visible: root ? root.placement.align === "spread" : false
        width: visible ? DockLayout.spreadGap(cardWrapper.innerWidth, spreadGap.x, rightRow.implicitWidth, row.spacing, cardWrapper.plateDpr) : 0
        height: 1
      }

      // Folders, buttons and drives (DockRightGroup).
      DockRightGroup {
        id: rightRow
        rootRef: cardWrapper.rootRef
        cardRef: dockCard
        wrapper: cardWrapper
        outerRow: row
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

    DockLift {
      id: dockLift
      rootRef: cardWrapper.rootRef
      findSlot: cardWrapper.slotByLiftKey
      z: 250
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
      // The layer is short now: keep the bubble below its top edge.
      readonly property real windowTop: -((root && root.dockWindowRef ? root.dockWindowRef.height : 0) - (root ? root.edgeGap : Style.gapsOut) - dockCard.height)
      y: Math.max(windowTop + Style.space(2), Math.round((root ? root.dragPointerY : 0) - height - Style.space(16)))

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
