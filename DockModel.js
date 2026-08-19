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

function copyMap(src) {
  var out = {}
  for (var key in src) out[key] = src[key]
  return out
}

// Compact workspace label for a tooltip: numbered workspaces only. Special
// workspaces have no number worth showing, so they get nothing.
function workspaceShort(wsId, wsName) {
  if (wsId === null || wsId === undefined || wsId < 0) return ""
  var name = String(wsName == null ? "" : wsName)
  if (name && name.length <= 2) return name
  return String(wsId)
}

// Spelled-out label for menu rows: "3", "scratchpad", "minimized".
function workspaceLabel(wsName, wsId) {
  var name = String(wsName == null ? "" : wsName).trim()
  if (name.indexOf("special:") === 0) return name.slice(8)
  if (name) return name
  return (wsId === null || wsId === undefined) ? "" : String(wsId)
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

function buildEntries(pinnedIds, toplevels, appRows, appLibrary, hyprFor) {
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
      activated: !!toplevel.activated,
      // Live Hyprland handle. Urgency and workspace are read off this object
      // directly so the dock follows them without rebuilding the model.
      hypr: hyprFor ? hyprFor(toplevel) : null
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

// Which window a click or a wheel step should land on. Pure: the caller
// decides how to bring it forward.
function pickAppWindow(toplevels, activeToplevel, appId, direction) {
  var want = stripDesktop(appId)
  if (!want) return null
  var list = toArray(toplevels)
  var matching = []

  for (var i = 0; i < list.length; i++) {
    var t = list[i]
    if (t && stripDesktop(t.appId) === want) matching.push(t)
  }

  if (matching.length === 0) return null
  if (matching.length === 1) return matching[0]

  var dir = (typeof direction === "number" && direction < 0) ? -1 : 1
  var activeIdx = -1
  for (var j = 0; j < matching.length; j++) {
    if (matching[j] === activeToplevel || matching[j].activated) {
      activeIdx = j
      break
    }
  }

  // Nothing of this app is focused: enter the list from the end we came from.
  if (activeIdx < 0) return matching[dir > 0 ? 0 : matching.length - 1]
  return matching[(activeIdx + dir + matching.length) % matching.length]
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
