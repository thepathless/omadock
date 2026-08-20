// Pure helpers for the dock plugin. No QML state — the host object owns the
// model; this file only turns inputs into output arrays.

var IGNORED_TOKENS = {
  "org": true, "com": true, "io": true, "net": true, "app": true, "bin": true,
  "linux": true, "desktop": true, "client": true, "gui": true, "wrapper": true,
  "window": true, "default": true, "profile": true, "profile_1": true, "profile_2": true,
  "chrome": true, "chromium": true, "brave": true, "edge": true, "microsoft-edge": true,
  "https": true, "http": true, "www": true, "x86_64": true, "x86": true, "amd64": true, "lib": true
};

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
}function copyMap(src) {
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

function getCandidates(id) {
  var raw = stripDesktop(id).toLowerCase()
  if (!raw) return []
  var list = [raw]

  // WebApp extraction (Chrome, Chromium, Brave, Edge PWAs)
  var webAppMatch = raw.match(/^(?:chrome|chromium|brave|edge|microsoft-edge)-(.*?)__?-(?:default|profile.*)$/i)
                 || raw.match(/^(?:chrome|chromium|brave|edge|microsoft-edge)-(.*?)$/i)
  if (webAppMatch) {
    var webTarget = webAppMatch[1].replace(/^https?___?/i, "").replace(/__.*$/, "")
    if (webTarget && list.indexOf(webTarget) < 0) list.push(webTarget)
    var webDomain = webTarget.split(/[\.\/_]+/)
    for (var w = 0; w < webDomain.length; w++) {
      var seg = webDomain[w]
      if (seg && list.indexOf(seg) < 0) list.push(seg)
    }
  }

  // Split by dots, underscores, dashes, slashes
  var parts = raw.split(/[\.\/_-]+/)
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i]
    if (p && list.indexOf(p) < 0) list.push(p)
  }

  var len = list.length
  for (var i = 0; i < len; i++) {
    var item = list[i]
    var stripped = item.replace(/[-_](app|bin|linux|gtk|wrapper|desktop|client|qt\d?|gui)$/i, "")
    if (stripped && list.indexOf(stripped) < 0) list.push(stripped)
    var prefixStripped = item.replace(/^(app|bin|linux|gtk|wrapper|desktop|client|qt\d?|gui)[-_]/i, "")
    if (prefixStripped && list.indexOf(prefixStripped) < 0) list.push(prefixStripped)
  }

  var out = []
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    if (s && !IGNORED_TOKENS[s] && out.indexOf(s) < 0) {
      out.push(s)
    }
  }
  return out
}

function isAppMatch(idA, idB) {
  if (!idA || !idB) return false
  var a = stripDesktop(idA).toLowerCase()
  var b = stripDesktop(idB).toLowerCase()
  if (a === b) return true

  var candsA = getCandidates(a)
  var candsB = getCandidates(b)
  for (var i = 0; i < candsA.length; i++) {
    var ca = candsA[i]
    if (candsB.indexOf(ca) >= 0) return true
  }
  return false
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
    if (stripDesktop(entry.id) === want || stripDesktop(entry.id).toLowerCase() === wantLower) return entry
  }

  // 2. Multi-token candidate match (e.g. chrome-x.com__-Default -> X.desktop, org.localsend.localsend_app -> localsend.desktop)
  var wantCands = getCandidates(want)
  for (var i = 0; i < appRows.length; i++) {
    var entry = appRows[i] && appRows[i].entry
    if (!entry) continue
    var entryCands = getCandidates(entry.id)
      .concat(getCandidates(entry.name))
      .concat(getCandidates(entry.icon))
    for (var k = 0; k < wantCands.length; k++) {
      var cand = wantCands[k]
      if (entryCands.indexOf(cand) >= 0) return entry
    }
  }

  // 3. Webapp Exec URL Match (if entry.exec contains candidate domain or URL)
  for (var i = 0; i < appRows.length; i++) {
    var entry = appRows[i] && appRows[i].entry
    if (!entry) continue
    var execStr = String(entry.exec || "").toLowerCase()
    if (execStr) {
      for (var k = 0; k < wantCands.length; k++) {
        var cand = wantCands[k]
        if (cand.length >= 2 && execStr.indexOf(cand) >= 0) return entry
      }
    }
  }

  // 4. GenericName / Substring match
  for (var i = 0; i < appRows.length; i++) {
    var entry = appRows[i] && appRows[i].entry
    if (!entry) continue
    var generic = String(entry.genericName || "").toLowerCase()
    if (generic && wantCands.indexOf(generic) >= 0) return entry
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
      // Live Hyprland handle. Urgency and workspace are read off this object
      // directly so the dock follows them without rebuilding the model.
      hypr: hyprFor ? hyprFor(toplevel) : null
    })
  }

  function getWindowsFor(targetId) {
    if (winMap[targetId] && winMap[targetId].length > 0) return winMap[targetId]
    for (var k = 0; k < runningIds.length; k++) {
      var rid = runningIds[k]
      if (isAppMatch(targetId, rid)) {
        return winMap[rid] || []
      }
    }
    return []
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
        var iconFound = ""
        if (appLibrary) {
          var cands = getCandidates(item.appId)
          for (var k = 0; k < cands.length; k++) {
            var cand = cands[k]
            var testSrc = appLibrary.iconSource(cand)
            if (testSrc && testSrc.indexOf("application-x-executable") < 0) {
              iconFound = testSrc
              break
            }
          }
        }
        item.icon = iconFound
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
    var wins = getWindowsFor(pid)
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
    var alreadyPinned = false
    for (var p = 0; p < pinned.length; p++) {
      if (isAppMatch(pinned[p], rid)) {
        alreadyPinned = true
        break
      }
    }
    if (alreadyPinned || seen[rid]) continue
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
    if (t && (stripDesktop(t.appId) === want || isAppMatch(t.appId, want))) matching.push(t)
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
    if (stripDesktop(t.appId) === want || isAppMatch(t.appId, want)) {
      if (t.close) t.close()
      closed += 1
    }
  }
  return closed
}
