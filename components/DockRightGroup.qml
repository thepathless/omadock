import QtQuick
import qs.Commons
import qs.Ui
import "../DockIcons.js" as DockIcons
import "../DockKeys.js" as DockKeys

// Folders, command buttons and drives: the right group of the dock's row
// (DockCard), its own Row so the Both sides gap before it can be sized from
// its width without the outer row measuring itself.
Row {
  property var rootRef: null
  readonly property var root: rootRef
  readonly property var motion: group.root ? group.root.motion : null
  // The card (dividers' geometry), its wrapper (drag handlers, drop lines,
  // the Both sides shift) and the outer row (spacing, y).
  property var cardRef: null
  property var wrapper: null
  property var outerRow: null
  property alias folderSeparator: folderSeparator
  property alias driveSeparator: driveSeparator
  property alias foldersRepeater: foldersRepeater
  property alias drivesRepeater: drivesRepeater
  property alias trailingDropGap: trailingDropGap
  readonly property alias folderRowModel: folderRowModel

  // Folders first, then the command buttons: the section keeps one row.
  // Both runs are keyed (KeyedListModel), so an added or removed one eases
  // in or out instead of rebuilding the others.
  readonly property var folderList: root ? root.pinnedFolders.concat(root.pinnedButtons) : []
  readonly property var driveList: (root && root.showRemovableDrives) ? root.mountedDrives : []
  readonly property var folderByKey: {
    var m = {}
    for (var i = 0; i < folderList.length; i++) m[DockKeys.folderKey(folderList[i])] = folderList[i]
    return m
  }
  readonly property var driveByKey: {
    var m = {}
    for (var i = 0; i < driveList.length; i++) m[DockKeys.driveKey(driveList[i])] = driveList[i]
    return m
  }
  KeyedListModel { id: folderRowModel; exitMs: group.root ? group.root.motion.base : 0 }
  KeyedListModel { id: driveRowModel; exitMs: group.root ? group.root.motion.base : 0 }
  onFolderListChanged: folderRowModel.sync(folderList.map(DockKeys.folderKey))
  onDriveListChanged: driveRowModel.sync(driveList.map(DockKeys.driveKey))
  Component.onCompleted: {
    folderRowModel.sync(folderList.map(DockKeys.folderKey))
    driveRowModel.sync(driveList.map(DockKeys.driveKey))
  }
  id: group
  spacing: group.outerRow.spacing
  anchors.verticalCenter: parent.verticalCenter
  // Also while its last rows and dividers are on their way out.
  visible: root ? (root.hasFolderSeparator || root.folderSlots > 0 || root.driveSlots > 0 || trailingDropGap.open
    || folderRowModel.count > 0 || driveRowModel.count > 0 || folderSeparator.visible || driveSeparator.visible || overflowSlot.visible
    || root.placement.taskbar) : true

  RowDivider {
    id: folderSeparator
    rootRef: group.wrapper.rootRef
    cardRef: group.cardRef
    rowY: group.outerRow.y + group.y
    shown: root ? (root.hasFolderSeparator && root.fitHostRef.shown.folders + root.fitHostRef.shown.drives > 0) : false
    lineHidden: !!(root && (root.placement.split || root.placement.align === "spread"))
  }

  Repeater {
    id: foldersRepeater
    model: folderRowModel
    delegate: RowSlot {
      id: foldersRepeaterWrap
      required property string key
      required leaving
      required fresh
      required property int slot
      rootRef: group.wrapper.rootRef
      liftKey: "folder:" + foldersRepeaterWrap.key
      // Moved into "»" by the dock's fit (DockFitHost).
      shown: !(group.root && group.root.fitHostRef.hidden["folder:" + foldersRepeaterWrap.key])
      DockFolderItem {
        id: folderItem
        // Looked up by key; kept while the row leaves.
        property var modelData: ({})
        // Taken only while the key is in the lookup: a leaving row keeps
        // the data it had (a Binding would read the gap first).
        readonly property var _lookedUp: group.folderByKey[foldersRepeaterWrap.key]
        on_LookedUpChanged: if (_lookedUp) modelData = _lookedUp
        Component.onCompleted: if (_lookedUp) modelData = _lookedUp
        readonly property int index: foldersRepeaterWrap.slot
        rootRef: group.wrapper.rootRef
        folderPath: (modelData || {}).path || ""
        command: (modelData || {}).command || ""
        name: (modelData || {}).name || "Folder"
        icon: (modelData || {}).icon || ((modelData || {}).command ? "application-x-executable" : DockIcons.folderIconFor((modelData || {}).path, ""))
        // A leaving folder takes no drop gap and no label slot.
        slotIndex: foldersRepeaterWrap.leaving ? -1 : index
        dropLineHere: !foldersRepeaterWrap.leaving && group.wrapper.dropLineFolder === index
        homeCenter: root ? root.slotHomeCenter(
          root.appsSlots + root.pinnedSection.length + root.groupSlots + (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + root.tileElements + root.visibleRunningCount + (root.hasFolderSeparator ? 1 : 0) + index,
          root.appsSlots + root.pinnedSection.length + root.groupSlots + root.visibleRunningCount + index,
          (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + (root.hasFolderSeparator ? 1 : 0),
          root.tilesFixedWidth + group.wrapper.spreadShift) : 0
        labelSlot: (root && !foldersRepeaterWrap.leaving) ? root.appsSlots + root.pinnedSection.length + root.groupSlots + root.visibleRunningCount + index : -1
        onOpenStackRequested: function(fpath, fname, cx, cy) {
          if (root) root.openFolderStack(fpath, fname, cx)
        }
        onMenuRequested: function(fpath, fname, cx, cy, cmd) {
          if (root) root.openFolderContext(fpath, fname, cx, cy, cmd)
        }
        onDragStarted: function(fpath) {
          if (group.root && group.root.dockCard) group.root.dockCard.liftRef.begin(foldersRepeaterWrap.liftKey, folderItem)
          group.wrapper.handleFolderDragStarted(fpath)
        }
        onDragMoved: function(fpath, mx, my) { group.wrapper.handleFolderDragMoved(fpath, mx, my) }
        onDragDropped: function(fpath) { group.wrapper.handleFolderDragDropped(fpath) }
      }
    }
  }

  // A folder dragged after the last one.
  DropGap {
    rootRef: group.wrapper.rootRef
    spacer: true
    open: group.wrapper.dropLineFolder >= 0 && group.wrapper.dropLineFolder === folderRowModel.liveCount
  }

  // Drop gap after the last pinned folder (see DockFolderItem.gapWidth).
  DropGhost {
    id: trailingDropGap
    rootRef: group.wrapper.rootRef
    readonly property bool open: root ? (root.dropPreviewPath !== "" && root.dropInsertIndex >= folderRowModel.liveCount) : false
    width: open && root ? root.iconSlot : 0
    height: root ? root.iconSlot : 0
    Behavior on width { NumberAnimation { duration: (group.motion ? group.motion.base : 0); easing.type: Easing.OutCubic } }
  }

  RowDivider {
    id: driveSeparator
    rootRef: group.wrapper.rootRef
    cardRef: group.cardRef
    rowY: group.outerRow.y + group.y
    shown: root ? (root.hasDriveSeparator && root.fitHostRef.shown.folders > 0 && root.fitHostRef.shown.drives > 0) : false
    lineHidden: !!(root && root.placement.split)
  }

  Repeater {
    id: drivesRepeater
    model: driveRowModel
    delegate: RowSlot {
      id: drivesRepeaterWrap
      required property string key
      required leaving
      required fresh
      required property int slot
      rootRef: group.wrapper.rootRef
      shown: !(group.root && group.root.fitHostRef.hidden["drive:" + drivesRepeaterWrap.key])
      DockDriveItem {
        // Looked up by key; kept while the row leaves.
        property var modelData: ({})
        // Taken only while the key is in the lookup: a leaving row keeps
        // the data it had (a Binding would read the gap first).
        readonly property var _lookedUp: group.driveByKey[drivesRepeaterWrap.key]
        on_LookedUpChanged: if (_lookedUp) modelData = _lookedUp
        Component.onCompleted: if (_lookedUp) modelData = _lookedUp
        readonly property int index: drivesRepeaterWrap.slot
        rootRef: group.wrapper.rootRef
        dev: (modelData || {}).dev || ""
        mountpoint: (modelData || {}).mountpoint || ""
        name: (modelData || {}).name || "USB Drive"
        size: (modelData || {}).size || ""
        space: (modelData || {}).space || ""
        fstype: (modelData || {}).fstype || ""
        icon: (modelData || {}).icon || "drive-removable-media"
        // Its plate's place among the plates (DockCard.plateEdges): after the folders.
        plateSlot: (root && !drivesRepeaterWrap.leaving) ? root.appsSlots + root.pinnedSection.length + root.groupSlots + root.visibleRunningCount + root.folderSlots + index : -1
        homeCenter: root ? root.slotHomeCenter(
          root.appsSlots + root.pinnedSection.length + root.groupSlots + (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + root.tileElements + root.visibleRunningCount + (root.hasFolderSeparator ? 1 : 0) + root.folderSlots + (root.hasDriveSeparator ? 1 : 0) + index,
          root.appsSlots + root.pinnedSection.length + root.groupSlots + root.visibleRunningCount + root.folderSlots + index,
          (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + (root.hasFolderSeparator ? 1 : 0) + (root.hasDriveSeparator ? 1 : 0),
          root.tilesFixedWidth + group.wrapper.spreadShift) : 0
        onOpenStackRequested: function(fpath, fname, cx, cy) {
          if (root) root.openFolderStack(fpath, fname, cx)
        }
        onMenuRequested: function(d, mp, n, s, cx, cy) {
          if (root) root.openDriveContext(d, mp, n, s, cx, cy)
        }
      }
    }
  }

  // "»": the items the dock's fit moved out of the row (DockFitHost).
  RowSlot {
    id: overflowSlot
    rootRef: group.wrapper.rootRef
    shown: !!(group.root && group.root.fitHostRef.plan.overflowFrom >= 0)
    DockOverflowTile { rootRef: group.wrapper.rootRef }
  }

  // Windows taskbar's tray clock, at the far right of the row.
  DockTaskbarClock {
    rootRef: group.rootRef
    visible: group.root ? group.root.placement.taskbar : false
  }
}
