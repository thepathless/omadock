// The desktop's icon theme: which themes are installed, which directories the
// icon index reads first, and whether a theme id is safe to apply.
//
// The theme itself belongs to the system (gsettings' icon-theme plus the GTK
// and KDE files scripts/icon-theme.sh writes), never to omadock.json: every
// application shares it, so the dock reads it, offers to change it, and then
// resolves its own icons through it. Nothing here holds state.

// scripts/icon-theme.sh list prints "id|Name|Inherits"; ids repeat when the
// same theme is installed under two prefixes, and the first wins (user themes
// are listed before the system ones).
function parseList(text) {
  var out = []
  var seen = Object.create(null)
  var lines = String(text == null ? "" : text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("|")
    var id = String(parts[0] || "").trim()
    if (!id || !safeId(id) || seen[id]) continue
    seen[id] = true
    out.push({
      id: id,
      name: String(parts[1] || id).trim() || id,
      inherits: String(parts[2] || "").split(",").map(function (s) { return s.trim() }).filter(Boolean)
    })
  }
  out.sort(function (a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0 })
  return out
}

// Same rule as the apply script: a theme id is a directory name. Keeping the
// two in step is what stops an id from reaching a path or a gsettings value
// with anything but a name in it.
function safeId(id) {
  return /^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(String(id == null ? "" : id))
}

// The theme and the themes it inherits from, in lookup order. Freedesktop
// inheritance is what makes Yaru-blue find the generic Yaru artwork, so the
// index walks it before it falls back to unrelated themes.
function chain(id, themes) {
  var byId = Object.create(null)
  var list = Array.isArray(themes) ? themes : []
  for (var i = 0; i < list.length; i++) byId[list[i].id] = list[i]
  var out = []
  var queue = [String(id == null ? "" : id)]
  while (queue.length && out.length < 8) {
    var current = queue.shift()
    if (!current || out.indexOf(current) >= 0) continue
    out.push(current)
    var theme = byId[current]
    if (theme) for (var k = 0; k < theme.inherits.length; k++) queue.push(theme.inherits[k])
  }
  return out
}

// What a row says under the theme's name: the id when it is not already the
// name, and which theme it builds on.
function subtitle(theme) {
  if (!theme) return ""
  var parts = []
  if (theme.id !== theme.name) parts.push(theme.id)
  if (theme.inherits.length) parts.push("builds on " + theme.inherits.join(", "))
  return parts.join(" · ")
}
