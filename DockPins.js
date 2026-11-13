// The pin list itself: whether it holds an app, which pin a toggle is about,
// and how an item moves (a single move, or a drop reorder). Identity lives in
// DockModel.js (isAppMatch), so this module never decides what an app *is*: the
// toggle takes the matcher it must use, and everything else works on the list.
// The split is what let DockModel.js come back under its ratchet without losing
// a rule (see tests/static/structure-check.py).
//
// Why the two small normalisers below are repeated here: a root JS module
// cannot import another one. CI parses every root module with `node --check`,
// and QML's `.import` is a QML directive that `node --check` rejects (measured),
// so there is no expressible `import` between DockModel.js and this file. The
// alternative — teaching the pin list its own identity rule, or its own copy of
// the model's whole id surface — would be worse than two restated helpers,
// and `tests/unit/pins.test.mjs` pins both implementations to the same answers
// so they cannot drift apart silently.

// DockModel.stripDesktop, restated: accept a row (it carries appId) or a string.
function idOf(value) {
  if (typeof value === "object" && value !== null && value.appId) value = value.appId
  return String(value == null ? "" : value).trim().replace(/\.desktop$/i, "")
}

// DockModel.toArray, restated: a JS array, a Qt list, or nothing.
function listOf(list) {
  if (Array.isArray(list)) return list
  if (!list || typeof list === "string" || typeof list === "function") return []
  if (typeof list.length === "number") {
    var out = []
    for (var i = 0; i < list.length; i++) out.push(list[i])
    return out
  }
  return []
}

function isPinned(pinnedIds, appId) {
  var arr = listOf(pinnedIds)
  var id = idOf(appId)
  if (!id) return false
  for (var i = 0; i < arr.length; i++) {
    if (idOf(arr[i]) === id) return true
  }
  return false
}

// Remove the pin for an app, or add it: sameApp is DockModel.isAppMatch, the
// identity rule, handed in because the list owns no identity of its own.
function togglePinned(pinnedIds, appId, sameApp) {
  var arr = listOf(pinnedIds).slice()
  var id = idOf(appId)
  if (!id) return arr
  // A pin keeps the id it was made with while the menu passes the entry's
  // current id; buildEntries calls those one app (isAppMatch), so the toggle
  // must too — exact matching appended a second pin instead of unpinning.
  var next = [], removed = false
  for (var i = 0; i < arr.length; i++) {
    var p = idOf(arr[i])
    if (p && (p === id || sameApp(p, id))) removed = true
    else next.push(arr[i])
  }
  if (!removed) next.push(id)
  return next
}

// Reorder pinned apps: move appId from its current position to insertBeforeId.
// If insertBeforeId is null/empty, move to the end. Dropping onto the dragged
// item itself is a no-op (prevents the "teleport to end" self-drop bug).
function reorderPinned(pinnedIds, appId, insertBeforeId) {
  var arr = listOf(pinnedIds).slice()
  var id = idOf(appId)
  if (!id) return arr
  if (insertBeforeId && idOf(insertBeforeId) === id) return arr

  var fromIdx = arr.indexOf(id)
  if (fromIdx >= 0) {
    arr.splice(fromIdx, 1)
  }

  if (!insertBeforeId) {
    arr.push(id)
  } else {
    var toIdx = arr.indexOf(idOf(insertBeforeId))
    if (toIdx < 0) arr.push(id)
    else arr.splice(toIdx, 0, id)
  }
  return arr
}

// A copy of list with the item at from moved before the item now at
// insertIndex (to the end when insertIndex is past the last item). Returns
// list itself when nothing moves.
function moveBefore(list, from, insertIndex) {
  var arr = listOf(list)
  if (from < 0 || from >= arr.length) return list
  var to = Math.max(0, Math.min(arr.length, insertIndex))
  if (to === from || to === from + 1) return list
  var next = arr.slice()
  var moved = next.splice(from, 1)[0]
  next.splice(to > from ? to - 1 : to, 0, moved)
  return next
}
