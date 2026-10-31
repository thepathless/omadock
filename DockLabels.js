// Pure helpers for the dock's name labels (components/DockLabel.qml and
// components/logic/DockLabelLogic.qml). Plain JS with no Qt globals, so the
// node tests run it in a vm context like DockModel.js.

var LABEL_MODES = ["off", "always", "hover"]
var LABEL_KINDS = ["all", "apps", "groups", "folders"]
var LABEL_FONTS = ["theme", "sans", "pixel"]
var LABEL_SIZES = ["small", "medium", "large"]
var LABEL_WEIGHTS = ["regular", "medium", "bold"]
var LABEL_COLORS = ["auto", "theme", "accent"]
var LABEL_BACKGROUNDS = ["none", "pill", "plate"]
var LABEL_SHAPES = ["dock", "pill", "rounded", "square"]
// The hover name's presentation: the dock's own chip, or the macOS Dock's
// callout (a dark translucent label that tracks the magnified icon). A look
// key, so only a preset that asks for it changes.
var LABEL_CHIPS = ["dock", "macos"]
// "nested" was its own choice; square took its look (square between plates,
// the ends round with the panel), so a stored nested reads as square.
function _shape(v) { return v === "nested" ? "square" : v }
var LABEL_INDICATORS = ["before", "after", "under"]
var LABEL_PLATE_HEIGHTS = ["icon", "dock"]
var LABEL_PINNED = ["always", "running"]
var LABEL_REVEALS = ["slide", "typewriter", "scramble"]
var LABEL_EFFECTS = ["none", "glow", "outline"]
var LABEL_MAX_WIDTH_MIN = 80
var LABEL_MAX_WIDTH_MAX = 240
var LABEL_MAX_WIDTH_DEFAULT = 140
var MAX_LABEL_NAMES = 200
var MAX_LABEL_NAME = 40
var MAX_LABEL_APP_ID = 128
var LABEL_CONFIG_KEYS = ["labelMode", "labelKind", "labelFont", "labelSize", "labelWeight",
  "labelColor", "labelBackground", "labelShape", "labelChip", "labelIndicators", "labelPlateHeight", "labelPinned", "labelReveal", "labelEffect", "labelMaxWidth", "labelNames"]
// The first label release spelled these; read once, dropped on save.
var LEGACY_LABEL_KEYS = ["showLabels", "labelPlacement", "labelContrast"]
var SYMBOL_WORD = /^[&+\-–—|\/·:,.]+$/
var SCRAMBLE_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#%&*+=?"

function _pick(value, allowed, fallback) {
  return allowed.indexOf(value) >= 0 ? value : fallback
}

function _chars(s) { return Array.from(String(s == null ? "" : s)) }

// A name for an app without a desktop entry: the last part of its class id,
// words split on - and _, capitalised. "org.omarchy.terminal" -> "Terminal".
function prettyAppId(appId) {
  var s = String(appId == null ? "" : appId).trim()
  if (s === "") return ""
  if (/\.desktop$/i.test(s)) s = s.slice(0, -8)
  var parts = s.split(".")
  var last = parts[parts.length - 1] || s
  var words = last.split(/[-_\s]+/).filter(function(w) { return w !== "" })
  if (words.length === 0) return s
  return words.map(function(w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join(" ")
}

// Drops what a short label can live without: bracketed parts and anything
// after a " - ", " — " or ": " subtitle separator.
function cleanName(name) {
  var orig = String(name == null ? "" : name).replace(/\s+/g, " ").trim()
  var s = orig
  var cut = s.search(/\s[-–—]\s|:\s/)
  if (cut > 0) s = s.slice(0, cut)
  s = s.replace(/\s*\([^)]*\)/g, "").replace(/\s+/g, " ").trim()
  return s !== "" ? s : orig
}

// The label text for a max width. fits(text) measures in the label's real
// font. Each step runs only when the previous one did not fit: the full
// name, the cleaned name, whole leading words, then an ellipsis inside the
// first word.
function shortenName(name, fits) {
  var full = String(name == null ? "" : name).replace(/\s+/g, " ").trim()
  if (full === "" || fits(full)) return { text: full, shortened: false }
  var clean = cleanName(full)
  if (fits(clean)) return { text: clean, shortened: true }
  var words = clean.split(" ")
  for (var n = words.length - 1; n >= 1; n--) {
    // A cut never ends on a connector like "&" or "-".
    if (SYMBOL_WORD.test(words[n - 1])) continue
    var head = words.slice(0, n).join(" ")
    if (fits(head)) return { text: head, shortened: true }
  }
  var chars = _chars(words[0])
  for (var k = chars.length - 1; k >= 1; k--) {
    var t = chars.slice(0, k).join("") + "…"
    if (fits(t)) return { text: t, shortened: true }
  }
  return { text: "…", shortened: true }
}

function labelVisible(mode, filter, kind) {
  if (mode !== "always" && mode !== "hover") return false
  return filter === "all" || filter === kind + "s"
}

// With a label shown, the tooltip appears only when it says more than the
// name: window previews, a state hint, or the full name of a shortened label.
function tooltipNeeded(labelShown, hasWindows, hasStateHint, shortened) {
  if (!labelShown) return true
  return !!(hasWindows || hasStateHint || shortened)
}

// The dock's per-slot label widths: { slot: { owner, width, before } },
// where before is the part of width that sits ahead of the slot's own icon
// (a mirrored label, a side-indicator column). A clear (width 0) only
// removes the entry its own owner wrote, so a tile leaving a slot cannot
// erase the tile that just moved in. Unchanged input returns the same
// object, so bindings on it do not re-run.
function withExtra(extras, slot, owner, width, before) {
  var cur = extras ? extras[slot] : undefined
  var w = Math.max(0, Math.round(Number(width) || 0))
  var b = Math.max(0, Math.min(w, Math.round(Number(before) || 0)))
  if (w > 0 && cur && cur.owner === owner && cur.width === w && cur.before === b) return extras
  if (w === 0 && (!cur || cur.owner !== owner)) return extras
  var next = {}
  for (var k in extras) next[k] = extras[k]
  if (w > 0) next[slot] = { owner: owner, width: w, before: b }
  else delete next[slot]
  return next
}

// Each label's full, unshortened width for the dock's fit planner
// (DockFit.js): text is the name's advance, inner what the max-width budget
// spends besides it, outer what the open label adds besides it, folded the
// room a folded label keeps. Same ownership rule as withExtra; unchanged
// input returns the same object.
function withNatural(map, slot, owner, entry) {
  var cur = map ? map[slot] : undefined
  if (!entry) {
    if (!cur || cur.owner !== owner) return map
    var cleared = {}
    for (var c in map) if (Number(c) !== Number(slot)) cleared[c] = map[c]
    return cleared
  }
  var e = { owner: owner, text: Math.ceil(entry.text || 0), inner: Math.ceil(entry.inner || 0),
    outer: Math.ceil(entry.outer || 0), folded: Math.ceil(entry.folded || 0) }
  if (cur && cur.owner === owner && cur.text === e.text && cur.inner === e.inner && cur.outer === e.outer && cur.folded === e.folded) return map
  var next = {}
  for (var k in map) next[k] = map[k]
  next[slot] = e
  return next
}

function extrasBefore(extras, slot) {
  var sum = 0
  for (var k in extras) if (Number(k) < slot) sum += extras[k].width || 0
  return sum
}

function extrasTotal(extras) { return extrasBefore(extras, Infinity) }

// The card's x for its alignment. hoverExtra is width a centred dock leaves
// out of its centring (0 when nothing should grow one way only).
function anchoredX(parentWidth, width, inset, alignment, hoverExtra) {
  if (alignment === "left") return inset
  if (alignment === "right") return parentWidth - width - inset
  return Math.round((parentWidth - (width - (hoverExtra || 0))) / 2)
}

// Label width that sits before a slot's icon: every earlier slot's, plus
// the part of the slot's own that is ahead of its icon (includeOwn false
// for a slot index shared with an unlabelled item).
function homeExtra(extras, slot, includeOwn) {
  var own = (includeOwn !== false && extras && extras[slot]) ? (extras[slot].before || 0) : 0
  return extrasBefore(extras, slot) + own
}

function _noise(n) {
  var x = Math.sin(n * 12.9898) * 43758.5453
  return x - Math.floor(x)
}

// The text drawn at reveal progress t (0..1). Typewriter shows a growing
// prefix; scramble keeps the length and settles characters left to right,
// the rest drawn from SCRAMBLE_CHARS (deterministic for a seed and t).
function revealFrame(text, style, t, seed) {
  var chars = _chars(text)
  if (style !== "typewriter" && style !== "scramble") return chars.join("")
  var p = Math.max(0, Math.min(1, Number(t) || 0))
  var shown = Math.round(p * chars.length)
  if (style === "typewriter") return chars.slice(0, shown).join("")
  var step = Math.floor(p * 12)
  var out = ""
  for (var i = 0; i < chars.length; i++) {
    if (i < shown || chars[i] === " ") out += chars[i]
    else out += SCRAMBLE_CHARS.charAt(Math.floor(_noise(seed * 31 + i * 7 + step) * SCRAMBLE_CHARS.length))
  }
  return out
}

function _boundName(v) {
  return _chars(String(v).replace(/\s+/g, " ").trim()).slice(0, MAX_LABEL_NAME).join("")
}

// User label names from config: string to string, bounded like every other
// config list.
function boundLabelNames(value) {
  var out = {}
  if (!value || typeof value !== "object" || Array.isArray(value)) return out
  var n = 0
  for (var k in value) {
    if (n >= MAX_LABEL_NAMES) break
    if (!Object.prototype.hasOwnProperty.call(value, k)) continue
    if (k === "" || k === "__proto__" || k.length > MAX_LABEL_APP_ID) continue
    if (typeof value[k] !== "string") continue
    var name = _boundName(value[k])
    if (name === "") continue
    out[k] = name
    n++
  }
  return out
}

// A copy of names with appId set to name; a blank name removes the entry.
function withLabelName(names, appId, name) {
  var next = {}
  for (var k in names) next[k] = names[k]
  if (!appId) return next
  var v = _boundName(name == null ? "" : name)
  if (v === "") delete next[appId]
  else next[appId] = v
  return boundLabelNames(next)
}

function readLabelConfig(parsed) {
  var p = (parsed && typeof parsed === "object") ? parsed : {}
  // A config without labelMode comes from the first label release (or has
  // no labels): its band-sized labelSize does not carry over.
  var legacy = _pick(p.labelMode, LABEL_MODES, "") === ""
  var mode = legacy ? (p.showLabels === true ? "always" : "off") : p.labelMode
  // "high" was this release's own early spelling of auto.
  var color = p.labelColor === "high" ? "auto" : _pick(p.labelColor, LABEL_COLORS, "")
  if (color === "") color = p.labelContrast === "theme" ? "theme" : "auto"
  var background = _pick(p.labelBackground, LABEL_BACKGROUNDS, "")
  if (background === "") background = p.labelContrast === "pill" ? "pill" : "none"
  var w = (typeof p.labelMaxWidth === "number" && isFinite(p.labelMaxWidth))
    ? Math.max(LABEL_MAX_WIDTH_MIN, Math.min(LABEL_MAX_WIDTH_MAX, Math.round(p.labelMaxWidth)))
    : LABEL_MAX_WIDTH_DEFAULT
  return {
    labelMode: mode,
    labelKind: _pick(p.labelKind, LABEL_KINDS, "all"),
    labelFont: _pick(p.labelFont, LABEL_FONTS, "theme"),
    labelSize: legacy ? "medium" : _pick(p.labelSize, LABEL_SIZES, "medium"),
    labelWeight: _pick(p.labelWeight, LABEL_WEIGHTS, "medium"),
    labelColor: color,
    labelBackground: background,
    labelShape: _pick(_shape(p.labelShape), LABEL_SHAPES, "dock"),
    labelChip: _pick(p.labelChip, LABEL_CHIPS, "dock"),
    labelIndicators: _pick(p.labelIndicators, LABEL_INDICATORS, "before"),
    labelPlateHeight: _pick(p.labelPlateHeight, LABEL_PLATE_HEIGHTS, "icon"),
    labelPinned: _pick(p.labelPinned, LABEL_PINNED, "always"),
    labelReveal: _pick(p.labelReveal, LABEL_REVEALS, "slide"),
    labelEffect: p.labelEffect === "shadow" ? "outline" : _pick(p.labelEffect, LABEL_EFFECTS, "none"),
    labelMaxWidth: w,
    labelNames: boundLabelNames(p.labelNames)
  }
}

// "When running" pinned apps (labelPinned): an always-on name folds away
// while its pinned app has no window, leaving the icon (on its plate). awake
// is the tile's say that the app runs and its launch bounce has landed.
function nameFolded(mode, pinnedMode, pinned, awake) {
  return mode === "always" && pinnedMode === "running" && !!pinned && !awake
}

// Window indicators move from under the icon to a column at the plate's
// edge only for always-on plates: a hover label would make them jump as it
// opens and closes.
function sideMarks(mode, background, indicators) {
  return mode === "always" && background === "plate" && (indicators === "before" || indicators === "after")
}

// Corner radius of a label background of height h. "dock" keeps the
// dock's own corner-to-height ratio, so a square dock gets square labels
// and a pill dock pill ones.
function labelRadius(shape, h, dockRatio) {
  if (shape === "pill") return h / 2
  if (shape === "rounded") return h / 4
  if (shape === "square") return 0
  return Math.min(h / 2, h * Math.max(0, Number(dockRatio) || 0))
}

// Which plates stand at their panel's edge, by label slot. sections is the
// row in order (DockCard), each { n, labelled, cut }: n visible items,
// labelled when those items have label slots, cut when split sections start
// a new panel before them. A cut before an empty section carries to the
// next one with items. Counted, not measured, so the magnification wave
// cannot move an edge.
function plateEdges(sections) {
  var items = []
  var panel = 0
  var pending = false
  for (var i = 0; i < (sections || []).length; i++) {
    var s = sections[i]
    if (s.cut) pending = true
    for (var k = 0; k < (s.n || 0); k++) {
      if (pending && items.length > 0) panel++
      pending = false
      items.push({ panel: panel, labelled: !!s.labelled })
    }
  }
  var out = []
  for (var j = 0; j < items.length; j++) {
    if (!items[j].labelled) continue
    out.push({
      left: j === 0 || items[j - 1].panel !== items[j].panel,
      right: j === items.length - 1 || items[j + 1].panel !== items[j].panel
    })
  }
  return out
}

// A plate's corner radii { tl, tr, bl, br }. Without edges (pills, hover
// labels) every shape rounds all four by radius. In a plate row "square"
// squares the plate off inside its panel and, on a side at the panel's edge,
// uses outer (the panel's radius less the gap), so the two curves run
// parallel, up to a pill end. Any other shape keeps its radius unless an
// edge corner would be smaller than fit (plateFitRadius), the smallest one
// that stays inside the panel's curve: then that side takes outer too.
function plateCorners(shape, h, radius, outer, edges, fit) {
  var nested = Math.max(0, Math.min(h / 2, Number(outer) || 0))
  if (!edges) return { tl: radius, tr: radius, bl: radius, br: radius }
  if (_shape(shape) === "square") {
    var l = edges.left ? nested : 0
    var rr = edges.right ? nested : 0
    return { tl: l, tr: rr, bl: l, br: rr }
  }
  var edge = radius < (Number(fit) || 0) ? Math.max(radius, nested) : radius
  var el = edges.left ? edge : radius
  var er = edges.right ? edge : radius
  return { tl: el, tr: er, bl: el, br: er }
}

// How far in from a pill end its curve (radius r) reaches at half-height
// half off the centre line: the room a pill plate keeps before its icon and
// after its name, so the curve never cuts into either.
function pillRoom(r, half) {
  var R = Math.max(0, Number(r) || 0)
  var y = Math.max(0, Number(half) || 0)
  if (y >= R) return R
  return R - Math.sqrt(R * R - y * y)
}

// The smallest corner radius a plate g in from a curve of radius R can have
// without poking out of it: the corner's arc, centred r + g in, must stay
// within R of the curve's centre along the diagonal, which gives
// r >= R - g * sqrt2 / (sqrt2 - 1).
function plateFitRadius(R, g) {
  var need = (Number(R) || 0) - (Number(g) || 0) * Math.SQRT2 / (Math.SQRT2 - 1)
  return Math.max(0, need)
}

var LABEL_LOOK_KEYS = ["labelMode", "labelKind", "labelFont", "labelSize", "labelWeight", "labelColor",
  "labelBackground", "labelShape", "labelChip", "labelIndicators", "labelPlateHeight", "labelPinned", "labelReveal", "labelEffect", "labelMaxWidth"]

// A preset's label look over the current one: known keys with valid
// values win, anything else keeps its current value. (readLabelConfig
// would treat a look without labelMode as a legacy config.)
function pickLabelLook(look, current) {
  var l = (look && typeof look === "object") ? look : {}
  var c = current || {}
  var out = {}
  var lists = { labelMode: LABEL_MODES, labelKind: LABEL_KINDS, labelFont: LABEL_FONTS, labelSize: LABEL_SIZES, labelWeight: LABEL_WEIGHTS,
    labelColor: LABEL_COLORS, labelBackground: LABEL_BACKGROUNDS, labelShape: LABEL_SHAPES, labelChip: LABEL_CHIPS, labelIndicators: LABEL_INDICATORS, labelPlateHeight: LABEL_PLATE_HEIGHTS, labelPinned: LABEL_PINNED,
    labelReveal: LABEL_REVEALS, labelEffect: LABEL_EFFECTS }
  for (var i = 0; i < LABEL_LOOK_KEYS.length; i++) {
    var k = LABEL_LOOK_KEYS[i]
    var v = l[k]
    if (k === "labelEffect" && v === "shadow") v = "outline"
    if (k === "labelColor" && v === "high") v = "auto"
    if (k === "labelShape") v = _shape(v)
    if (k === "labelMaxWidth") {
      out[k] = (typeof v === "number" && isFinite(v))
        ? Math.max(LABEL_MAX_WIDTH_MIN, Math.min(LABEL_MAX_WIDTH_MAX, Math.round(v))) : c[k]
    } else {
      out[k] = lists[k].indexOf(v) >= 0 ? v : c[k]
    }
  }
  return out
}

// Identity of the Labels page's name rows: only the apps and their default
// names, so window-title churn in the dock model does not rebuild them.
function nameRowsKey(rows) {
  return JSON.stringify((rows || []).map(function(r) { return [r.appId, r.auto] }))
}

// A pinned folder's own name; blank goes back to the directory's name.
// Bounded like DockModel.boundPinnedFolders (120 characters).
var MAX_FOLDER_LABEL = 120
function folderBaseName(path) {
  var p = String(path == null ? "" : path).replace(/\/+$/, "")
  if (p === "" || p === "~") return "Home"
  var parts = p.split("/")
  return parts[parts.length - 1] || "Folder"
}

function withFolderName(folders, path, name) {
  var list = folders || []
  var at = -1
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].path === path) { at = i; break }
  if (at < 0) return list
  var v = _chars(String(name == null ? "" : name).replace(/\s+/g, " ").trim()).slice(0, MAX_FOLDER_LABEL).join("")
  var next = list.slice()
  var entry = {}
  for (var k in list[at]) entry[k] = list[at][k]
  entry.name = v !== "" ? v : folderBaseName(path)
  next[at] = entry
  return next
}

// The dock's gradient fill (shaders/gradient.frag) at card point (x, y),
// without the dock's opacity: base and colours as {r, g, b} in 0..1, w x h
// the card size. Lets an auto label pick black or white for what is behind
// it there rather than for the gradient's average.
function _ramp(t, s0, s1) { return Math.max(0, Math.min(1, (s1 - t) / (s1 - s0))) }
function _linearT(x, y, w, h, deg) {
  var a = deg * Math.PI / 180
  var dx = Math.sin(a), dy = -Math.cos(a)
  var len = Math.abs(w * Math.sin(a)) + Math.abs(h * Math.cos(a))
  return ((x - w / 2) * dx + (y - h / 2) * dy) / len + 0.5
}
function _radialT(x, y, w, h, cx, cy) {
  var px = cx * w, py = cy * h
  var r = Math.max(Math.max(Math.hypot(px, py), Math.hypot(px - w, py)), Math.max(Math.hypot(px, py - h), Math.hypot(px - w, py - h)))
  return Math.hypot(x - px, y - py) / r
}
function _over(under, layer, cover, strength) {
  var k = Math.max(0, Math.min(1, cover * strength))
  return { r: under.r + (layer.r - under.r) * k, g: under.g + (layer.g - under.g) * k, b: under.b + (layer.b - under.b) * k }
}
function gradientAt(base, cols, strength, w, h, x, y) {
  var col = { r: base.r, g: base.g, b: base.b }
  var c = cols || []
  if (c.length === 0 || !(w > 0) || !(h > 0)) return col
  var c1 = c[0], c2 = c.length > 1 ? c[1] : c1, c3 = c.length > 2 ? c[2] : c2
  if (c.length < 3) {
    col = _over(col, c2, _ramp(_linearT(x, y, w, h, -30), 0.3, 1.2), strength)
    col = _over(col, c1, _ramp(_linearT(x, y, w, h, 150), 0.3, 1.2), strength)
  } else {
    col = _over(col, c1, _ramp(_radialT(x, y, w, h, 0, 0), 0.1, 0.7), strength)
    col = _over(col, c2, _ramp(_radialT(x, y, w, h, 0.95, 0), 0, 0.75), strength)
    col = _over(col, c3, _ramp(_linearT(x, y, w, h, -5), 0.1, 0.8), strength)
  }
  return col
}

// WCAG relative luminance and contrast of {r, g, b} colours in 0..1.
function _lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
function _lum(c) { return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b) }
function contrast(a, b) {
  var la = _lum(a), lb = _lum(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// One ink for every label: of dark and light, the one whose weakest
// contrast over the sampled backdrops is highest. Picking per label made
// neighbours flip between light and dark plates on mid-tone gradients.
function steadyInk(backdrops, dark, light) {
  var list = backdrops || []
  if (list.length === 0) return dark
  var worstDark = Infinity, worstLight = Infinity
  for (var i = 0; i < list.length; i++) {
    worstDark = Math.min(worstDark, contrast(dark, list[i]))
    worstLight = Math.min(worstLight, contrast(light, list[i]))
  }
  return worstDark >= worstLight ? dark : light
}

// Device-pixel grid helpers for a plate row at output scale dpr: values
// that are whole device pixels keep both sides of every gap identical.
function gridRound(v, dpr) { var d = dpr > 0 ? dpr : 1; return Math.round(v * d) / d }
function gridCeil(v, dpr) { var d = dpr > 0 ? dpr : 1; return Math.ceil(v * d - 1e-9) / d }
// The smallest whole logical size from n up that is also whole device
// pixels (an even number at 1.5), for sizes held in int properties.
function gridInt(n, dpr) {
  var d = dpr > 0 ? dpr : 1
  for (var k = 0; k < 8; k++) {
    var m = Math.round(n) + k
    if (Math.abs(m * d - Math.round(m * d)) < 1e-9) return m
  }
  return Math.round(n)
}

// Spacing for a row of label plates: one gap between plates, between a
// plate and the dock's edge, and between a plate and a divider line.
// spacing is the user's item spacing, clamped to minGap..maxGap (plates
// touch at 0 and drift apart at large values) and snapped to the
// output's pixel grid. Plates fill their tiles (inset 0), the card's side
// padding is the gap (edge) and a divider slot is just its line.
function plateSpacing(spacing, line, dpr, minGap, maxGap) {
  var d = dpr > 0 ? dpr : 1
  var gap = gridRound(Math.max(minGap, Math.min(maxGap, spacing)), d)
  return { spacing: gap, line: line, inset: 0, gap: gap, edge: gap, separator: line }
}

function writeLabelConfig(conf, state) {
  for (var i = 0; i < LABEL_CONFIG_KEYS.length; i++) conf[LABEL_CONFIG_KEYS[i]] = state[LABEL_CONFIG_KEYS[i]]
  for (var j = 0; j < LEGACY_LABEL_KEYS.length; j++) delete conf[LEGACY_LABEL_KEYS[j]]
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

// Folder stack header count: "" for none, "N+" when the scan stopped at its
// budget (list-folder.py MAX_SCAN) and the folder holds more.
function stackCountLabel(count, truncated) {
  var n = Math.max(0, Math.floor(Number(count) || 0))
  if (n === 0) return ""
  return truncated ? n + "+" : String(n)
}

// Folder stack footer for entries not shown: "" when all are shown.
function stackMoreLabel(count, shown, truncated) {
  var rest = Math.max(0, Math.floor(Number(count) || 0) - Math.floor(Number(shown) || 0))
  if (rest === 0) return ""
  return "+ " + rest + (truncated ? "+" : "") + " more"
}
