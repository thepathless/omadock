// Pure helpers for the dock plugin. No QML state — the host object owns the
// model; this file only turns inputs into output arrays.

var IGNORED_TOKENS = {
  "org": true, "com": true, "io": true, "net": true, "app": true, "apps": true, "bin": true,
  "linux": true, "desktop": true, "client": true, "gui": true, "wrapper": true, "launcher": true,
  "window": true, "default": true, "profile": true, "profile_1": true, "profile_2": true,
  "chrome": true, "chromium": true, "brave": true, "edge": true, "microsoft-edge": true,
  "helium": true, "helium-browser": true, "opera": true, "vivaldi": true,
  "web": true, "omarchy": true,
  "https": true, "http": true, "www": true, "x86_64": true, "x86": true, "amd64": true, "lib": true,
  "wine": true, "extension": true, "exe": true, "electron": true, "run": true, "wayland": true, "x11": true, "gtk3": true, "gtk4": true, "qt5": true, "qt6": true,
  "gnome": true, "kde": true, "freedesktop": true, "mozilla": true, "google": true, "github": true, "gitlab": true,
  "xfce": true, "mate": true, "elementary": true, "flathub": true, "microsoft": true,
  "browser": true, "terminal": true, "system": true, "daemon": true, "service": true,
  "tool": true, "tools": true, "utility": true, "utilities": true, "viewer": true, "player": true,
  "manager": true, "editor": true, "helper": true, "agent": true, "stable": true, "beta": true,
  "dev": true, "nightly": true, "canary": true, "release": true, "community": true
};

function stripDesktop(id) {
  if (typeof id === "object" && id !== null && id.appId) id = id.appId
  var value = String(id == null ? "" : id).trim()
  return value.replace(/\.desktop$/i, "")
}

function isList(v) {
  return Array.isArray(v) || (v !== null && typeof v === "object" && typeof v.length === "number");
}

function toArray(list) {
  if (Array.isArray(list)) return list
  if (!list || typeof list === "string" || typeof list === "function") return []
  if (typeof list.length === "number") {
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
  for (var key in src) {
    if (Object.prototype.hasOwnProperty.call(src, key)) out[key] = src[key]
  }
  return out
}

// Compact workspace label for a tooltip: numbered workspaces only. Special
// workspaces have no number worth showing, so they get nothing.
function workspaceShort(wsId, wsName) {
  var name = String(wsName == null ? "" : wsName).trim()
  if (!name || name.indexOf("special:") === 0 || name === "special") return ""
  var num = Number(wsId)
  if (isNaN(num) || num < 0) {
    if (name.length <= 2 && !isNaN(Number(name)) && Number(name) >= 0) return name
    return ""
  }
  if (name.length <= 2) return name
  return String(wsId)
}


function extractNotificationWebDomain(body, summary) {
  var text = (String(body || "") + "\n" + String(summary || "")).trim()
  if (!text) return ""

  // 1. HTML anchor tag href or text: <a href="https://web.whatsapp.com/">web.whatsapp.com</a>
  var anchorMatch = text.match(/<a\b[^>]*href=["']?(https?:\/\/[^"'>\s]+)["']?[^>]*>/i)
                 || text.match(/href=["']?(https?:\/\/[^"'>\s]+)["']?/i)
  if (anchorMatch && anchorMatch[1]) {
    var rawHost = anchorMatch[1].replace(/^https?:\/\//i, "").split(/[\/?#:]/)[0].replace(/\.+$/, "")
    if (rawHost) return rawHost.toLowerCase()
  }

  // 2. Leading URL or domain string (e.g. web.whatsapp.com, https://music.youtube.com)
  var domainMatch = text.match(/https?:\/\/([a-zA-Z0-9.-]+(?::\d+)?)/i)
                 || text.match(/www\.([a-zA-Z0-9.-]+(?::\d+)?)/i)
                 || text.match(/\b([a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}(?::\d+)?)\b/i)
  if (domainMatch && domainMatch[1]) {
    return domainMatch[1].split(/[\/?#:]/)[0].replace(/\.+$/, "").toLowerCase()
  }

  return ""
}

function getCandidates(id) {
  var raw = stripDesktop(id).toLowerCase()
  if (!raw) return []
  var list = [raw]

  // WebApp extraction (Chrome, Chromium, Brave, Edge, Helium, Opera, Vivaldi PWAs)
  var webAppMatch = raw.match(/^(?:chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(.*?)__?-(?:default|profile.*)$/i)
                 || raw.match(/^(?:chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(.*?)$/i)
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
    if (ca.length >= 3 && !IGNORED_TOKENS[ca] && candsB.indexOf(ca) >= 0) return true
  }
  return false
}

function findNotificationTargets(allEntries, appRows, row) {
  if (!row || !allEntries || allEntries.length === 0) return []

  var appName = String(row.app || "").trim()
  var appIcon = String(row.appIcon || "").trim()
  var summary = String(row.summary || "").trim()
  var body = String(row.body || "").trim()

  var webDomain = extractNotificationWebDomain(body, summary)

  // Pass 1: If a web domain is found, check for a matching WebApp / PWA dock entry
  if (webDomain) {
    var domainCands = getCandidates(webDomain)
    var pwaMatches = []

    for (var i = 0; i < allEntries.length; i++) {
      var entry = allEntries[i]
      if (!entry) continue
      var appId = entry.appId || entry.id

      // A. Check if the dock entry ID matches any domain candidate
      var idMatches = false
      for (var k = 0; k < domainCands.length; k++) {
        if (isAppMatch(appId, domainCands[k])) {
          idMatches = true
          break
        }
      }

      // B. Check entry display name (e.g. "WhatsApp", "YouTube Music")
      var nameMatches = false
      if (entry.name) {
        var nameLower = String(entry.name).toLowerCase()
        for (var k = 0; k < domainCands.length; k++) {
          if (nameLower === domainCands[k] || isAppMatch(entry.name, domainCands[k])) {
            nameMatches = true
            break
          }
        }
      }

      // C. Check underlying desktop entry Exec command (e.g. omarchy-launch-webapp https://web.whatsapp.com/)
      var execMatches = false
      var dEntry = entryFor(appRows, appId)
      if (dEntry && dEntry.exec) {
        var execStr = String(dEntry.exec).toLowerCase()
        if (execStr && (execStr.indexOf("http://") >= 0 || execStr.indexOf("https://") >= 0 || execStr.indexOf("--app") >= 0)) {
          for (var k = 0; k < domainCands.length; k++) {
            var cand = domainCands[k]
            if (cand.length >= 4 && !IGNORED_TOKENS[cand] && execStr.indexOf(cand) >= 0) {
              execMatches = true
              break
            }
          }
        }
      }

      // D. Check running window classes of this entry
      var winMatches = false
      var wins = entry.windowList || []
      for (var w = 0; w < wins.length; w++) {
        var topId = wins[w] ? stripDesktop(wins[w].appId || "") : ""
        if (topId) {
          for (var k = 0; k < domainCands.length; k++) {
            if (isAppMatch(topId, domainCands[k])) {
              winMatches = true
              break
            }
          }
        }
        if (winMatches) break
      }

      if (idMatches || nameMatches || execMatches || winMatches) {
        if (pwaMatches.indexOf(entry) < 0) pwaMatches.push(entry)
      }
    }

    // WebApp Priority Rule: If any specific WebApp entry matched the web origin,
    // attribute the notification EXCLUSIVELY to that PWA and suppress the host browser!
    if (pwaMatches.length > 0) {
      return pwaMatches
    }
  }

  // Pass 2: Standard App Matching (Native Apps, Flatpaks, or generic Browser notifications)
  var standardMatches = []
  for (var i = 0; i < allEntries.length; i++) {
    var entry = allEntries[i]
    if (!entry) continue
    var appId = entry.appId || entry.id

    var iconIsGeneric = appIcon.indexOf("dialog-") === 0
                     || appIcon.indexOf("preferences-") === 0
                     || appIcon.indexOf("system-") === 0
                     || appIcon.indexOf("notification-") === 0
                     || appIcon.indexOf("status-") === 0
                     || appIcon === "folder"

    var match = (appName !== "" && isAppMatch(appId, appName))
             || (appIcon !== "" && !iconIsGeneric && isAppMatch(appId, appIcon))
             || (entry.name && appName && String(entry.name).toLowerCase() === appName.toLowerCase())

    if (match) {
      if (standardMatches.indexOf(entry) < 0) standardMatches.push(entry)
    }
  }

  // Fallback: If no direct app match was found, evaluate summary for generic daemons / CLI notifications
  if (standardMatches.length === 0 && summary !== "") {
    var sumClean = summary.trim()
    var sumIsSingleWord = sumClean.indexOf(" ") < 0
    if (sumIsSingleWord) {
      for (var i = 0; i < allEntries.length; i++) {
        var entry = allEntries[i]
        if (!entry) continue
        var appId = entry.appId || entry.id
        if (isAppMatch(appId, sumClean)) {
          if (standardMatches.indexOf(entry) < 0) standardMatches.push(entry)
        }
      }
    }
  }

  return standardMatches
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
  if (!parsed || typeof parsed !== "object") return []

  var arr = isList(parsed) ? parsed : (isList(parsed.pinned) ? parsed.pinned : [])
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
  var arr = toArray(pinnedIds)
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
  var arr = toArray(pinnedIds).slice()
  var id = stripDesktop(appId)
  if (!id) return arr
  var idx = arr.indexOf(id)
  if (idx < 0) {
    for (var i = 0; i < arr.length; i++) {
      if (isAppMatch(arr[i], id)) {
        idx = i
        break
      }
    }
  }
  if (idx >= 0) arr.splice(idx, 1)
  else arr.push(id)
  return arr
}

function isPinned(pinnedIds, appId) {
  var arr = toArray(pinnedIds)
  var id = stripDesktop(appId)
  if (!id) return false
  if (arr.indexOf(id) >= 0) return true
  for (var i = 0; i < arr.length; i++) {
    if (isAppMatch(arr[i], id)) return true
  }
  return false
}

// Reorder pinned apps: move appId from its current position to insertBeforeId.
// If insertBeforeId is null/empty, move to the end. Dropping onto the dragged
// item itself is a no-op (prevents the "teleport to end" self-drop bug).
function reorderPinned(pinnedIds, appId, insertBeforeId) {
  var arr = toArray(pinnedIds).slice()
  var id = stripDesktop(appId)
  if (!id) return arr
  if (insertBeforeId && stripDesktop(insertBeforeId) === id) return arr

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
    var entry = (row && row.entry) ? row.entry : row
    if (!entry) continue
    if (stripDesktop(entry.id) === want || stripDesktop(entry.id).toLowerCase() === wantLower) return entry
  }

  // 2. Multi-token candidate match (e.g. chrome-x.com__-Default -> X.desktop, org.localsend.localsend_app -> localsend.desktop)
  var wantCands = getCandidates(want)
  for (var i = 0; i < appRows.length; i++) {
    var entry = (appRows[i] && appRows[i].entry) ? appRows[i].entry : appRows[i]
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
    var entry = (appRows[i] && appRows[i].entry) ? appRows[i].entry : appRows[i]
    if (!entry) continue
    var execStr = String(entry.exec || "").toLowerCase()
    if (execStr && (execStr.indexOf("http://") >= 0 || execStr.indexOf("https://") >= 0 || execStr.indexOf("--app") >= 0)) {
      for (var k = 0; k < wantCands.length; k++) {
        var cand = wantCands[k]
        if (cand.length >= 4 && !IGNORED_TOKENS[cand] && execStr.indexOf(cand) >= 0) return entry
      }
    }
  }

  // 4. GenericName / Substring match
  for (var i = 0; i < appRows.length; i++) {
    var entry = (appRows[i] && appRows[i].entry) ? appRows[i].entry : appRows[i]
    if (!entry) continue
    var generic = String(entry.genericName || "").toLowerCase()
    if (generic && wantCands.indexOf(generic) >= 0) return entry
  }

  return null
}

function windowAddress(handle) {
  var value = String((handle && handle.address) || "").trim()
  if (!value) return ""
  if (value.slice(0, 2) === "0x" || value.slice(0, 2) === "0X") value = value.slice(2)
  return "0x" + value.toLowerCase()
}

function buildEntries(pinnedIds, toplevels, appRows, appLibrary, hyprFor, minimizedWs, minimizedOrigins, appGroups) {
  var pinned = toArray(pinnedIds)
  var list = toArray(toplevels)
  var minWs = minimizedWs || "special:minimized"
  var minOrigins = minimizedOrigins || {}

  var groupedMap = {}
  var groups = toArray(appGroups)
  for (var g = 0; g < groups.length; g++) {
    var grp = groups[g]
    if (grp && grp.apps) {
      var gapps = toArray(grp.apps)
      for (var a = 0; a < gapps.length; a++) {
        var ga = stripDesktop(gapps[a])
        if (ga) {
          groupedMap[ga] = true
          var gc = getCandidates(ga)
          for (var c1 = 0; c1 < gc.length; c1++) groupedMap[gc[c1]] = true
        }
      }
    }
  }

  var runningIds = []
  var winMap = {}
  for (var i = 0; i < list.length; i++) {
    var toplevel = list[i]
    if (!toplevel) continue
    var h = hyprFor ? hyprFor(toplevel) : null
    var appId = stripDesktop(toplevel.appId)
    if (!appId && h && h.appId) appId = stripDesktop(h.appId)
    if (!appId && toplevel.title) appId = stripDesktop(toplevel.title)
    if (!appId) continue
    if (!winMap[appId]) {
      winMap[appId] = []
      runningIds.push(appId)
    }
    var addr = windowAddress(h)
    var ws = h ? h.workspace : null
    var wsName = ws ? String(ws.name ? ws.name : (ws.id !== undefined && ws.id !== null ? ws.id : "")) : (addr && minOrigins[addr] ? minWs : "")
    var isParked = (wsName === minWs) || Boolean(addr && minOrigins[addr])
    winMap[appId].push({
      title: String(toplevel.title || "Window"),
      address: addr,
      appId: appId,
      workspaceName: isParked ? minWs : wsName,
      isMinimized: isParked
    })
  }

  function getWindowsFor(targetId) {
    var out = []
    var seenAddr = {}
    for (var k = 0; k < runningIds.length; k++) {
      var rid = runningIds[k]
      if (rid === targetId || isAppMatch(targetId, rid)) {
        var wlist = winMap[rid] || []
        for (var w = 0; w < wlist.length; w++) {
          var item = wlist[w]
          var addr = item ? item.address : ""
          if (addr && !seenAddr[addr]) {
            seenAddr[addr] = true
            out.push(item)
          } else if (!addr) {
            out.push(item)
          }
        }
      }
    }
    return out
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
      id: pid,
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
    var alreadyGrouped = Boolean(groupedMap[rid])
    if (!alreadyGrouped) {
      var rcands = getCandidates(rid)
      for (var rc = 0; rc < rcands.length; rc++) {
        if (groupedMap[rcands[rc]]) {
          alreadyGrouped = true
          break
        }
      }
    }
    if (alreadyPinned || alreadyGrouped || seen[rid]) continue
    seen[rid] = true
    var cands = getCandidates(rid)
    for (var c = 0; c < cands.length; c++) {
      seen[cands[c]] = true
    }
    for (var k2 = 0; k2 < runningIds.length; k2++) {
      if (isAppMatch(rid, runningIds[k2])) {
        seen[runningIds[k2]] = true
      }
    }
    var wins = getWindowsFor(rid)
    runningOut.push({
      id: rid,
      appId: rid,
      pinned: false,
      running: true,
      windows: wins.length,
      windowList: wins
    })
  }
  enrich(runningOut)

  var groupedOut = []
  for (var ga in groupedMap) {
    var gwins = getWindowsFor(ga)
    if (gwins.length > 0) {
      groupedOut.push({
        id: ga,
        appId: ga,
        pinned: false,
        running: true,
        windows: gwins.length,
        windowList: gwins
      })
    }
  }
  enrich(groupedOut)

  return { pinned: pinnedOut, running: runningOut, grouped: groupedOut }
}

// True when the list has at least one window and every one of them is parked
// on the minimized workspace. Used by both the running-icon hide logic and
// the divider gating so the two can never disagree.
//
// liveWsOf/minWs: optional live resolver. The cached isMinimized flag freezes
// at rebuild time and can be stale — Quickshell's Hyprland handle lags silent
// moves onto the special workspace — so callers that can resolve live state
// (the address-based lookup the running-dot uses) must pass it here. A window
// counts as minimized when its cached flag says so OR the live workspace does.
function allWindowsMinimized(windowList, liveWsOf, minWs) {
  var targetWs = minWs || "special:minimized"
  var list = toArray(windowList)
  if (list.length === 0) return false
  for (var i = 0; i < list.length; i++) {
    var w = list[i]
    if (!w) return false
    var liveWs = liveWsOf ? liveWsOf(w) : null
    var ws = (liveWs !== null && liveWs !== undefined && liveWs !== "")
      ? String(liveWs)
      : (w.isMinimized ? targetWs : String(w.workspaceName || ""))
    if (ws !== targetWs) return false
  }
  return true
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
    if (t && (stripDesktop(t.appId) === want || isAppMatch(t.appId, want) || (!t.appId && t.title && (stripDesktop(t.title) === want || isAppMatch(t.title, want))))) {
      matching.push(t)
    }
  }

  if (matching.length === 0) return null
  if (matching.length === 1) return matching[0]

  if (direction === 0) {
    for (var j = 0; j < matching.length; j++) {
      if (matching[j] === activeToplevel || matching[j].activated) return matching[j]
    }
    return matching[0]
  }

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
  try {
    if (toplevel && typeof toplevel.activate === "function") toplevel.activate()
  } catch (e) {}
}

function closeApp(toplevels, appId) {
  var want = stripDesktop(appId)
  if (!want) return 0
  var list = toArray(toplevels)
  var closed = 0
  for (var i = 0; i < list.length; i++) {
    var t = list[i]
    if (!t) continue
    if (stripDesktop(t.appId) === want || isAppMatch(t.appId, want) || (!t.appId && t.title && (stripDesktop(t.title) === want || isAppMatch(t.title, want)))) {
      try {
        if (typeof t.close === "function") {
          t.close()
          closed += 1
        }
      } catch (e) {}
    }
  }
  return closed
}

function folderIconFor(path, explicitIcon) {
  if (explicitIcon) return explicitIcon
  var clean = String(path || "").trim().replace(/\/+$/, "")
  var norm = clean.toLowerCase()
  if (norm === "~" || (norm.indexOf("/home/") === 0 && norm.split("/").length <= 3)) return "user-home"
  var baseName = norm.split("/").pop() || ""
  if (baseName.indexOf("download") >= 0) return "folder-download"
  if (baseName.indexOf("document") >= 0) return "folder-documents"
  if (baseName.indexOf("picture") >= 0) return "folder-pictures"
  if (baseName.indexOf("music") >= 0) return "folder-music"
  if (baseName.indexOf("video") >= 0) return "folder-videos"
  if (baseName.indexOf("desktop") >= 0) return "user-desktop"
  if (baseName.indexOf("template") >= 0) return "folder-templates"
  if (baseName.indexOf("public") >= 0) return "folder-publicshare"
  if (baseName.indexOf("trash") >= 0) return "user-trash"
  return "folder"
}

function resolveThemedFolderIcon(iconName, themeName, folderColorMode) {
  var name = String(iconName || "folder").trim()
  if (name.indexOf("/") === 0 || name.indexOf("file://") === 0) return name

  // Standardize known place aliases that don't have dedicated icons in Adwaita/Yaru
  var placeAliases = {
    "folder-development": "folder",
    "folder-projects": "folder",
    "folder-code": "folder",
    "folder-git": "folder",
    "folder-github": "folder",
    "folder-src": "folder",
    "folder-source": "folder",
    "folder-build": "folder"
  }
  if (placeAliases[name]) {
    name = placeAliases[name]
  }

  // Whitelist of valid place icons guaranteed to exist in Adwaita / Yaru place icon themes
  var validPlaces = [
    "folder", "folder-documents", "folder-download", "folder-music",
    "folder-pictures", "folder-publicshare", "folder-remote",
    "folder-templates", "folder-videos", "user-home", "user-desktop", "user-trash"
  ]
  if (validPlaces.indexOf(name) < 0) {
    name = "folder"
  }

  // Explicit white, black, or symbolic mode:
  if (folderColorMode === "white" || folderColorMode === "black" || folderColorMode === "symbolic") {
    return "file:///usr/share/icons/Adwaita/symbolic/places/" + name + "-symbolic.svg"
  }

  // Explicit custom Yaru color preset:
  if (folderColorMode && folderColorMode !== "theme" && folderColorMode !== "auto") {
    var customTheme = folderColorMode
    if (customTheme.indexOf("Yaru") === 0) {
      return "file:///usr/share/icons/" + customTheme + "/256x256/places/" + name + ".png"
    }
  }

  // Automatic theme mode:
  var theme = String(themeName || "").trim()

  // 1. If valid Yaru variant theme (e.g. Yaru-sage, Yaru-olive, Yaru-magenta, Yaru-purple, Yaru-blue, Yaru-red, Yaru-yellow, Yaru)
  if (theme.indexOf("Yaru-") === 0 && theme !== "Yaru-gray" && theme !== "Yaru-grey") {
    return "file:///usr/share/icons/" + theme + "/256x256/places/" + name + ".png"
  }
  if (theme === "Yaru") {
    return "file:///usr/share/icons/Yaru/256x256/places/" + name + ".png"
  }

  // 2. For Vantablack / minimal themes (Yaru-gray / unstyled):
  // Nautilus displays the clean monochrome symbolic outline icon!
  return "file:///usr/share/icons/Adwaita/symbolic/places/" + name + "-symbolic.svg"
}

function resolveFileItemIcon(iconName, themeName, folderColorMode) {
  var name = String(iconName || "text-x-generic").trim()
  if (name.indexOf("/") === 0 || name.indexOf("file://") === 0) return name

  // If it is a folder / place icon:
  if (name === "folder" || name.indexOf("folder-") === 0 || name.indexOf("user-") === 0) {
    return resolveThemedFolderIcon(name, themeName, folderColorMode)
  }

  // Known mimetypes
  var knownMimetypes = [
    "image-x-generic", "video-x-generic", "audio-x-generic",
    "package-x-generic", "application-pdf", "text-x-generic",
    "application-x-executable"
  ]
  if (knownMimetypes.indexOf(name) >= 0) {
    return "file:///usr/share/icons/Yaru/256x256/mimetypes/" + name + ".png"
  }

  return "file:///usr/share/icons/Yaru/256x256/mimetypes/text-x-generic.png"
}

function resolveAppIcon(appLibrary, appRows, appId) {
  var id = String(appId || "").trim()
  if (!id) return appLibrary ? appLibrary.iconSource("application-x-executable") : ""

  // 1. If an absolute file path is passed
  if (id.indexOf("/") === 0 || id.indexOf("file://") === 0) {
    return id.indexOf("file://") === 0 ? id : ("file://" + id)
  }

  // 2. Look up desktop entry
  var entry = entryFor(appRows, id)
  if (entry && entry.icon && appLibrary) {
    var src = appLibrary.iconSource(entry.icon)
    if (src && src.indexOf("application-x-executable") < 0) return src
  }

  // 3. Look up candidate tokens in appLibrary
  if (appLibrary) {
    var cands = getCandidates(id)
    for (var k = 0; k < cands.length; k++) {
      var cand = cands[k]
      var testSrc = appLibrary.iconSource(cand)
      if (testSrc && testSrc.indexOf("application-x-executable") < 0) return testSrc
    }
    var directSrc = appLibrary.iconSource(id)
    if (directSrc && directSrc.indexOf("application-x-executable") < 0) return directSrc
  }

  // 4. Try Quickshell.iconPath fallback
  try {
    var qp = Quickshell.iconPath(entry && entry.icon ? entry.icon : id, true)
    if (qp && qp !== "") return qp
  } catch (e) {}

  // 5. Ultimate fallback
  if (appLibrary) {
    var fallback = appLibrary.iconSource("application-x-executable")
    if (fallback) return fallback
  }
  try {
    return Quickshell.iconPath("application-x-executable", true)
  } catch (e2) {
    return ""
  }
}

function resolveAppName(appLibrary, appRows, appId) {
  var id = String(appId || "").trim()
  if (!id) return ""
  var entry = entryFor(appRows, id)
  if (entry) {
    if (appLibrary && typeof appLibrary.entryName === "function") {
      var n = appLibrary.entryName(entry)
      if (n) return n
    }
    if (entry.name) return entry.name
  }
  return id
}
