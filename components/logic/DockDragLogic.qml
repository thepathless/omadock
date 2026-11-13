import QtQuick
import Quickshell
import qs.Commons
import "../../DockModel.js" as DockModel
import "../../DockPins.js" as DockPins

// Logic extracted from DockCard.qml: stateless functions taking the
// dock root and the card wrapper. Bodies are verbatim.

QtObject {
  // Insert index among the pinned folders for a pointer at row x: before the
  // first folder whose icon centre lies right of it. The icon sits right of
  // any open gap, so moving through the gap keeps the same index.
  // The folder section of the row: from the folder divider on, or, with no
  // divider (no folders or drives yet, or nothing before them), the last
  // three quarters of a slot at the end of the row and beyond.
  // Folders and drives sit in their own row (card.rightRowRef); px is in
  // the outer row's coordinates. A divider narrowing away (RowDivider keeps
  // it visible while it has width) no longer counts.
  // The element the drag holds (DockLift); null before the card is built.
  function liftOf(root, card) {
    return card && card.dockCard ? card.dockCard.liftRef : null
  }

  function inPinZone(root, card, px) {
    var rx = px - card.rightRowRef.x
    if (card.folderSeparatorRef.visible && card.folderSeparatorRef.shown) return rx >= card.folderSeparatorRef.x - (root ? root.gapWidth : 0)
    var folders = card.liveSlots(card.foldersRepeater)
    if (folders.length > 0) return rx >= folders[0].x
    return px >= card.row.width - (root ? root.iconSlot * 0.75 : 0)
  }

  function folderInsertIndex(root, card, px) {
    var rx = px - card.rightRowRef.x
    var folders = card.liveSlots(card.foldersRepeater)
    var n = folders.length
    for (var i = 0; i < n; i++) {
      var slot = folders[i]
      // The held folder has folded away: it is no place to aim at.
      if (slot.lifted) continue
      // The middle of the folder's tile (icon and any label), past the drop gap.
      var gap = slot.child.gapWidth || 0
      var iconCenter = slot.x + gap + (slot.width - gap) / 2
      if (rx < iconCenter) return i
    }
    return n
  }

  // A drag pulled this far above the card takes the item off the dock.
  function offDockAt(root, card, my) {
    return root ? my < -(root.iconSlot * 0.75) : false
  }

  // Over the running apps that are not pinned: from the divider before
  // them to the gap after the last one.
  function overRunningAt(root, card, rx) {
    var runs = card.liveSlots(card.runningRepeater)
    var n = runs.length
    var first = n > 0 ? runs[0] : null
    var last = n > 0 ? runs[n - 1] : null
    if (!first || !last) return false
    var start = (card.separatorRef.visible && card.separatorRef.shown) ? card.separatorRef.x : first.x - card.row.spacing / 2
    return rx >= start && rx <= last.x + last.width + card.row.spacing / 2
  }

  function handleDragMoved(root, card, aid, mx, my) {
    if (!root) return
    root.dropBeforeId = ""
    root.dragPointerX = mx
    root.dragPointerY = my
    var lift = cardWrapper.liftOf()
    if (lift) lift.move(mx, my)

    // Only a pin can be taken off, by pulling it up off the dock or over to
    // the running apps; a running app that is not pinned stays.
    root.dragRemoveArmed = root.dragSourceGroupId === "" && DockPins.isPinned(root.pinnedIds, aid)
      && (cardWrapper.offDockAt(my) || cardWrapper.overRunningAt(mx - card.row.x))
    if (root.dragRemoveArmed) {
      if (lift) lift.dwell("")
      return
    }

    // Over the middle half of a group or of another pinned app nothing
    // moves; held there a moment (DockLift.dwell) it becomes the target:
    // the group takes the app, or the two apps make one. Let go before,
    // the element lands where its gap stands.
    var rx = mx - card.row.x
    var slots = card.liveSlots(card.pinnedRowRepeater)
    var n = slots.length
    var over = ""
    for (var i = 0; i < n; i++) {
      var slot = slots[i]
      var it = slot.child.item
      if (!it || slot.lifted) continue
      var lead = it.dropGap || 0
      var left = slot.x + lead
      var span = slot.width - lead
      if (rx <= left + span * 0.25 || rx >= left + span * 0.75) continue
      if (slot.child.isGroup) over = "group:" + it.groupId
      else if (it.appId !== aid) over = "app:" + it.appId
      break
    }
    if (lift) lift.dwell(over)
    else {
      root.dropTargetAppId = ""
      root.dropTargetGroupId = ""
    }

    var idx = stickyRowIndex(root, card, rx)
    // Past the end of the run, a running app that is not pinned lands after
    // the last item only while the pointer stays next to it: further right
    // it is over the running apps, its own place, where letting go does
    // nothing.
    if (idx === n && !DockPins.isPinned(root.pinnedIds, aid)) {
      var last = n > 0 ? slots[n - 1] : null
      if (!last || rx > last.x + last.width + root.iconSlot / 2) idx = -1
    }
    root.dropRowIndex = idx
    if (idx < 0) return
    // The first app at or after the drop, for moves that work in pin order.
    for (var j = idx; j < n; j++) {
      var s2 = slots[j].child
      if (!s2.isGroup && s2.item && s2.item.appId !== aid) {
        root.dropBeforeId = s2.item.appId
        break
      }
    }
  }

  // The drop index in a run of slots for a pointer at x, kept where it is
  // until the pointer has gone three quarters of the way over the next
  // element (or back over the previous one): that neighbour then moves
  // once, into the place the gap leaves, away from the pointer, instead of
  // stepping aside as soon as the pointer reaches its edge. `cur` < 0 (no
  // place yet) takes `fresh`. leadOf gives the room an open gap adds
  // before a slot's element.
  function stickyIndex(root, slots, x, cur, fresh, leadOf) {
    var n = slots.length
    if (cur < 0 || cur > n) return fresh
    function edge(slot, f) {
      var lead = leadOf(slot)
      return slot.x + lead + (slot.width - lead) * f
    }
    for (var guard = 0; guard <= n; guard++) {
      var next = -1
      for (var a = cur; a < n; a++) if (!slots[a].lifted) { next = a; break }
      if (next >= 0 && x > edge(slots[next], 0.75)) { cur = next + 1; continue }
      var prev = -1
      for (var b = cur - 1; b >= 0; b--) if (!slots[b].lifted) { prev = b; break }
      if (prev >= 0 && x < edge(slots[prev], 0.25)) { cur = prev; continue }
      break
    }
    return cur
  }

  function stickyRowIndex(root, card, rx) {
    var slots = card.liveSlots(card.pinnedRowRepeater)
    if (slots.length === 0) return -1
    return stickyIndex(root, slots, rx, root.dropRowIndex, cardWrapper.rowInsertIndex(rx),
      function(slot) { return slot.child.item ? (slot.child.item.dropGap || 0) : 0 })
  }

  // Insert index in the pinned run for a pointer at row x: before the first
  // item whose centre lies right of it, so past the end of the run (over the
  // running apps, say) means its end. -1 when the run is empty.
  function rowInsertIndex(root, card, rx) {
    var slots = card.liveSlots(card.pinnedRowRepeater)
    var n = slots.length
    if (n === 0) return -1
    // The held element has folded away: the places either side of it are
    // the same place, its own.
    for (var i = 0; i < n; i++) {
      if (slots[i].lifted) continue
      if (rx < slots[i].x + slots[i].width / 2) return i
    }
    return n
  }

  function handleDragDropped(root, card, aid) {
    if (!root) return
    var lift = cardWrapper.liftOf()
    // Out of an opened group the copy is the app's icon (DockLift.beginIcon):
    // the room its gap holds goes to the app's new slot, so a drop that
    // pins it lands at once; any other lets the gap ease shut.
    var fromPopup = !!lift && lift.iconCopy
    var pinsIt = root.dropTargetGroupId === "" && root.dropTargetAppId === ""
    if (lift) lift.drop()
    if (fromPopup && !pinsIt) lift.snapping = false
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

    // Where the dragged copy lands: the app's slot after the drop, or into
    // the group it went into; off the dock it fades.
    var fade = removeArmed
    var intoKey = ""
    var hadKeys = {}
    var keysThen = root.pinnedRowKeys
    for (var hk = 0; hk < keysThen.length; hk++) hadKeys[keysThen[hk]] = true
    if (dragId !== "" && removeArmed) {
      root.dragSourceGroupId = ""
      root.togglePin(dragId)
    } else if (dragId !== "") {
      if (sourceGroupId !== "") {
        if (targetGroupId === sourceGroupId) {
          root.dragSourceGroupId = ""
          if (lift) lift.settle("pin:group:" + sourceGroupId, false, true)
          root.syncVisibility()
          return
        }
        if (fromPopup) lift.handOff([], lift.heldGapSum)
        root.removeAppFromGroup(sourceGroupId, dragId)
      }

      if (targetGroupId !== "") {
        root.addAppToGroup(targetGroupId, dragId)
        intoKey = "pin:group:" + targetGroupId
      } else if (targetAppId !== "" && targetAppId !== dragId) {
        var made = root.createAppGroupFromDrop(targetAppId, dragId)
        if (made) intoKey = "pin:group:" + made
      } else {
        var rowNow = root.pinnedRow
        if (sourceGroupId !== "") {
          // Out of an open group: the group has just changed under the drag,
          // so place the app by pin order alone.
          root.setPinned(DockPins.reorderPinned(root.pinnedIds, dragId, beforeId))
        } else if (rowIdx >= 0) {
          // A pinned app moves within the run; a running one dropped in it
          // gets pinned there. Groups keep their places.
          var from = -1
          for (var r = 0; r < rowNow.length; r++) {
            if (rowNow[r].kind === "app" && rowNow[r].appId === dragId) { from = r; break }
          }
          var nextRow
          if (from >= 0) {
            nextRow = DockPins.moveBefore(rowNow, from, rowIdx)
          } else {
            nextRow = rowNow.slice()
            nextRow.splice(rowIdx, 0, { kind: "app", appId: dragId })
          }
          if (nextRow !== rowNow) root.applyPinnedRow(nextRow)
        }
      }
      if (fromPopup && sourceGroupId !== "") {
        var appKey = "app:" + dragId
        lift.handOn((!hadKeys[appKey] && root.pinnedRowKeys.indexOf(appKey) >= 0) ? ["pin:" + appKey] : [])
      }
      root.dragSourceGroupId = ""
    } else {
      root.dragSourceGroupId = ""
    }
    if (lift) {
      if (intoKey !== "") lift.settle(intoKey, false, true)
      else lift.settle(DockPins.isPinned(root.pinnedIds, aid) ? "pin:app:" + aid : "run:" + aid, fade)
    }
    root.syncVisibility()
  }

  function handleFolderDragStarted(root, card, path) {
    if (!root) return
    root.dragFolderPath = path
    root.dropFolderIndex = -1
    root.dragRemoveArmed = false
  }

  // Reorders within the folder section: from the gap before the first
  // folder to the gap after the last one.
  function handleFolderDragMoved(root, card, path, mx, my) {
    if (!root) return
    root.dragPointerX = mx
    root.dragPointerY = my
    var lift = cardWrapper.liftOf()
    if (lift) lift.move(mx, my)
    root.dragRemoveArmed = cardWrapper.offDockAt(my)
    var folders = card.liveSlots(card.foldersRepeater)
    var n = folders.length
    var first = n > 0 ? folders[0] : null
    var last = n > 0 ? folders[n - 1] : null
    var rx = mx - card.row.x
    var fx = rx - card.rightRowRef.x
    if (root.dragRemoveArmed || !first || !last
        || fx < first.x - card.row.spacing || fx > last.x + last.width + card.row.spacing) {
      root.dropFolderIndex = -1
      return
    }
    var idx = stickyIndex(root, folders, fx, root.dropFolderIndex, cardWrapper.folderInsertIndex(rx),
      function(slot) { return slot.child.gapWidth || 0 })
    root.dropFolderIndex = idx
  }

  function handleFolderDragDropped(root, card, path) {
    if (!root) return
    var lift = cardWrapper.liftOf()
    if (lift) lift.drop()
    var removeArmed = root.dragRemoveArmed
    var idx = root.dropFolderIndex
    root.dragFolderPath = ""
    root.dropFolderIndex = -1
    root.dragRemoveArmed = false
    if (removeArmed) root.toggleFolderPin(path, "", "")
    else if (idx >= 0) root.moveFolder(path, idx)
    if (lift) lift.settle(lift.sourceKey, removeArmed)
    root.syncVisibility()
  }

  // App groups move anywhere in the pinned run, among the pinned apps; an
  // accent line marks where the group lands.
  function handleGroupDragStarted(root, card, gid) {
    if (!root) return
    root.dragGroupId = gid
    root.dropRowIndex = -1
    root.dragRemoveArmed = false
  }

  function handleGroupDragMoved(root, card, gid, mx, my) {
    if (!root) return
    root.dragPointerX = mx
    root.dragPointerY = my
    var lift = cardWrapper.liftOf()
    if (lift) lift.move(mx, my)
    root.dragRemoveArmed = cardWrapper.offDockAt(my)
    var idx = root.dragRemoveArmed ? -1 : stickyRowIndex(root, card, mx - card.row.x)
    root.dropRowIndex = idx
  }

  function handleGroupDragDropped(root, card, gid) {
    if (!root) return
    var lift = cardWrapper.liftOf()
    if (lift) lift.drop()
    var removeArmed = root.dragRemoveArmed
    var idx = root.dropRowIndex
    root.dragGroupId = ""
    root.dropRowIndex = -1
    root.dragRemoveArmed = false
    if (removeArmed) root.removeAppGroup(gid)
    else if (idx >= 0) root.moveAppGroup(gid, idx)
    if (lift) lift.settle("pin:group:" + gid, removeArmed)
    root.syncVisibility()
  }
}
