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
  "video": true, "audio": true, "chat": true, "files": true, "file": true, "media": true,
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

function normalizeId(id) { return stripDesktop(id) }

function copyMap(src) {
  var out = {}
  for (var key in src) {
    if (Object.prototype.hasOwnProperty.call(src, key)) out[key] = src[key]
  }
  return out
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

// The id spellings that name a CLI or agent product: the TUI launcher's command
// name, the product name, or a reverse-DNS desktop id. One table, one answer.
function cliAppId(id) {
  var raw = stripDesktop(id)
  if (/^(?:org\.omarchy\.)?agy$/i.test(raw)) return "antigravity"
  if (/^org\.omarchy\.btop(?:-.*)?$/i.test(raw)) return "btop"
  if (/^(?:com\.anthropic\.)?claude(?:-code)?$/i.test(raw)) return "claude"
  if (/^aider(?:-chat)?$/i.test(raw)) return "aider"
  if (/^(?:com\.cursor\.)?cursor(?:-bin)?$/i.test(raw)) return "cursor"
  if (/^(?:com\.codeium\.)?windsurf$/i.test(raw)) return "windsurf"
  if (/^ollama(?:-app)?$/i.test(raw)) return "ollama"
  if (/^(?:github-)?copilot(?:-cli)?$/i.test(raw)) return "copilot"
  if (/^open-?interpreter$/i.test(raw)) return "interpreter"
  return raw
}

// The two CLI products the dock learns to identify. Nothing else takes the
// TUI app-id launch path — every other terminal entry launches normally.
function isKnownCli(id) {
  var raw = cliAppId(id).toLowerCase()
  return raw === "antigravity" || raw === "btop"
}

// Every id a badge count may be filed under for one dock item. CLI products
// arrive under several spellings (pin id, TUI app-id, product name); keeping
// the list here means DockItem never has to know the mapping.
function notificationAliasIds(appId) {
  var raw = String(appId == null ? "" : appId)
  var canonical = cliAppId(raw).toLowerCase()
  if (canonical === "antigravity") return [raw, "antigravity", "agy", "org.omarchy.agy"]
  if (canonical === "btop") return [raw, "btop", "org.omarchy.btop"]
  return [raw]
}

// A dock rebuild runs on every window title change and asks this ~1200 times
// for a few dozen ids, so each answer is kept per id string. Callers get copies.
var candidateCache = Object.create(null), candidateCacheSize = 0
function getCandidates(id) {
  if (typeof id !== "string") return computeCandidates(id)
  var known = candidateCache[id]
  if (known) return known.slice()
  if (++candidateCacheSize > 4096) { candidateCache = Object.create(null); candidateCacheSize = 1 }
  return (candidateCache[id] = computeCandidates(id)).slice()
}

function computeCandidates(id) {
  // The id as written, plus its canonical name: a candidate set never shrinks.
  var raw = stripDesktop(id).toLowerCase(), canon = cliAppId(id).toLowerCase()
  if (!raw) return []
  var list = [raw]
  if (canon !== raw) list.push(canon)
  function addCandidate(part) { if (part && list.indexOf(part) < 0) list.push(part) }

  // WebApp extraction (Chrome, Chromium, Brave, Edge, Helium, Opera, Vivaldi PWAs)
  var webAppMatch = raw.match(/^(?:google-chrome|google-chrome-stable|chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(.*?)__?-(?:default|profile.*)$/i)
                 || raw.match(/^(?:google-chrome|google-chrome-stable|chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(.*?)$/i)
  if (webAppMatch) {
    var webTarget = webAppMatch[1].replace(/^https?___?/i, "").replace(/__.*$/, "")
    if (webTarget && list.indexOf(webTarget) < 0) list.push(webTarget)
    webTarget.split(/[\.\/_]+/).forEach(addCandidate)
  }

  // Split by dots, underscores, dashes, slashes
  raw.split(/[\.\/_-]+/).forEach(addCandidate)

  var len = list.length
  for (var i = 0; i < len; i++) {
    var item = list[i]
    var stripped = item.replace(/[-_](app|bin|linux|gtk|wrapper|desktop|client|qt\d?|gui)$/i, "")
    if (stripped && list.indexOf(stripped) < 0) list.push(stripped)
    var prefixStripped = item.replace(/^(app|bin|linux|gtk|wrapper|desktop|client|qt\d?|gui)[-_]/i, "")
    if (prefixStripped && list.indexOf(prefixStripped) < 0) list.push(prefixStripped)
  }

  // Every push above skips duplicates, so only vendor tokens need dropping.
  return list.filter(function (s) { return s && !IGNORED_TOKENS[s] })
}

function isAppMatch(idA, idB) {
  if (!idA || !idB) return false
  var a = cliAppId(idA).toLowerCase()
  var b = cliAppId(idB).toLowerCase()
  if (a === b) return true

  var candsA = getCandidates(idA)
  var candsB = getCandidates(idB)
  for (var i = 0; i < candsA.length; i++) {
    var ca = candsA[i]
    if (!ca || IGNORED_TOKENS[ca]) continue
    if (candsB.indexOf(ca) >= 0) {
      if (ca === a || ca === b) return true
      if (ca.length >= 4) return true
    }
  }
  return false
}

function findNotificationTargets(allEntries, appRows, row) {
  if (!row || !allEntries || allEntries.length === 0) return []
  var attributed = []
  function add(entry) {
    if (entry && attributed.indexOf(entry) < 0) attributed.push(entry)
  }
  // Map exact Omarchy TUI app-ids and the native Antigravity CLI name,
  // independent of window-list folding or the generic terminal host.
  var cliApp = String(row.app || "").trim()
  var cliTarget = isKnownCli(cliApp) ? cliAppId(cliApp).toLowerCase() : ""
  if (cliTarget) {
    for (var c = 0; c < allEntries.length; c++) {
      var candidate = allEntries[c]
      if (candidate && isAppMatch(candidate.appId || candidate.id, cliTarget)) add(candidate)
    }
    if (attributed.length) return attributed
  }

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
      if (dEntry && (dEntry.execString || dEntry.exec)) {
        var execStr = String(dEntry.execString || dEntry.exec).toLowerCase()
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

// Popups in rows that were not in the previous snapshot, told apart by
// their timestamp (rows without one cannot be told apart and are skipped).
// Feeds urgency from the popup-file watch when the shell's notification
// service is not available to the dock.
function newPopupRows(previous, rows) {
  var seen = {}
  var prev = Array.isArray(previous) ? previous : []
  for (var i = 0; i < prev.length; i++) {
    var t = prev[i] ? prev[i].timestamp : 0
    if (typeof t === "number" && t > 0) seen[t] = true
  }
  var out = []
  var list = Array.isArray(rows) ? rows : []
  for (var j = 0; j < list.length; j++) {
    var r = list[j]
    var ts = r ? r.timestamp : 0
    if (typeof ts === "number" && ts > 0 && !seen[ts]) out.push(r)
  }
  return out
}

// Badge attribution: which dock entries each row counts against. Grouped and
// unpinned entries count too — whether a count is shown (pinned only, or at
// all) is the UI's decision. The 512-row bound keeps a hostile snapshot from
// amplifying attribution work. A fresh count of active popups, not unread
// messages or notification history: rebuilding from the model handles
// replacements and removals without drift.
function notificationCounts(entries, appRows, rows) {
  var counts = {}
  if (!Array.isArray(rows)) return counts
  for (var i = 0; i < Math.min(rows.length, 512); i++) {
    var matches = findNotificationTargets(entries, appRows, rows[i])
    for (var m = 0; m < matches.length; m++) {
      var id = matches[m].appId || matches[m].id
      if (id) counts[id] = (counts[id] || 0) + 1
    }
  }
  return counts
}

// One row's identity for the sticky badge store: the notification's own
// timestamp/id when it carries one, else a content fingerprint. The file-watch
// fallback (scripts/notification-popups.py) emits rows with neither field and
// re-emits its whole snapshot on every change, so without the fingerprint the
// same popups would count again on each re-emission.
function notificationRowKey(row) {
  if (!row) return ""
  var ts = String(row.timestamp == null ? "" : row.timestamp)
  var id = String(row.id == null ? "" : row.id)
  if (ts || id) return ts + "-" + id
  return String(row.app || "") + "\u0000" + String(row.summary || "") + "\u0000" + String(row.body || "")
}

// Sticky badge counts: +n under each of ids, at most once per spelling.
// Returns a new map; the input is never touched. Counts stay plain
// non-negative integers — the 99+ cap is a display concern.
function bumpNotificationCounts(map, ids, n) {
  var out = copyMap(map || {})
  var step = (typeof n === "number" && isFinite(n)) ? Math.round(n) : 1
  if (step <= 0) return out
  var list = Array.isArray(ids) ? ids : (ids == null ? [] : [ids])
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var id = String(list[i] == null ? "" : list[i])
    if (!id || seen[id]) continue
    seen[id] = true
    var cur = (typeof out[id] === "number" && isFinite(out[id])) ? Math.max(0, Math.floor(out[id])) : 0
    out[id] = cur + step
  }
  return out
}

// Drop the sticky counts filed under appId: every spelling
// notificationAliasIds knows for it (CLI products file under several).
// Returns a new map; the input is never touched.
function clearNotificationCounts(map, appId) {
  var out = copyMap(map || {})
  var ids = notificationAliasIds(appId)
  for (var i = 0; i < ids.length; i++) {
    var id = String(ids[i] == null ? "" : ids[i])
    if (id && out[id] !== undefined) delete out[id]
  }
  return out
}

// Sticky badge state for the state dir: the counts plus the dedupe keys of
// rows already counted, so a shell restart resumes exactly where the session
// left off (README: counts stay until the app is focused). Everything is
// bounded on the way out — ids, keys, counts — so a long session can never
// grow the file without limit; parseBadgeState treats anything unreadable as
// "no badges": the file is persisted memory, never a source of truth.
function serializeBadgeState(counts, seenOrder) {
  var out = { counts: {}, seen: [] }
  var n = 0
  if (counts && typeof counts === "object") {
    var ids = Object.keys(counts)
    for (var i = 0; i < ids.length && n < MAX_BADGE_IDS; i++) {
      var key = String(ids[i] == null ? "" : ids[i]).slice(0, MAX_BADGE_KEY)
      var val = Math.round(Number(counts[ids[i]]))
      if (!key || !isFinite(val) || val <= 0) continue
      out.counts[key] = Math.min(val, MAX_BADGE_COUNT)
      n++
    }
  }
  if (Array.isArray(seenOrder)) {
    for (var j = 0; j < seenOrder.length && out.seen.length < MAX_BADGE_SEEN; j++) {
      var s = String(seenOrder[j] == null ? "" : seenOrder[j]).slice(0, MAX_BADGE_KEY)
      if (s) out.seen.push(s)
    }
  }
  return JSON.stringify(out)
}

function parseBadgeState(raw) {
  var empty = { counts: {}, seenKeys: {}, seenOrder: [] }
  var txt = readCapped(raw, MAX_BADGE_BYTES).trim()
  if (!txt) return empty
  var obj = null
  try {
    obj = JSON.parse(txt)
  } catch (e) {
    return empty
  }
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) return empty
  var out = { counts: {}, seenKeys: {}, seenOrder: [] }
  var counts = (obj.counts && typeof obj.counts === "object" && !Array.isArray(obj.counts)) ? obj.counts : {}
  var ids = Object.keys(counts)
  var n = 0
  for (var i = 0; i < ids.length && n < MAX_BADGE_IDS; i++) {
    var key = String(ids[i] == null ? "" : ids[i]).slice(0, MAX_BADGE_KEY)
    var val = Math.round(Number(counts[ids[i]]))
    if (!key || !isFinite(val) || val <= 0) continue
    out.counts[key] = Math.min(val, MAX_BADGE_COUNT)
    n++
  }
  var seen = Array.isArray(obj.seen) ? obj.seen : []
  for (var j = 0; j < seen.length && out.seenOrder.length < MAX_BADGE_SEEN; j++) {
    var s = String(seen[j] == null ? "" : seen[j]).slice(0, MAX_BADGE_KEY)
    if (!s || out.seenKeys[s]) continue
    out.seenKeys[s] = true
    out.seenOrder.push(s)
  }
  return out
}

// The badge total a folder tile shows: the counts of every member app summed
// through notificationAliasIds, each spelling counted once so members filed
// under aliases (or two members sharing one) never inflate the total.
function groupBadgeTotal(groupApps, counts) {
  var list = toArray(groupApps)
  var map = counts || {}
  var seen = {}
  var total = 0
  for (var i = 0; i < list.length; i++) {
    var ids = notificationAliasIds(list[i])
    for (var k = 0; k < ids.length; k++) {
      var id = String(ids[k] == null ? "" : ids[k])
      if (!id || seen[id]) continue
      seen[id] = true
      var v = map[id]
      if (typeof v === "number" && isFinite(v) && v > 0) total += Math.floor(v)
    }
  }
  return total
}

function parsePinned(raw) {
  var text = String(raw == null ? "" : raw).trim()
  if (!text) return []

  var parsed = null
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    console.warn("[omadock] Failed parsing dock.json, keeping no pins:", e)
    return []
  }
  if (!parsed || typeof parsed !== "object") return []

  // Real arrays only (see boundList).
  var arr = Array.isArray(parsed) ? parsed : (Array.isArray(parsed.pinned) ? parsed.pinned : [])
  var out = []
  var seen = Object.create(null)
  for (var i = 0; i < Math.min(arr.length, 256); i++) {
    if (typeof arr[i] !== "string" || arr[i].length > 512) continue
    var id = stripDesktop(arr[i])
    if (!id || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

// ------------------------------------------------- safety ceilings
//
// Mutable config/theme/notification files are read by the long-lived shell
// process, so every read is gated by a byte ceiling and every persisted
// collection is bounded before it can reach dock state. Limits are 25-100x the
// largest legitimate file the dock itself writes, so valid configs behave
// byte-for-byte identically; only hostile or corrupted inputs get rejected.

var MAX_CONFIG_BYTES = 1048576        // omadock.json (largest real file ~40 KB)
var MAX_DOCK_JSON_BYTES = 65536       // dock.json (largest real file ~2 KB)
var MAX_ICONS_THEME_BYTES = 4096      // icons.theme (one line)
var MAX_COLORS_TOML_BYTES = 262144    // colors.toml (~10 KB)
var MAX_NOTIFICATIONS_BYTES = 16384   // notifications.json (~60 bytes)
var MAX_BADGE_BYTES = 16384           // omadock-badges.json (sticky badge state)
var MAX_BADGE_IDS = 256
var MAX_BADGE_SEEN = 512
var MAX_BADGE_KEY = 128
var MAX_BADGE_COUNT = 9999

var MAX_APP_GROUPS = 32
var MAX_APP_GROUP_NAME = 120
var MAX_APP_GROUP_ICON = 120
var MAX_APP_GROUP_ID = 120
var MAX_APP_GROUP_APPS = 16
var MAX_PINNED_FOLDERS = 12
var MAX_FOLDER_PATH = 512
var MAX_FOLDER_NAME = 120
var MAX_FOLDER_ICON = 120

var MAX_SYSTEM_BLUR_SIZE = 100

// Hyprland's own blur size as remembered in the config: an integer in
// 0..MAX_SYSTEM_BLUR_SIZE (0 = not remembered). It is written back to
// decoration.blur.size, where a huge value stalls the compositor.
function boundSystemBlurSize(v) {
  if (typeof v !== "number" || !isFinite(v)) return 0
  return Math.max(0, Math.min(MAX_SYSTEM_BLUR_SIZE, Math.round(v)))
}

// A sound theme id for canberra-gtk-play -i, or "none"; anything else
// (a path, "../x") falls back to "bell".
function cleanSoundName(v) {
  return (typeof v === "string" && /^[a-z0-9][a-z0-9-]{0,47}$/.test(v)) ? v : "bell"
}

// Byte ceiling applied to text read from a watched file. The returned slice is
// never parsed further when the file exceeds the cap, so an oversized file can
// neither grow shell memory nor amplify parse work. Oversize input yields "".
function readCapped(raw, maxBytes) {
  var text = String(raw == null ? "" : raw)
  if (!maxBytes || maxBytes <= 0) maxBytes = MAX_CONFIG_BYTES
  // Char-count approximation: UTF-8 chars occupy 1-4 bytes, so chars <= bytes.
  // A slice that fits by chars is guaranteed to fit by bytes when kept small;
  // checking bytes-per-char keeps the cap honest for multibyte content.
  if (text.length <= maxBytes) {
    var bytes = 0
    for (var i = 0; i < text.length; i++) {
      var c = text.charCodeAt(i)
      if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length
          && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
        bytes += 4
        i++
      } else {
        bytes += c < 0x80 ? 1 : (c < 0x800 ? 2 : 3)
      }
      if (bytes > maxBytes) return ""
    }
    return text
  }
  return ""
}

// The object saveConfig merges the dock's keys into: {} for an empty file,
// the parsed object otherwise, and null when the file holds anything else
// (a typo, an array, a string). null means "do not write": rewriting from
// {} would silently drop every key the dock does not own.
function configBase(text) {
  var t = String(text == null ? "" : text).trim()
  if (!t) return {}
  var parsed
  try {
    parsed = JSON.parse(t)
  } catch (e) {
    return null
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
  return parsed
}

// Shape-bound generic list: keeps at most `max` entries that pass `predicate`.
// Real arrays only: JSON gives nothing else, and an array-like object
// ({ "length": 1e9 }) would be walked to its claimed length.
function boundList(arr, max, predicate) {
  // Real arrays only: JSON gives nothing else, and an array-like object
  // ({ "length": 1e9 }) would be walked to its claimed length.
  if (!Array.isArray(arr)) return []
  var out = []
  for (var i = 0; i < arr.length && out.length < max; i++) {
    var v = arr[i]
    if (predicate(v)) out.push(v)
  }
  return out
}

function _boundedStr(v, max) {
  var s = String(v == null ? "" : v).trim()
  return s.length > max ? "" : s
}

// Persisted app groups: drop malformed entries, cap counts and field lengths.
// Keeps the exact { id, name, icon, apps, cols } shape the dock writes.
function boundAppGroups(arr) {
  return boundList(arr, MAX_APP_GROUPS, function(g) {
    if (!g || typeof g !== "object" || isList(g)) return false
    if (!_boundedStr(g.id, MAX_APP_GROUP_ID)) return false
    return true
  }).map(function(g) {
    var apps = boundList(g.apps, MAX_APP_GROUP_APPS, function(a) {
      return !!_boundedStr(a, MAX_APP_GROUP_ID)
    }).map(function(a) { return _boundedStr(a, MAX_APP_GROUP_ID) })
    var name = _boundedStr(g.name, MAX_APP_GROUP_NAME)
    return {
      id: _boundedStr(g.id, MAX_APP_GROUP_ID),
      name: name || "Group",
      icon: _boundedStr(g.icon, MAX_APP_GROUP_ICON) || "folder",
      apps: apps,
      cols: Math.max(1, Math.min(6, Math.round(Number(g.cols) || 3))),
      // Pinned app the group stands before in the dock; "" for the end.
      before: _boundedStr(g.before, MAX_APP_GROUP_ID) || ""
    }
  })
}

// ---------------------------------------------------------------- pinned row
// Pinned apps and app groups share one run of the dock. Pins keep their own
// order (pinnedIds); each group records the pinned app it stands before
// (group.before, "" for the end of the run).

// The run in dock order: { kind: "app", appId, entry } and { kind: "group",
// id, group } items. Groups whose app is not in entries go to the end; groups
// before the same app keep their order in groups.
function pinnedRow(entries, groups) {
  var apps = toArray(entries)
  var list = toArray(groups)
  var present = {}
  for (var i = 0; i < apps.length; i++) if (apps[i]) present[apps[i].appId] = true
  var byAnchor = {}
  var tail = []
  for (var g = 0; g < list.length; g++) {
    var grp = list[g]
    if (!grp) continue
    var item = { kind: "group", id: grp.id, group: grp }
    var anchor = grp.before || ""
    if (anchor && present[anchor]) (byAnchor[anchor] = byAnchor[anchor] || []).push(item)
    else tail.push(item)
  }
  var row = []
  for (var a = 0; a < apps.length; a++) {
    var e = apps[a]
    if (!e) continue
    var before = byAnchor[e.appId] || []
    for (var b = 0; b < before.length; b++) row.push(before[b])
    row.push({ kind: "app", appId: e.appId, entry: e })
  }
  return row.concat(tail)
}

// Pins and groups that put the dock in the order of row: pins in row order
// (with any pinned id the row does not show kept at the end), and each group
// standing before the next app after it in the row.
function rowState(row, pinnedIds) {
  var items = toArray(row)
  var pins = []
  var groups = []
  var pending = []
  for (var i = 0; i < items.length; i++) {
    var it = items[i]
    if (!it) continue
    if (it.kind === "app") {
      pins.push(it.appId)
      for (var p = 0; p < pending.length; p++) pending[p].before = it.appId
      pending = []
    } else if (it.kind === "group") {
      var copy = {}
      for (var k in it.group) copy[k] = it.group[k]
      copy.before = ""
      groups.push(copy)
      pending.push(copy)
    }
  }
  var shown = {}
  for (var s = 0; s < pins.length; s++) shown[pins[s]] = true
  var ids = toArray(pinnedIds)
  for (var r = 0; r < ids.length; r++) if (!shown[ids[r]]) pins.push(ids[r])
  return { pins: pins, groups: groups }
}

// The row with a group dissolved: its apps take its place, in the group's
// order, skipping any the row already shows as pinned.
function ungroupRow(row, groupId) {
  var items = toArray(row)
  var shown = {}
  for (var i = 0; i < items.length; i++) {
    if (items[i] && items[i].kind === "app") shown[items[i].appId] = true
  }
  var out = []
  for (var j = 0; j < items.length; j++) {
    var it = items[j]
    if (!it || it.kind !== "group" || it.id !== groupId) { out.push(it); continue }
    var apps = toArray(it.group.apps)
    for (var a = 0; a < apps.length; a++) {
      var id = apps[a]
      if (!id || shown[id]) continue
      shown[id] = true
      out.push({ kind: "app", appId: id })
    }
  }
  return out
}

// Groups re-anchored for a change of pins: a group whose app is no longer
// pinned moves before the next app after it in oldPins that still is.
function reanchorGroups(groups, oldPins, newPins) {
  var list = toArray(groups)
  var older = toArray(oldPins)
  var kept = {}
  var newer = toArray(newPins)
  for (var n = 0; n < newer.length; n++) kept[newer[n]] = true
  var changed = false
  var out = list.map(function(g) {
    if (!g || !g.before || kept[g.before]) return g
    var from = older.indexOf(g.before)
    var anchor = ""
    for (var i = from + 1; from >= 0 && i < older.length; i++) {
      if (kept[older[i]]) { anchor = older[i]; break }
    }
    var copy = {}
    for (var k in g) copy[k] = g[k]
    copy.before = anchor
    changed = true
    return copy
  })
  return changed ? out : list
}

// Persisted pinned folders: drop malformed entries, cap counts and lengths.
// Stack orders a pinned folder may carry (scripts/list-folder.py).
var FOLDER_SORTS = ["name", "kind", "modified", "added", "size"]

function boundPinnedFolders(arr) {
  return boundList(arr, MAX_PINNED_FOLDERS, function(f) {
    if (!f || typeof f !== "object" || isList(f)) return false
    // Absolute or home-relative only: the path reaches xdg-open, which has
    // no "--", so a relative "-x" would be read as an option.
    var p = _boundedStr(f.path, MAX_FOLDER_PATH)
    return !!p && (p.charAt(0) === "/" || p === "~" || p.indexOf("~/") === 0)
  }).map(function(f) {
    return {
      path: _boundedStr(f.path, MAX_FOLDER_PATH),
      name: _boundedStr(f.name, MAX_FOLDER_NAME) || "Folder",
      icon: _boundedStr(f.icon, MAX_FOLDER_ICON) || "folder",
      sort: FOLDER_SORTS.indexOf(f.sort) >= 0 ? f.sort : "modified",
      view: f.view === "grid" ? "grid" : "stack"
    }
  })
}

// ---------------------------------------------------------------- presets
// A preset is a named copy of the dock's look: the config keys below, as
// saveConfig writes them, each with the value it takes when the config lacks
// it (Dock.applyLook's fallbacks). Values reach the dock only through
// applyLook, so a preset can hold nothing the file could not; a key added
// after a preset was saved gets its default, as the dock then looked.
var DEFAULT_LOOK = {
  showBackground: true, bgColor: "theme", bgFill: "solid", gradientPreset: "theme", gradientStrength: 0.6,
  grain: 0, opacity: 1, blur: "system", showShadow: true, shadowStrength: 0.4, showBorder: true,
  borderWidth: 1.5, borderOpacity: "theme", shape: "rounded", cornerRadius: -1, splitSections: false,
  dividerGeometry: "classic", dividerHeight: 70, dividerStyle: "simple", dividerWidth: 1.5, dividerOpacity: 0.4,
  iconStyle: "original", iconTint: "text", iconHoverOriginal: false, iconHoverReveal: false, iconContrast: 0, iconStrength: 1,
  iconGrid: 16, indicatorShape: "theme", hoverEffect: "zoom", launchBounce: true, groupStyle: "rounded",
  groupIconEffects: "theme", folderColor: "theme", iconSize: 0, itemSpacing: 4, sectionSpacing: 18, labelMode: "off",
  labelKind: "all", labelFont: "theme", labelSize: "medium", labelColor: "auto", labelBackground: "none", labelReveal: "slide",
  labelEffect: "none", labelMaxWidth: 140, labelWeight: "medium", labelShape: "dock", labelIndicators: "before", labelPlateHeight: "icon", labelPinned: "always"
}
var LOOK_KEYS = Object.keys(DEFAULT_LOOK)
var MAX_PRESETS = 6
var MAX_PRESET_NAME = 40
var MAX_PRESET_ID = 64
var MAX_LOOK_STRING = 64

// Every look key of a config-shaped object, scalars only, strings capped;
// a missing or non-scalar one gets its DEFAULT_LOOK value.
function pickLook(conf) {
  var src = (conf && typeof conf === "object") ? conf : {}
  var out = {}
  for (var i = 0; i < LOOK_KEYS.length; i++) {
    var k = LOOK_KEYS[i]
    var v = Object.prototype.hasOwnProperty.call(src, k) ? src[k] : undefined
    if (typeof v === "string") out[k] = v.slice(0, MAX_LOOK_STRING)
    else if (typeof v === "boolean" || (typeof v === "number" && isFinite(v))) out[k] = v
    else out[k] = DEFAULT_LOOK[k]
  }
  return out
}

// Every look key the preset holds has the same value in cur. (Presets are
// read through pickLook, so they hold every key.)
function lookIncludes(cur, look) {
  var x = cur || {}
  var y = look || {}
  for (var i = 0; i < LOOK_KEYS.length; i++) {
    var k = LOOK_KEYS[i]
    if (!Object.prototype.hasOwnProperty.call(y, k)) continue
    if (JSON.stringify(x[k]) !== JSON.stringify(y[k])) return false
  }
  return true
}

// Trimmed, without control or bidi characters, at most MAX_PRESET_NAME.
function cleanPresetName(s) {
  var t = String(s == null ? "" : s)
    .replace(/[\u0000-\u001f\u007f-\u009f​-‏‪-‮⁦-⁩]/g, "")
    .replace(/\s+/g, " ")
    .trim()
  return t.slice(0, MAX_PRESET_NAME).trim()
}

// Persisted presets: valid id and name, an object look, unique ids, at most
// MAX_PRESETS. Looks are reduced to the look keys.
function boundPresets(arr) {
  // Real arrays only: JSON gives nothing else, and an array-like object
  // ({ "length": 1e9 }) would be walked to its claimed length.
  if (!Array.isArray(arr)) return []
  var src = arr
  var seen = Object.create(null)
  var out = []
  for (var i = 0; i < src.length && out.length < MAX_PRESETS; i++) {
    var p = src[i]
    if (!p || typeof p !== "object") continue
    var id = typeof p.id === "string" ? p.id : ""
    if (!/^[A-Za-z0-9_]{1,64}$/.test(id) || seen[id]) continue
    var name = cleanPresetName(p.name)
    if (name === "" || !p.look || typeof p.look !== "object" || isList(p.look)) continue
    seen[id] = true
    out.push({ id: id, name: name, look: pickLook(p.look) })
  }
  return out
}

// Local absolute paths from dropped file:// URLs. A path with a line break
// is dropped: the folder probes print one path per line, so "a\n/etc"
// would come back as two paths. Malformed escapes are skipped.
function localPathsFromUrls(urls) {
  var list = toArray(urls)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var u = String(list[i])
    if (u.indexOf("file://") !== 0) continue
    var p
    try {
      p = decodeURIComponent(u.slice(7))
    } catch (e) {
      continue
    }
    if (p.charAt(0) === "/" && !/[\r\n]/.test(p)) out.push(p)
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
  var idx = -1
  for (var i = 0; i < arr.length; i++) {
    if (stripDesktop(arr[i]) === id) {
      idx = i
      break
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
  for (var i = 0; i < arr.length; i++) {
    if (stripDesktop(arr[i]) === id) return true
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
  if (fromIdx >= 0) {
    arr.splice(fromIdx, 1)
  }

  if (!insertBeforeId) {
    arr.push(id)
  } else {
    var toIdx = arr.indexOf(stripDesktop(insertBeforeId))
    if (toIdx < 0) arr.push(id)
    else arr.splice(toIdx, 0, id)
  }
  return arr
}

// A copy of list with the item at from moved before the item now at
// insertIndex (to the end when insertIndex is past the last item). Returns
// list itself when nothing moves.
function moveBefore(list, from, insertIndex) {
  var arr = toArray(list)
  if (from < 0 || from >= arr.length) return list
  var to = Math.max(0, Math.min(arr.length, insertIndex))
  if (to === from || to === from + 1) return list
  var next = arr.slice()
  var moved = next.splice(from, 1)[0]
  next.splice(to > from ? to - 1 : to, 0, moved)
  return next
}

function entryFor(appRows, appId) {
  var want = cliAppId(appId)
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
      .concat(getCandidates(String(entry.icon || "").replace(/^.*\//, "")))
    for (var k = 0; k < wantCands.length; k++) {
      var cand = wantCands[k]
      if (entryCands.indexOf(cand) >= 0) return entry
    }
  }

  // 3. Webapp Exec URL Match (if entry.exec contains candidate domain or URL)
  for (var i = 0; i < appRows.length; i++) {
    var entry = (appRows[i] && appRows[i].entry) ? appRows[i].entry : appRows[i]
    if (!entry) continue
    var execStr = String(entry.execString || entry.exec || "").toLowerCase()
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

function buildEntries(pinnedIds, toplevels, appRows, appLibrary, hyprFor, minimizedWs, minimizedOrigins, appGroups, terminalHosts, terminalApps) {
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
    var address = windowAddress(h)
    var cliApp = terminalApps && address ? terminalApps[address] : ""
    var appId = cliApp ? stripDesktop(cliApp) : stripDesktop(toplevel.appId)
    var hyprClass = (h && h.lastIpcObject) ? (h.lastIpcObject["class"] || h.lastIpcObject["initialClass"] || "") : ""
    if (!appId && hyprClass) appId = stripDesktop(hyprClass)
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
      item.name = entry && appLibrary ? appLibrary.entryName(entry) : item.appId
      var windows = item.windowList || []
      var host = terminalHosts && windows.length ? terminalHosts[windows[0].address] : ""
      // Application artwork wins; the actual terminal fills only a generic or missing icon.
      item.icon = resolveAppIcon(appLibrary, appRows, item.appId, host)
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
  var seenGrouped = {}
  for (var ga in groupedMap) {
    if (seenGrouped[ga]) continue
    var gwins = getWindowsFor(ga)
    if (gwins.length > 0) {
      seenGrouped[ga] = true
      var gc = getCandidates(ga)
      for (var c = 0; c < gc.length; c++) seenGrouped[gc[c]] = true
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

// The model holds only plain values (see buildEntries), so equal JSON means
// equal content. refreshDock skips assigning an equal model: every delegate
// binding re-evaluates on assignment, and most events (a workspace switch,
// a focus change) rebuild exactly the same model.
function sameModel(a, b) {
  if (!a || !b) return false
  return JSON.stringify(a) === JSON.stringify(b)
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

function focusWindow(toplevel) {
  try {
    if (toplevel && typeof toplevel.activate === "function") toplevel.activate()
  } catch (e) {
    console.warn("[omadock] focusWindow error:", e)
  }
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
      } catch (e) {
        console.warn("[omadock] closeApp error:", e)
      }
    }
  }
  return closed
}

function resolveAppIcon(appLibrary, appRows, appId, terminalHost) {
  var originalId = String(appId || "").trim()
  var id = cliAppId(originalId)
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

  // 4. Keep a theme-resolved app icon, but let a known terminal replace only
  // Quickshell's generic placeholder when the application itself is unknown.
  var genericIcon = ""
  try {
    var qp = Quickshell.iconPath(entry && entry.icon ? entry.icon : id, true)
    if (qp && qp !== "") {
      if (qp.indexOf("application-x-executable") < 0) return qp
      genericIcon = qp
    }
  } catch (e) {
    console.warn("[omadock] iconPath fallback failed for", id, e)
  }

  // 5. A known hosting terminal is preferable only to a generic/missing app icon.
  if (terminalHost && terminalHost !== id) {
    var terminalIcon = resolveAppIcon(appLibrary, appRows, terminalHost)
    if (terminalIcon && terminalIcon.indexOf("application-x-executable") < 0) return terminalIcon
  }

  // 6. Ultimate fallback
  if (genericIcon) return genericIcon
  if (appLibrary) {
    var fallback = appLibrary.iconSource("application-x-executable")
    if (fallback) return fallback
  }
  try {
    return Quickshell.iconPath("application-x-executable", true)
  } catch (e2) {
    console.warn("[omadock] Ultimate icon fallback failed:", e2)
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