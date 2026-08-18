// Pure helpers for the dock plugin. No QML state — the host object owns the
// model; this file only turns inputs into output arrays.

function stripDesktop(id) {
  var value = String(id == null ? "" : id).trim()
  if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
  return value
}

function toArray(list) {
  if (Array.isArray(list)) return list
  if (list && typeof list.length === "number") {
    var out = []
    for (var i = 0; i < list.length; i++) out.push(list[i])
    return out
  }
  return []
}

function normalizeId(id) {
  return stripDesktop(id)
}

function parsePinned(raw) {
  var text = String(raw == null ? "" : raw).trim()
  if (!text) return []

  var parsed = null
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return []
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return []

  var arr = Array.isArray(parsed.pinned) ? parsed.pinned : []
  var out = []
  var seen = {}
  for (var i = 0; i < arr.length; i++) {
    var id = stripDesktop(arr[i])
    if (!id || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

function serializePinned(pinnedIds) {
  var arr = Array.isArray(pinnedIds) ? pinnedIds : []
  var cleaned = []
  var seen = {}
  for (var i = 0; i < arr.length; i++) {
    var id = stripDesktop(arr[i])
    if (!id || seen[id]) continue
    seen[id] = true
    cleaned.push(id)
  }
  return JSON.stringify({ pinned: cleaned }, null, 2)
}

function togglePinned(pinnedIds, appId) {
  var arr = Array.isArray(pinnedIds) ? pinnedIds.slice() : []
  var id = stripDesktop(appId)
  if (!id) return arr
  var idx = arr.indexOf(id)
  if (idx >= 0) arr.splice(idx, 1)
  else arr.push(id)
  return arr
}

function isPinned(pinnedIds, appId) {
  var arr = Array.isArray(pinnedIds) ? pinnedIds : []
  return arr.indexOf(stripDesktop(appId)) >= 0
}

// Reorder pinned apps: move appId from its current position to insertBeforeId.
// If insertBeforeId is null/empty, move to the end.
function reorderPinned(pinnedIds, appId, insertBeforeId) {
  var arr = Array.isArray(pinnedIds) ? pinnedIds.slice() : []
  var id = stripDesktop(appId)
  if (!id) return arr

  var fromIdx = arr.indexOf(id)
  if (fromIdx < 0) return arr

  arr.splice(fromIdx, 1)

  if (!insertBeforeId) {
    arr.push(id)
  } else {
    var toIdx = arr.indexOf(stripDesktop(insertBeforeId))
    if (toIdx < 0) arr.push(id)
    else arr.splice(toIdx, 0, id)
  }
  return arr
}

function entryFor(appRows, appId) {
  var want = stripDesktop(appId)
  if (!want || !appRows) return null
  var wantLower = want.toLowerCase()

  // 1. Exact ID match
  for (var i = 0; i < appRows.length; i++) {
    var row = appRows[i]
    var entry = row && row.entry
    if (!entry) continue
    if (stripDesktop(entry.id) === want) return entry
  }

  // 2. Case-insensitive ID match
  for (var i = 0; i < appRows.length; i++) {
    var entry = appRows[i] && appRows[i].entry
    if (!entry) continue
    if (stripDesktop(entry.id).toLowerCase() === wantLower) return entry
  }

  // 3. Suffix/prefix match for reverse domain names (e.g. org.gnome.Nautilus vs nautilus)
  for (var i = 0; i < appRows.length; i++) {
    var entry = appRows[i] && appRows[i].entry
    if (!entry) continue
    var eid = stripDesktop(entry.id).toLowerCase()
    var lastDot = eid.lastIndexOf(".")
    var shortEid = lastDot >= 0 ? eid.slice(lastDot + 1) : eid
    var lastDotWant = wantLower.lastIndexOf(".")
    var shortWant = lastDotWant >= 0 ? wantLower.slice(lastDotWant + 1) : wantLower

    if (shortEid === shortWant && shortWant.length > 1) return entry
  }

  // 4. Name / genericName match
  for (var i = 0; i < appRows.length; i++) {
    var entry = appRows[i] && appRows[i].entry
    if (!entry) continue
    var name = String(entry.name || "").toLowerCase()
    var generic = String(entry.genericName || "").toLowerCase()
    if (name === wantLower || (generic && generic === wantLower)) return entry
  }

  return null
}

function buildEntries(pinnedIds, toplevels, appRows, appLibrary) {
  var pinned = Array.isArray(pinnedIds) ? pinnedIds : []
  var list = toArray(toplevels)

  var runningIds = []
  var winMap = {}
  for (var i = 0; i < list.length; i++) {
    var toplevel = list[i]
    if (!toplevel) continue
    var appId = stripDesktop(toplevel.appId)
    if (!appId) continue
    if (!winMap[appId]) {
      winMap[appId] = []
      runningIds.push(appId)
    }
    winMap[appId].push({
      title: String(toplevel.title || "Window"),
      toplevel: toplevel,
      activated: !!toplevel.activated
    })
  }

  function enrich(list) {
    for (var j = 0; j < list.length; j++) {
      var item = list[j]
      var entry = entryFor(appRows, item.appId)
      if (entry && appLibrary) {
        item.name = appLibrary.entryName(entry)
        item.icon = appLibrary.iconSource(entry.icon)
      } else {
        item.name = item.appId
        item.icon = ""
      }
    }
  }

  var pinnedOut = []
  var seen = {}
  var j = 0

  for (j = 0; j < pinned.length; j++) {
    var pid = stripDesktop(pinned[j])
    if (!pid || seen[pid]) continue
    seen[pid] = true
    var wins = winMap[pid] || []
    pinnedOut.push({
      appId: pid,
      pinned: true,
      running: wins.length > 0,
      windows: wins.length,
      windowList: wins
    })
  }
  enrich(pinnedOut)

  var runningOut = []
  for (j = 0; j < runningIds.length; j++) {
    var rid = runningIds[j]
    if (seen[rid]) continue
    seen[rid] = true
    var wins = winMap[rid] || []
    runningOut.push({
      appId: rid,
      pinned: false,
      running: true,
      windows: wins.length,
      windowList: wins
    })
  }
  enrich(runningOut)

  return { pinned: pinnedOut, running: runningOut }
}

function activeAppId(toplevels, activeToplevel) {
  var top = activeToplevel || null
  if (top) return stripDesktop(top.appId)
  var list = toArray(toplevels)
  if (list.length > 0) return stripDesktop(list[0].appId)
  return ""
}

function cycleAppWindow(toplevels, activeToplevel, appId, direction) {
  var want = stripDesktop(appId)
  if (!want) return
  var list = toArray(toplevels)
  var matching = []

  for (var i = 0; i < list.length; i++) {
    var t = list[i]
    if (t && stripDesktop(t.appId) === want) matching.push(t)
  }

  if (matching.length === 0) return
  if (matching.length === 1) {
    if (matching[0].activate) matching[0].activate()
    return
  }

  // Multi-window: cycle in requested direction (default forward +1, backward -1)
  var dir = (typeof direction === "number" && direction !== 0) ? (direction > 0 ? 1 : -1) : 1
  var activeIdx = -1
  if (activeToplevel) {
    for (var i = 0; i < matching.length; i++) {
      if (matching[i] === activeToplevel || matching[i].activated) {
        activeIdx = i
        break
      }
    }
  }

  var nextIdx = (activeIdx + dir + matching.length) % matching.length
  if (matching[nextIdx] && matching[nextIdx].activate) {
    matching[nextIdx].activate()
  }
}

function activateApp(toplevels, activeToplevel, appId) {
  cycleAppWindow(toplevels, activeToplevel, appId, 1)
}

function focusWindow(toplevel) {
  if (toplevel && toplevel.activate) toplevel.activate()
}

function closeWindow(toplevel) {
  if (toplevel && toplevel.close) toplevel.close()
}

function closeApp(toplevels, appId) {
  var want = stripDesktop(appId)
  if (!want) return 0
  var list = toArray(toplevels)
  var closed = 0
  for (var i = 0; i < list.length; i++) {
    var t = list[i]
    if (!t) continue
    if (stripDesktop(t.appId) === want) {
      if (t.close) t.close()
      closed += 1
    }
  }
  return closed
}
