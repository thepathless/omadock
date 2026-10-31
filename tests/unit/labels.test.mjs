// Tests for DockLabels.js, the pure helpers behind the dock's name labels.
// Plain JS with no Qt globals, run in a vm context like DockModel.js.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKLABELS || new URL("../../DockLabels.js", import.meta.url)
const L = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), L)
const plain = (v) => JSON.parse(JSON.stringify(v))
// 7 px per character, like a monospace caption.
const fitsChars = (n) => (s) => Array.from(s).length * 7 <= n * 7

test("prettyAppId turns class ids into names", () => {
  assert.equal(L.prettyAppId("org.omarchy.terminal"), "Terminal")
  assert.equal(L.prettyAppId("zen-browser"), "Zen Browser")
  assert.equal(L.prettyAppId("com.github.foo_bar"), "Foo Bar")
  assert.equal(L.prettyAppId("signal.desktop"), "Signal")
  assert.equal(L.prettyAppId(""), "")
  assert.equal(L.prettyAppId(null), "")
})

test("cleanName drops brackets and subtitles", () => {
  assert.equal(L.cleanName("Signal - Private Messenger"), "Signal")
  assert.equal(L.cleanName("Firefox (Beta)"), "Firefox")
  assert.equal(L.cleanName("GIMP: Image Editor"), "GIMP")
  assert.equal(L.cleanName("Visual Studio Code — Insiders"), "Visual Studio Code")
  assert.equal(L.cleanName("(only brackets)"), "(only brackets)")
})

test("shortenName keeps names that fit", () => {
  assert.deepEqual(plain(L.shortenName("Signal", fitsChars(10))), { text: "Signal", shortened: false })
})

test("shortenName cleans before cutting", () => {
  assert.deepEqual(plain(L.shortenName("Signal - Private Messenger", fitsChars(10))), { text: "Signal", shortened: true })
})

test("shortenName cuts at word boundaries without an ellipsis", () => {
  assert.deepEqual(plain(L.shortenName("Visual Studio Code", fitsChars(14))), { text: "Visual Studio", shortened: true })
  assert.deepEqual(plain(L.shortenName("Zen Browser", fitsChars(5))), { text: "Zen", shortened: true })
})

test("shortenName ellipsises only a first word that does not fit", () => {
  assert.deepEqual(plain(L.shortenName("Spotifasolatron", fitsChars(8))), { text: "Spotifa…", shortened: true })
})

test("shortenName handles empty, blank, tiny widths and wide characters", () => {
  assert.deepEqual(plain(L.shortenName("", fitsChars(8))), { text: "", shortened: false })
  assert.deepEqual(plain(L.shortenName("   ", fitsChars(8))), { text: "", shortened: false })
  assert.deepEqual(plain(L.shortenName("Mattermost", () => false)), { text: "…", shortened: true })
  assert.equal(L.shortenName("日本語のアプリ名前", fitsChars(4)).text, "日本語…")
  assert.equal(L.shortenName("🎵🎵🎵🎵🎵🎵", fitsChars(3)).text, "🎵🎵…")
})

test("labelVisible follows mode and filter", () => {
  assert.equal(L.labelVisible("off", "all", "app"), false)
  assert.equal(L.labelVisible("always", "all", "folder"), true)
  assert.equal(L.labelVisible("hover", "apps", "app"), true)
  assert.equal(L.labelVisible("hover", "apps", "group"), false)
  assert.equal(L.labelVisible("always", "folders", "folder"), true)
  assert.equal(L.labelVisible("bogus", "all", "app"), false)
})

test("tooltipNeeded only when the tooltip says more than the label", () => {
  assert.equal(L.tooltipNeeded(false, false, false, false), true)
  assert.equal(L.tooltipNeeded(true, false, false, false), false)
  assert.equal(L.tooltipNeeded(true, true, false, false), true)
  assert.equal(L.tooltipNeeded(true, false, true, false), true)
  assert.equal(L.tooltipNeeded(true, false, false, true), true)
})

test("withExtra records, updates and clears by owner", () => {
  let e = {}
  e = L.withExtra(e, 2, "a", 40)
  e = L.withExtra(e, 0, "b", 10)
  assert.equal(L.extrasBefore(e, 2), 10)
  assert.equal(L.extrasBefore(e, 3), 50)
  assert.equal(L.extrasTotal(e), 50)
  const same = L.withExtra(e, 2, "a", 40)
  assert.equal(same, e)
  // Another owner moved into slot 2 first: a's late clear must not erase it.
  e = L.withExtra(e, 2, "c", 30)
  e = L.withExtra(e, 2, "a", 0)
  assert.equal(L.extrasTotal(e), 40)
  e = L.withExtra(e, 2, "c", 0)
  assert.equal(L.extrasTotal(e), 10)
  assert.equal(L.withExtra({}, 5, "x", 0) !== undefined, true)
})

test("anchoredX keeps a centred dock's leading edge while labels open", () => {
  // 1000 wide screen, dock 200 wide at rest -> x 400.
  assert.equal(L.anchoredX(1000, 200, 20, "center", 0), 400)
  // A hover label adds 80: same x, the dock grows to the right.
  assert.equal(L.anchoredX(1000, 280, 20, "center", 80), 400)
  // Always-mode width is not hover extra: it centres.
  assert.equal(L.anchoredX(1000, 280, 20, "center", 0), 360)
  assert.equal(L.anchoredX(1000, 280, 20, "left", 80), 20)
  // Right: the right edge stays (labels open to the left there).
  assert.equal(L.anchoredX(1000, 280, 20, "right", 80), 700)
})

test("revealFrame types and scrambles without changing length", () => {
  assert.equal(L.revealFrame("Signal", "slide", 0.2, 1), "Signal")
  assert.equal(L.revealFrame("Signal", "typewriter", 0, 1), "")
  assert.equal(L.revealFrame("Signal", "typewriter", 0.5, 1), "Sig")
  assert.equal(L.revealFrame("Signal", "typewriter", 1, 1), "Signal")
  const s = L.revealFrame("Zen Browser", "scramble", 0.3, 7)
  assert.equal(Array.from(s).length, 11)
  assert.equal(s.slice(0, 3), "Zen")
  assert.equal(s.charAt(3), " ")
  assert.equal(L.revealFrame("Zen Browser", "scramble", 1, 7), "Zen Browser")
  assert.equal(L.revealFrame("Zen", "scramble", 0.3, 7), L.revealFrame("Zen", "scramble", 0.3, 7))
})

test("boundLabelNames keeps sane string entries only", () => {
  const raw = JSON.parse('{"a":"  Matter  most ","b":"","c":5,"__proto__":"x","' + "z".repeat(200) + '":"long id"}')
  raw.d = "x".repeat(60)
  const out = plain(L.boundLabelNames(raw))
  assert.deepEqual(Object.keys(out).sort(), ["a", "d"])
  assert.equal(out.a, "Matter most")
  assert.equal(out.d.length, 40)
  assert.deepEqual(plain(L.boundLabelNames(["x"])), {})
  assert.deepEqual(plain(L.boundLabelNames(null)), {})
  const many = {}
  for (let i = 0; i < 300; i++) many["app" + i] = "n" + i
  assert.equal(Object.keys(L.boundLabelNames(many)).length, 200)
})

test("withLabelName sets, trims and clears", () => {
  let n = L.withLabelName({}, "zen", "  Zen ")
  assert.deepEqual(plain(n), { zen: "Zen" })
  n = L.withLabelName(n, "zen", "   ")
  assert.deepEqual(plain(n), {})
  assert.deepEqual(plain(L.withLabelName({}, "", "x")), {})
})

test("readLabelConfig defaults", () => {
  assert.deepEqual(plain(L.readLabelConfig(null)), {
    labelMode: "off", labelKind: "all", labelFont: "theme", labelSize: "medium",
    labelWeight: "medium", labelColor: "auto", labelBackground: "none", labelShape: "dock",
    labelChip: "dock",
    labelIndicators: "before", labelPlateHeight: "icon", labelPinned: "always", labelReveal: "slide", labelEffect: "none", labelMaxWidth: 140, labelNames: {}
  })
})

test("readLabelConfig keeps a known labelPinned and defaults the rest", () => {
  assert.equal(L.readLabelConfig({ labelPinned: "running" }).labelPinned, "running")
  assert.equal(L.readLabelConfig({ labelPinned: "never" }).labelPinned, "always")
  assert.equal(L.pickLabelLook({ labelPinned: "running" }, { labelPinned: "always" }).labelPinned, "running")
  assert.equal(L.pickLabelLook({}, { labelPinned: "running" }).labelPinned, "running")
})

test("nameFolded only for a sleeping pinned app with always-on names set to running", () => {
  assert.equal(L.nameFolded("always", "running", true, false), true)
  assert.equal(L.nameFolded("always", "running", true, true), false)
  assert.equal(L.nameFolded("always", "running", false, false), false)
  assert.equal(L.nameFolded("always", "always", true, false), false)
  assert.equal(L.nameFolded("hover", "running", true, false), false)
  assert.equal(L.nameFolded("off", "running", true, false), false)
})

test("readLabelConfig migrates upstream's first label keys", () => {
  const c = L.readLabelConfig({ showLabels: true, labelPlacement: "above", labelContrast: "pill", labelSize: "small" })
  assert.equal(c.labelMode, "always")
  assert.equal(c.labelBackground, "pill")
  assert.equal(c.labelColor, "auto")
  // The band's sizes were tuned for a strip under the icons; side labels
  // start from the readable default.
  assert.equal(c.labelSize, "medium")
  assert.equal(L.readLabelConfig({ showLabels: true, labelContrast: "high" }).labelColor, "auto")
  assert.equal(L.readLabelConfig({ showLabels: true, labelContrast: "theme" }).labelColor, "theme")
  assert.equal(L.readLabelConfig({ showLabels: false }).labelMode, "off")
  // New keys win over old ones.
  assert.equal(L.readLabelConfig({ showLabels: true, labelMode: "hover" }).labelMode, "hover")
})

test("readLabelConfig validates values", () => {
  assert.equal(L.readLabelConfig({ labelMode: "always", labelSize: "small" }).labelSize, "small")
  assert.equal(L.readLabelConfig({ labelMode: "always", labelColor: "high" }).labelColor, "auto")
  assert.equal(L.readLabelConfig({ labelMode: "always", labelEffect: "shadow" }).labelEffect, "outline")
  assert.equal(L.readLabelConfig({ labelWeight: "bold", labelShape: "square" }).labelWeight, "bold")
  assert.equal(L.readLabelConfig({ labelShape: "square" }).labelShape, "square")
  assert.equal(L.readLabelConfig({ labelIndicators: "after" }).labelIndicators, "after")
  assert.equal(L.readLabelConfig({ labelIndicators: "sideways" }).labelIndicators, "before")
  assert.equal(L.readLabelConfig({ labelPlateHeight: "dock" }).labelPlateHeight, "dock")
  assert.equal(L.readLabelConfig({ labelPlateHeight: "tall" }).labelPlateHeight, "icon")
  assert.equal(L.readLabelConfig({ labelShape: "blob", labelWeight: "heavy" }).labelShape, "dock")
  const c = L.readLabelConfig({ labelMode: "sideways", labelFont: "comic", labelMaxWidth: 9999, labelEffect: "glow" })
  assert.equal(c.labelMode, "off")
  assert.equal(c.labelFont, "theme")
  assert.equal(c.labelMaxWidth, 240)
  assert.equal(c.labelEffect, "glow")
  assert.equal(L.readLabelConfig({ labelMaxWidth: 10 }).labelMaxWidth, 80)
  assert.equal(L.readLabelConfig({ labelMaxWidth: "150" }).labelMaxWidth, 140)
  assert.equal(L.readLabelConfig({ labelMaxWidth: 151.6 }).labelMaxWidth, 152)
})

test("writeLabelConfig writes new keys and drops old ones", () => {
  const conf = { showLabels: true, labelPlacement: "below", labelContrast: "pill", other: 1 }
  const state = L.readLabelConfig({ labelMode: "hover", labelNames: { a: "A" } })
  L.writeLabelConfig(conf, state)
  assert.equal(conf.showLabels, undefined)
  assert.equal(conf.labelPlacement, undefined)
  assert.equal(conf.labelContrast, undefined)
  assert.equal(conf.labelMode, "hover")
  assert.deepEqual(plain(conf.labelNames), { a: "A" })
  assert.equal(conf.other, 1)
})

test("shortenName never ends a cut on a lone symbol word", () => {
  assert.deepEqual(plain(L.shortenName("Spotifast & more", fitsChars(11))), { text: "Spotifast", shortened: true })
  assert.deepEqual(plain(L.shortenName("Tools + Extras Pack", fitsChars(8))), { text: "Tools", shortened: true })
})

test("labelRadius follows the shape, or the dock's own corner ratio", () => {
  assert.equal(L.labelRadius("pill", 20, 0), 10)
  assert.equal(L.labelRadius("rounded", 20, 0.5), 5)
  assert.equal(L.labelRadius("square", 20, 0.5), 0)
  // A square dock gives square labels, a pill dock pill labels.
  assert.equal(L.labelRadius("dock", 20, 0), 0)
  assert.equal(L.labelRadius("dock", 20, 0.5), 10)
  assert.equal(L.labelRadius("dock", 20, 0.2), 4)
  assert.equal(L.labelRadius("dock", 20, 3), 10)
})

test("homeExtra counts the part of a slot's own extra that sits before its icon", () => {
  let e = {}
  e = L.withExtra(e, 0, "a", 30, 0)
  // Slot 1: 50 wide, 10 of it (a side-indicator column) before the icon.
  e = L.withExtra(e, 1, "b", 50, 10)
  assert.equal(L.homeExtra(e, 1), 40)
  assert.equal(L.homeExtra(e, 1, false), 30)
  assert.equal(L.homeExtra(e, 2), 80)
  // Same width, new split: still an update.
  const e2 = L.withExtra(e, 1, "b", 50, 50)
  assert.notEqual(e2, e)
  assert.equal(L.homeExtra(e2, 1), 80)
})

test("pickLabelLook applies a preset's label look and keeps the rest", () => {
  const cur = { labelMode: "always", labelKind: "all", labelFont: "theme", labelSize: "small", labelWeight: "medium", labelColor: "auto",
    labelBackground: "none", labelShape: "dock", labelChip: "dock", labelIndicators: "before", labelPlateHeight: "icon", labelPinned: "always", labelReveal: "slide", labelEffect: "none", labelMaxWidth: 140 }
  const out = plain(L.pickLabelLook({ labelFont: "pixel", labelBackground: "plate", labelMaxWidth: 999, labelShape: "blob", iconSize: 40 }, cur))
  assert.deepEqual(out, Object.assign({}, cur, { labelFont: "pixel", labelBackground: "plate", labelMaxWidth: 240 }))
  // A preset saved before label looks existed changes nothing.
  assert.deepEqual(plain(L.pickLabelLook({ iconSize: 40 }, cur)), cur)
  assert.equal(L.pickLabelLook({ labelEffect: "shadow" }, cur).labelEffect, "outline")
  assert.equal(L.pickLabelLook({ labelIndicators: "under" }, cur).labelIndicators, "under")
})

// The macOS callout is a look key, not a global restyle: a saved config and
// every look that does not name it keep the dock's own chip.
test("labelChip is a look key: dock by default, macOS only when a look asks", () => {
  assert.equal(L.readLabelConfig({}).labelChip, "dock")
  assert.equal(L.readLabelConfig({ labelChip: "macos" }).labelChip, "macos")
  assert.equal(L.readLabelConfig({ labelChip: "blob" }).labelChip, "dock")
  assert.equal(L.pickLabelLook({ labelChip: "macos" }, { labelChip: "dock" }).labelChip, "macos")
  assert.equal(L.pickLabelLook({ labelChip: "blob" }, { labelChip: "dock" }).labelChip, "dock")
  assert.equal(L.pickLabelLook({ labelBackground: "pill" }, { labelChip: "macos" }).labelChip, "macos")
})

test("nameRowsKey changes only when the listed apps change", () => {
  const a = [{ appId: "zen", auto: "Zen Browser" }, { appId: "t3", auto: "T3 Code" }]
  const b = [{ appId: "zen", auto: "Zen Browser", windowTitle: "x" }, { appId: "t3", auto: "T3 Code" }]
  assert.equal(L.nameRowsKey(a), L.nameRowsKey(b))
  assert.notEqual(L.nameRowsKey(a), L.nameRowsKey(a.slice(0, 1)))
})

test("withFolderName renames one pinned folder, blank restores the directory name", () => {
  const list = [{ path: "/home/u/Downloads", name: "Downloads", icon: "folder-download" }, { path: "~/code/omazen", name: "omazen", icon: "folder" }]
  const a = plain(L.withFolderName(list, "~/code/omazen", "  Zen work  "))
  assert.equal(a[1].name, "Zen work")
  assert.equal(a[1].icon, "folder")
  assert.equal(a[0].name, "Downloads")
  assert.equal(L.withFolderName(list, "~/code/omazen", "   ")[1].name, "omazen")
  assert.equal(L.withFolderName([{ path: "/data/x/", name: "q" }], "/data/x/", "")[0].name, "x")
  assert.equal(L.withFolderName([{ path: "~", name: "q" }], "~", "")[0].name, "Home")
  assert.equal(L.withFolderName(list, "~/code/omazen", "x".repeat(300))[1].name.length, 120)
  assert.equal(L.withFolderName(list, "/nope", "X"), list)
})

test("sideMarks only for an always-on plate with side indicators", () => {
  assert.equal(L.sideMarks("always", "plate", "before"), true)
  assert.equal(L.sideMarks("always", "plate", "after"), true)
  assert.equal(L.sideMarks("always", "plate", "under"), false)
  assert.equal(L.sideMarks("hover", "plate", "before"), false)
  assert.equal(L.sideMarks("always", "pill", "before"), false)
  assert.equal(L.sideMarks("off", "plate", "before"), false)
})

test("gradientAt follows the dock's gradient shader", () => {
  const base = { r: 0.5, g: 0.5, b: 0.5 }
  const black = { r: 0, g: 0, b: 0 }, white = { r: 1, g: 1, b: 1 }
  // Two colours: c2 ramps in toward the top-right end, c1 toward the bottom-left.
  const left = L.gradientAt(base, [black, white], 1, 1000, 60, 5, 55)
  const right = L.gradientAt(base, [black, white], 1, 1000, 60, 995, 5)
  assert.ok(left.r < 0.2, "left end is the first colour")
  assert.ok(right.r > 0.6, "right end leans to the second colour")
  // Strength 0 leaves the base.
  assert.deepEqual(plain(L.gradientAt(base, [black, white], 0, 1000, 60, 500, 30)), base)
  // Three colours stay within 0..1 and differ across the card.
  const a = L.gradientAt(base, [black, white, { r: 1, g: 0, b: 0 }], 0.8, 1000, 60, 10, 10)
  const b = L.gradientAt(base, [black, white, { r: 1, g: 0, b: 0 }], 0.8, 1000, 60, 990, 50)
  for (const c of [a, b]) for (const k of ["r", "g", "b"]) assert.ok(c[k] >= 0 && c[k] <= 1)
  assert.notDeepEqual(plain(a), plain(b))
})

test("steadyInk picks one ink whose weakest contrast along the dock is best", () => {
  const dark = { r: 0.08, g: 0.08, b: 0.08 }, light = { r: 0.95, g: 0.95, b: 0.95 }
  // All light behind: dark ink.
  assert.equal(L.steadyInk([{ r: 0.9, g: 0.9, b: 0.9 }, { r: 0.8, g: 0.8, b: 0.8 }], dark, light), dark)
  // All dark behind: light ink.
  assert.equal(L.steadyInk([{ r: 0.1, g: 0.1, b: 0.15 }, { r: 0.2, g: 0.2, b: 0.2 }], dark, light), light)
  // Mixed: one ink for all, the one whose worst spot still reads best.
  const mixed = [{ r: 0.45, g: 0.45, b: 0.45 }, { r: 0.6, g: 0.6, b: 0.6 }, { r: 0.35, g: 0.35, b: 0.35 }]
  const pick = L.steadyInk(mixed, dark, light)
  const worst = (ink) => Math.min(...mixed.map((c) => L.contrast(ink, c)))
  assert.equal(worst(pick), Math.max(worst(dark), worst(light)))
  assert.ok(L.contrast(dark, light) > 15)
})

test("plateSpacing keeps one gap, clamped to what plates look right with", () => {
  // In range: the spacing itself, snapped to the device-pixel grid.
  const a = plain(L.plateSpacing(6, 1, 1.5, 4, 12))
  assert.deepEqual([a.gap, a.edge, a.separator], [6, 6, 1])
  // Zero and huge spacing clamp.
  assert.equal(L.plateSpacing(0, 1, 1.5, 4, 12).gap, 4)
  assert.equal(L.plateSpacing(40, 1, 1.5, 4, 12).gap, 12)
  // Odd spacing lands on the grid at 1.5.
  const c = plain(L.plateSpacing(5, 1.3333333333333333, 1.5, 4, 12))
  assert.ok(Math.abs(c.gap * 1.5 - Math.round(c.gap * 1.5)) < 1e-9)
  // The divider slot is just the line, so line-to-plate is the gap.
  assert.equal(c.separator, c.line)
})

test("grid helpers land on whole device pixels", () => {
  const on = (v, d) => Math.abs(v * d - Math.round(v * d)) < 1e-9
  for (const d of [1, 1.25, 1.5, 2]) {
    for (const v of [44, 45, 46.3, 57]) {
      assert.ok(on(L.gridCeil(v, d), d) && L.gridCeil(v, d) >= v - 1e-9, `ceil ${v}@${d}`)
      assert.ok(on(L.gridRound(v, d), d) && Math.abs(L.gridRound(v, d) - v) <= 0.5 / d + 1e-9, `round ${v}@${d}`)
      const n = L.gridInt(Math.floor(v), d)
      assert.ok(Number.isInteger(n) && n >= Math.floor(v) && on(n, d), `int ${v}@${d}`)
    }
  }
  assert.equal(L.gridInt(45, 1.5), 46)
  assert.equal(L.gridInt(46, 1.5), 46)
})

test("plateEdges: one panel without split, its outermost items are the edges", () => {
  // Omarchy button, three pinned, no tiles, two running, two folders, no drives.
  const e = plain(L.plateEdges([
    { n: 1, labelled: true, cut: false }, { n: 3, labelled: true, cut: false },
    { n: 0, labelled: false, cut: false }, { n: 2, labelled: true, cut: false },
    { n: 2, labelled: true, cut: false }, { n: 0, labelled: false, cut: false }]))
  assert.equal(e.length, 8)
  assert.deepEqual(e[0], { left: true, right: false })
  for (let i = 1; i < 7; i++) assert.deepEqual(e[i], { left: false, right: false })
  assert.deepEqual(e[7], { left: false, right: true })
})

test("plateEdges: a drive at the edge leaves the last plate square", () => {
  const e = plain(L.plateEdges([
    { n: 1, labelled: true, cut: false }, { n: 2, labelled: true, cut: false },
    { n: 1, labelled: false, cut: false }]))
  assert.equal(e.length, 3)
  assert.deepEqual(e[2], { left: false, right: false })
})

test("plateEdges: split cuts each section into its own panel", () => {
  // button + 2 pinned | 2 running | 2 folders
  const e = plain(L.plateEdges([
    { n: 1, labelled: true, cut: false }, { n: 2, labelled: true, cut: false },
    { n: 0, labelled: false, cut: false }, { n: 2, labelled: true, cut: true },
    { n: 2, labelled: true, cut: true }, { n: 0, labelled: false, cut: false }]))
  assert.deepEqual(e.map((x) => [x.left, x.right]), [
    [true, false], [false, false], [false, true],
    [true, false], [false, true],
    [true, false], [false, true]])
})

test("plateEdges: unlabelled tiles in their own split panel", () => {
  // 2 pinned | 2 tiles | 1 running: the pinned run ends a panel, the running one is alone.
  const e = plain(L.plateEdges([
    { n: 0, labelled: true, cut: false }, { n: 2, labelled: true, cut: false },
    { n: 2, labelled: false, cut: true }, { n: 1, labelled: true, cut: true }]))
  assert.deepEqual(e.map((x) => [x.left, x.right]), [[true, false], [false, true], [true, true]])
})

test("plateEdges: a pending cut carries to the next section with items", () => {
  // Both sides + split, no folders, a drive: the cut before folders lands before the drive,
  // so the last running plate rounds on the right.
  const e = plain(L.plateEdges([
    { n: 1, labelled: true, cut: false }, { n: 1, labelled: true, cut: false },
    { n: 0, labelled: false, cut: false }, { n: 0, labelled: true, cut: true },
    { n: 0, labelled: true, cut: true }, { n: 1, labelled: false, cut: false }]))
  assert.deepEqual(e.map((x) => [x.left, x.right]), [[true, false], [false, true]])
})

test("plateEdges: without the Omarchy button the first pinned app takes the left edge", () => {
  const e = plain(L.plateEdges([{ n: 0, labelled: true, cut: false }, { n: 2, labelled: true, cut: false }]))
  assert.deepEqual(e.map((x) => [x.left, x.right]), [[true, false], [false, true]])
})

test("plateEdges: empty row and a cut before the first item", () => {
  assert.deepEqual(plain(L.plateEdges([])), [])
  assert.deepEqual(plain(L.plateEdges([{ n: 1, labelled: true, cut: true }])), [{ left: true, right: true }])
})

test("plateCorners: dock, pill and rounded round all four corners alike when they fit", () => {
  assert.deepEqual(plain(L.plateCorners("dock", 40, 6, 9, { left: true, right: false })), { tl: 6, tr: 6, bl: 6, br: 6 })
  assert.deepEqual(plain(L.plateCorners("pill", 40, 12.8, 9, null)), { tl: 12.8, tr: 12.8, bl: 12.8, br: 12.8 })
})

test("plateCorners: without edges (pills, hover labels) every shape keeps its radius", () => {
  assert.deepEqual(plain(L.plateCorners("square", 40, 6, 9, null)), { tl: 6, tr: 6, bl: 6, br: 6 })
  assert.deepEqual(plain(L.plateCorners("square", 40, 6, 9, undefined)), { tl: 6, tr: 6, bl: 6, br: 6 })
})

test("plateCorners: square squares inner corners and rounds the edge side", () => {
  assert.deepEqual(plain(L.plateCorners("square", 40, 6, 9, { left: false, right: false })), { tl: 0, tr: 0, bl: 0, br: 0 })
  assert.deepEqual(plain(L.plateCorners("square", 40, 6, 9, { left: true, right: false })), { tl: 9, tr: 0, bl: 9, br: 0 })
  assert.deepEqual(plain(L.plateCorners("square", 40, 6, 9, { left: false, right: true })), { tl: 0, tr: 9, bl: 0, br: 9 })
  assert.deepEqual(plain(L.plateCorners("square", 40, 6, 9, { left: true, right: true })), { tl: 9, tr: 9, bl: 9, br: 9 })
})

test("plateCorners: square edge radius stops at a pill end and never goes negative", () => {
  // Pill dock 72 high, gap 6: R - gap = 30 = half of a 60 px plate, not the 0.32 h cap.
  assert.deepEqual(plain(L.plateCorners("square", 60, 19.2, 30, { left: true, right: false })), { tl: 30, tr: 0, bl: 30, br: 0 })
  assert.equal(L.plateCorners("square", 40, 6, 50, { left: true, right: false }).tl, 20)
  assert.equal(L.plateCorners("square", 40, 6, -3, { left: true, right: false }).tl, 0)
})

test("plateFitRadius: the smallest edge corner that stays inside the panel's curve", () => {
  // A corner of radius r, g in from a curve of radius R, fits once r >= R - g*sqrt2/(sqrt2-1).
  assert.ok(Math.abs(L.plateFitRadius(36, 6) - (36 - 6 * Math.SQRT2 / (Math.SQRT2 - 1))) < 1e-9)
  assert.equal(L.plateFitRadius(16, 6), 0)    // a rounded dock: even a square corner fits
  assert.equal(L.plateFitRadius(0, 6), 0)     // square dock, panel
})

test("plateCorners: a chosen corner that would stick out of the panel's curve rounds with it", () => {
  // Pill dock, R 36, gap 6: square plates would poke out at the ends; the edge side takes the
  // nested radius (30, parallel to the curve), the inner side keeps the choice.
  const fit = L.plateFitRadius(36, 6)
  assert.deepEqual(plain(L.plateCorners("square", 60, 0, 30, { left: true, right: false }, fit)), { tl: 30, tr: 0, bl: 30, br: 0 })
  assert.deepEqual(plain(L.plateCorners("rounded", 60, 15, 30, { left: false, right: true }, fit)), { tl: 15, tr: 30, bl: 15, br: 30 })
  // A choice that already fits stays as chosen, on every side.
  assert.deepEqual(plain(L.plateCorners("dock", 60, 19.2, 30, { left: true, right: true }, fit)), { tl: 19.2, tr: 19.2, bl: 19.2, br: 19.2 })
  // A rounded dock: square plates still round their ends with the dock's corners.
  assert.deepEqual(plain(L.plateCorners("square", 40, 0, 10, { left: true, right: true }, L.plateFitRadius(16, 6))), { tl: 10, tr: 10, bl: 10, br: 10 })
  // Inside the row (no edge) and without edges (pills, hover): the choice.
  assert.deepEqual(plain(L.plateCorners("square", 60, 0, 30, { left: false, right: false }, fit)), { tl: 0, tr: 0, bl: 0, br: 0 })
  assert.deepEqual(plain(L.plateCorners("square", 60, 0, 30, null, fit)), { tl: 0, tr: 0, bl: 0, br: 0 })
  // Never past a pill end.
  assert.equal(L.plateCorners("square", 40, 0, 30, { left: true, right: false }, fit).tl, 20)
})

test("pillRoom: how far in a pill end's curve reaches at a given half height", () => {
  // Radius 25: at 17 px off the centre line the curve is 25 - sqrt(625 - 289) in.
  assert.ok(Math.abs(L.pillRoom(25, 17) - (25 - Math.sqrt(625 - 289))) < 1e-9)
  assert.equal(L.pillRoom(25, 0), 0)
  assert.equal(L.pillRoom(25, 30), 25)   // taller than the plate: the whole radius
  assert.equal(L.pillRoom(0, 5), 0)
})

test("square corners: square between plates, the ends round with the panel", () => {
  // What Nested used to do: an edge side takes the panel's radius less the gap.
  assert.deepEqual(plain(L.plateCorners("square", 40, 0, 9, { left: true, right: false }, 0)), { tl: 9, tr: 0, bl: 9, br: 0 })
  assert.deepEqual(plain(L.plateCorners("square", 40, 0, 9, { left: false, right: false }, 0)), { tl: 0, tr: 0, bl: 0, br: 0 })
  assert.deepEqual(plain(L.plateCorners("square", 40, 0, 9, null, 0)), { tl: 0, tr: 0, bl: 0, br: 0 })
})

test("a stored nested corner reads as square, in the config and in presets", () => {
  assert.equal(L.readLabelConfig({ labelMode: "always", labelShape: "nested" }).labelShape, "square")
  const look = plain(L.pickLabelLook({ labelShape: "nested" }, { labelShape: "dock" }))
  assert.equal(look.labelShape, "square")
})

test("plateEdges: drives with plates of their own take the edge after the folders", () => {
  // button, 2 pinned, 1 folder, 1 drive: the drive is the last plate, at the right edge.
  const e = plain(L.plateEdges([
    { n: 1, labelled: true, cut: false }, { n: 2, labelled: true, cut: false },
    { n: 0, labelled: false, cut: false }, { n: 0, labelled: true, cut: false },
    { n: 1, labelled: true, cut: false }, { n: 1, labelled: true, cut: false }]))
  assert.equal(e.length, 5)
  assert.deepEqual(e[3], { left: false, right: false })
  assert.deepEqual(e[4], { left: false, right: true })
})

test("withNatural keeps one entry per slot and only its owner clears it", () => {
  let m = L.withNatural({}, 3, "a", { text: 50, inner: 20, outer: 24, folded: 0 })
  assert.deepEqual(plain(m), { 3: { owner: "a", text: 50, inner: 20, outer: 24, folded: 0 } })
  assert.equal(L.withNatural(m, 3, "a", { text: 50, inner: 20, outer: 24, folded: 0 }), m)
  assert.equal(L.withNatural(m, 3, "b", null), m)
  assert.deepEqual(plain(L.withNatural(m, 3, "a", null)), {})
})
