// Tests for DockPresets.js, the looks a fresh install offers: the shape a
// shipped preset must hold, and the merge that puts them in front of the
// presets a user saved. Plain JS, run in a vm context like DockModel.js (the
// merge fills each shipped look through pickLook, so both modules load).
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const root = new URL("../../", import.meta.url)
const ctx = vm.createContext({ console, Quickshell: { iconPath: () => "" } })
for (const file of ["DockModel.js", "DockPresets.js", "DockLabels.js"])
  vm.runInContext(readFileSync(new URL(file, root), "utf8"), ctx)
const plain = (v) => JSON.parse(JSON.stringify(v))

const SHIPPED = plain(ctx.SHIPPED)
const merged = (user) => plain(ctx.merge(user, ctx.pickLook))

// A preset's label keys are applied through DockLabels.pickLabelLook, which
// keeps a value only when it is one of the lists below and otherwise falls
// back to the value already on the dock -- so a misspelled enum in a shipped
// look would ship a look that silently does nothing. Assert the values here.
const LABEL_LISTS = {
  labelMode: "LABEL_MODES", labelKind: "LABEL_KINDS", labelFont: "LABEL_FONTS",
  labelSize: "LABEL_SIZES", labelWeight: "LABEL_WEIGHTS", labelColor: "LABEL_COLORS",
  labelBackground: "LABEL_BACKGROUNDS", labelShape: "LABEL_SHAPES",
  labelIndicators: "LABEL_INDICATORS", labelPlateHeight: "LABEL_PLATE_HEIGHTS", labelPinned: "LABEL_PINNED",
  labelReveal: "LABEL_REVEALS", labelEffect: "LABEL_EFFECTS",
}

test("every label key a shipped look carries is a value the labels accept", () => {
  let shown = 0
  for (const p of SHIPPED) {
    for (const [key, listName] of Object.entries(LABEL_LISTS)) {
      if (!(key in p.look)) continue
      const allowed = plain(ctx[listName])
      assert.ok(allowed.includes(p.look[key]),
        `${p.name}.${key} = ${JSON.stringify(p.look[key])} is not one of ${allowed.join(", ")}`)
    }
    if (p.look.labelMode && p.look.labelMode !== "off") shown++
  }
  assert.ok(shown >= 1, "at least one shipped look shows the names")
  // macOS shows the name on hover; the Windows taskbar never carries one.
  assert.equal(SHIPPED.find((p) => p.name === "macOS").look.labelMode, "hover")
  assert.equal(SHIPPED.find((p) => p.name === "Windows").look.labelMode, "off")
})

// The taskbar is more than a look: a full-width, always-visible bottom panel
// with 24px-class artwork, no magnification and one pill per running app. The
// The setup is what a look cannot spell, which is why a shipped preset carries
// it; applying the look alone used to leave a floating, auto-hiding dock.
test("the Windows look is the taskbar, and carries the setup it needs", () => {
  const w = SHIPPED.find((p) => p.name === "Windows")
  assert.ok(w, "the taskbar look ships")
  assert.deepEqual(plain(w.setup), {
    layout: "panel", alignment: "center", autohide: false, intelligentAutohide: false,
    showMinimizedTiles: false
  })
  assert.equal(w.look.shape, "square")
  assert.equal(w.look.cornerRadius, 0)
  assert.equal(w.look.showBorder, false)
  assert.equal(w.look.hoverEffect, "off", "a taskbar does not magnify")
  assert.equal(w.look.magnifyPeak, 1)
  assert.equal(w.look.indicatorMode, "app", "one mark per app, not per window")
  assert.equal(w.look.indicatorShape, "rounded")
  // iconSlot is iconSize + iconMargin in style units (29 + 11); 4px of card
  // padding each side lands the bar at ~50px on this desktop's UI scale.
  assert.equal(w.look.iconSize + w.look.iconMargin, 40)
  assert.equal(w.look.dockPaddingPx, 4)
})

test("only a shipped look carries setup; a saved preset never does", () => {
  const windows = merged([]).find((p) => p.name === "Windows")
  assert.deepEqual(plain(windows.setup), plain(SHIPPED.find((p) => p.name === "Windows").setup),
    "merge keeps the shipped setup")
  for (const p of merged([])) {
    if (p.name === "Windows") continue
    assert.equal(p.setup, undefined, `${p.name} leaves the user's placement alone`)
  }
  // boundPresets is what a saved preset is read back through, and it keeps
  // only id/name/look, so a setup in a hand-edited config is dropped rather
  // than moving the dock when that preset is applied.
  const saved = { id: "preset_1", name: "Mine", look: plain(ctx.pickLook({})),
    setup: { layout: "panel", alignment: "center", autohide: false } }
  assert.equal(plain(ctx.boundPresets([saved]))[0].setup, undefined)
})

test("shipped presets are well formed and distinct", () => {
  assert.ok(SHIPPED.length >= 1, "at least one look ships")
  const ids = new Set()
  const names = new Set()
  for (const p of SHIPPED) {
    assert.match(p.id, /^[A-Za-z0-9_]{1,64}$/, `${p.name} has a storable id`)
    assert.doesNotMatch(p.id, /^preset_\d+$/, `${p.name} cannot take a saved preset's id`)
    assert.equal(p.name, ctx.cleanPresetName(p.name), `${p.name} is a clean, trimmed name`)
    assert.ok(p.name.length > 0 && p.name.length <= ctx.MAX_PRESET_NAME)
    assert.ok(!ids.has(p.id) && !names.has(p.name), `${p.name} is unique`)
    ids.add(p.id)
    names.add(p.name)
  }
})

test("every shipped look fills out to the whole look model", () => {
  for (const p of SHIPPED) {
    const look = plain(ctx.pickLook(p.look))
    assert.deepEqual(Object.keys(look).sort(), plain(ctx.LOOK_KEYS).sort(),
      `${p.name} holds every look key`)
    for (const [k, v] of Object.entries(look)) {
      const scalar = typeof v === "string" || typeof v === "boolean"
        || (typeof v === "number" && isFinite(v))
      assert.ok(scalar, `${p.name}.${k} is a scalar a preset can hold`)
    }
  }
})

test("shipped looks differ from each other", () => {
  const seen = new Map()
  for (const p of SHIPPED) {
    const key = JSON.stringify(plain(ctx.pickLook(p.look)))
    assert.ok(!seen.has(key), `${p.name} differs from ${seen.get(key)}`)
    seen.set(key, p.name)
  }
})

test("a dock with no saved presets still offers every shipped look", () => {
  const list = merged([])
  assert.equal(list.length, SHIPPED.length)
  assert.deepEqual(list.map((p) => p.name), SHIPPED.map((p) => p.name))
  assert.ok(list.every((p) => p.builtin === true), "each entry is marked as shipped")
  assert.equal(plain(ctx.userCount(list)), 0)
  assert.deepEqual(plain(ctx.userOnly(list)), [])
})

test("saved presets follow the shipped ones and stay untouched", () => {
  const saved = [
    { id: "preset_1", name: "Mine", look: plain(ctx.pickLook({ grain: 0.5, iconStyle: "mono" })) },
    { id: "preset_2", name: "Other", look: plain(ctx.pickLook({})) }
  ]
  const list = merged(saved)
  assert.equal(list.length, SHIPPED.length + saved.length)
  assert.deepEqual(list.slice(-saved.length), saved, "the user's own entries are kept verbatim")
  assert.deepEqual(plain(ctx.userOnly(list)), saved)
  assert.equal(plain(ctx.userCount(list)), saved.length)
  // What the dock writes back is exactly what the user had.
  assert.deepEqual(plain(ctx.boundPresets(ctx.userOnly(list))), saved)
})

test("one row per name: the saved preset wins its name and the shipped one steps aside", () => {
  const r = merged([]).find((p) => p.name === "thepathless:ristretto")
  const mine = { id: "preset_7", name: "thepathless:ristretto", look: plain(r.look) }
  const list = merged([mine])
  // Exactly one row under that name, and it is the entry the user saved.
  const named = list.filter((p) => ctx.nameKey(p.name) === ctx.nameKey(mine.name))
  assert.equal(named.length, 1, "the name is listed once")
  assert.deepEqual(named[0], mine, "the listed row is the user's own, verbatim")
  assert.notEqual(named[0].builtin, true, "it stays the row they can edit")
  // Every other shipped look is untouched, and the entry is not hidden data:
  // it is still the user's preset, still counted, still what gets written back.
  assert.equal(list.length, SHIPPED.length - 1 + 1)
  for (const p of SHIPPED)
    if (p.name !== mine.name) assert.ok(list.some((x) => x.name === p.name), `${p.name} still ships`)
  assert.deepEqual(plain(ctx.userOnly(list)), [mine])
  assert.equal(plain(ctx.userCount(list)), 1)
  assert.deepEqual(plain(ctx.boundPresets(ctx.userOnly(list))), [mine])
})

test("the collision rule ignores case and surrounding space", () => {
  const mine = { id: "preset_8", name: "  ThePathless:RISTRETTO ", look: plain(ctx.pickLook({})) }
  const list = merged([mine])
  assert.equal(list.filter((p) => ctx.nameKey(p.name) === "thepathless:ristretto").length, 1)
  assert.deepEqual(list[list.length - 1], mine)
  // Without a collision the shipped look is back, and a saved preset that
  // shares no name never displaces anything.
  const other = { id: "preset_9", name: "Mine", look: plain(ctx.pickLook({})) }
  const clean = merged([other])
  assert.equal(clean.length, SHIPPED.length + 1)
  assert.ok(clean.some((p) => p.name === "thepathless:ristretto" && p.builtin === true))
})

test("thepathless:ristretto pins the look the maintainer's dock runs", () => {
  const r = merged([]).find((p) => p.name === "thepathless:ristretto")
  assert.ok(r, "the owner's look ships")
  // Its stated keys, then the defaults for every key it leaves out.
  assert.deepEqual(plain(ctx.pickLook(r.look)), plain(ctx.pickLook({
    bgFill: "gradient", gradientPreset: "forest", gradientStrength: 0.25, grain: 0.2,
    dividerGeometry: "long", dividerStyle: "custom",
    iconStyle: "dots", iconGrid: 8, iconContrast: 0.4, iconStrength: 0.45, iconSize: 34,
    hoverEffect: "glitch", opacity: "theme", shape: "theme",
    showBorder: false, showShadow: false
  })))
  assert.equal(r.look.iconStyle, "dots")
  assert.equal(r.look.gradientPreset, "forest")
  assert.equal(r.look.showShadow, false)
  assert.equal(r.look.hoverEffect, "glitch")
  assert.equal(r.look.opacity, "theme")
})

test("a key-for-key tie goes to the saved preset, not the shipped row", () => {
  const mac = merged([]).find((p) => p.name === "macOS")
  // The user's own copy of that look, under a name of their own: no name
  // collision, so merge keeps both rows and only the active mark can tell.
  const mine = { id: "preset_1700000000000", name: "Mine", look: plain(mac.look) }
  const list = merged([mine])
  assert.equal(list.findIndex((p) => p.builtin === true), 0,
    "the shipped looks lead the list, which is why the tie needs settling")
  assert.equal(ctx.activeId(list, plain(mac.look), ctx.lookIncludes), mine.id,
    "the row the user can edit takes the active mark")
  assert.notEqual(ctx.activeId(list, plain(mac.look), ctx.lookIncludes), mac.id,
    "the read-only shipped row does not")
  // A look only a shipped preset matches still marks that one, whether or not
  // anything was saved.
  const win = merged([]).find((p) => p.name === "Windows")
  assert.equal(ctx.activeId(list, plain(win.look), ctx.lookIncludes), win.id)
  assert.equal(ctx.activeId(merged([]), plain(win.look), ctx.lookIncludes), win.id)
  // Nothing matches: no row is marked, and an empty list answers "".
  assert.equal(ctx.activeId(list, plain(ctx.pickLook({ grain: 0.9 })), ctx.lookIncludes), "")
  assert.equal(ctx.activeId([], plain(ctx.pickLook({})), ctx.lookIncludes), "")
})
