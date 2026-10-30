import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const base = new URL("../../", import.meta.url)
const plain = (v) => JSON.parse(JSON.stringify(v))
function module(file) {
  const ctx = vm.createContext({ console })
  vm.runInContext(readFileSync(new URL(file, base), "utf8"), ctx)
  return ctx
}
const DockModel = module("DockModel.js")
const DockPresets = module("DockPresets.js")
const DockLabels = module("DockLabels.js")
const ctx = vm.createContext({ console, DockModel, DockPresets, DockLabels,
  DockLayout: module("DockLayout.js"), DockMotion: module("DockMotion.js"),
  DockFloating: module("DockFloating.js"), Buttons: module("Buttons.js") })
// Run the actual QtObject function bodies, not a copy of preset application.
const qml = readFileSync(new URL("components/logic/DockConfigLogic.qml", base), "utf8")
vm.runInContext(qml.slice(qml.indexOf("QtObject {") + "QtObject {".length, qml.lastIndexOf("}")), ctx)

const expected = {
  "thepathless:ristretto": { layout: "dock", alignment: "center", autohide: true,
    intelligentAutohide: true, showMinimizedTiles: true, minimizeMode: "active", showAppsButton: true },
  macOS: { layout: "dock", alignment: "center", autohide: true,
    intelligentAutohide: true, showMinimizedTiles: true, minimizeMode: "off", showAppsButton: true },
  Windows: { layout: "panel", alignment: "taskbar", autohide: false,
    intelligentAutohide: false, showMinimizedTiles: false, minimizeMode: "active", showAppsButton: true }
}
function root(config = {}) {
  const r = { floatingWatch: {}, writes: [], syncs: 0,
    applyBlurRule() {}, syncVisibility() { this.syncs++ },
    saveConfig() { this.writes.push(plain(ctx.buildConfig(this, {}))) } }
  Object.defineProperty(r, "currentLook", { get: () => DockModel.pickLook(ctx.buildConfig(r, {})) })
  ctx.loadConfig(r, JSON.stringify(config))
  return r
}
function apply(r, name) {
  const p = r.presets.find((p) => p.name === name)
  assert.ok(p, `${name} is listed`)
  assert.equal(ctx.applyPreset(r, p.id), true)
  return p
}
function setup(r) {
  return Object.fromEntries(Object.keys(expected.Windows).map((key) => [key, r[key]]))
}
const preferences = { showTooltips: false, advancedTooltips: false, restoreWorkspace: "origin",
  restoreSlot: true, keepPointer: false, animations: "reduced", tooltipDelay: 1234,
  showNotificationBadges: false, perMonitorApps: false, screen: "test-output" }

for (const from of Object.keys(expected)) {
  for (const to of Object.keys(expected)) {
    test(`shipped transition ${from} -> ${to} establishes setup and preserves preferences`, () => {
      const r = root(preferences)
      apply(r, from)
      const p = apply(r, to)
      assert.deepEqual(setup(r), expected[to])
      const saved = r.writes.at(-1)
      for (const [key, value] of Object.entries(preferences)) assert.equal(saved[key], value, key)
      for (const [key, value] of Object.entries(expected[to])) assert.equal(saved[key], value, key)
      assert.equal(saved.clickToMinimize, expected[to].minimizeMode !== "off", "legacy mirror")
      assert.equal(ctx.activePresetId(r), p.id)
      assert.equal(r.syncs, 2)
      const reloaded = root(saved)
      assert.deepEqual(setup(reloaded), expected[to], "setup survives a config reload")
      assert.equal(ctx.activePresetId(reloaded), p.id)
    })
  }
}

test("each required setup key participates in active detection without locking the controls", () => {
  for (const name of Object.keys(expected)) {
    const r = root()
    const p = apply(r, name)
    for (const [key, value] of Object.entries(expected[name])) {
      r[key] = typeof value === "boolean" ? !value : key === "minimizeMode" ? "all" : key === "layout" ? "other" : "right"
      assert.equal(ctx.activePresetId(r), "", `${name}.${key} clears the active mark`)
      assert.equal(r[key], typeof value === "boolean" ? !value : key === "minimizeMode" ? "all" : key === "layout" ? "other" : "right",
        "active detection does not undo a user's adjustment")
      r[key] = value
      assert.equal(ctx.activePresetId(r), p.id, `${name}.${key} restored`)
    }
    r.showTooltips = !r.showTooltips
    r.advancedTooltips = !r.advancedTooltips
    r.restoreWorkspace = "origin"
    assert.equal(ctx.activePresetId(r), p.id, "optional preferences do not invalidate a preset")
    r.grain = 0.91
    assert.equal(ctx.activePresetId(r), "", "appearance still participates")
  }
})

test("saved presets stay look-only, win ties, and never inherit shipped setup by name", () => {
  const windows = DockPresets.merge([], DockModel.pickLook).find((p) => p.name === "Windows")
  const mine = { id: "preset_1", name: "My Windows", look: plain(windows.look), setup: expected.macOS }
  const r = root({ ...preferences, layout: "dock", alignment: "right", minimizeMode: "all", presets: [mine] })
  const before = setup(r)
  assert.equal(r.presets.find((p) => p.id === mine.id).setup, undefined, "legacy schema remains id/name/look")
  apply(r, mine.name)
  assert.deepEqual(setup(r), before, "applying a saved look does not move the dock or change behavior")
  assert.equal(ctx.activePresetId(r), mine.id, "saved tie wins even without Windows setup")
  apply(r, "Windows")
  assert.equal(ctx.activePresetId(r), mine.id, "saved tie also wins with matching setup")
  assert.deepEqual(plain(r.writes.at(-1).presets), [{ id: mine.id, name: mine.name, look: mine.look }])
  // A saved row that shadows the shipped name must not acquire its behavior.
  const collision = root({ layout: "panel", alignment: "left", minimizeMode: "all",
    presets: [{ ...mine, name: "macOS" }] })
  const beforeCollision = setup(collision)
  apply(collision, "macOS")
  assert.deepEqual(setup(collision), beforeCollision)
  assert.equal(ctx.activePresetId(collision), mine.id)
})

test("an untrusted runtime saved row cannot apply setup either", () => {
  const r = root()
  const p = { id: "preset_2", name: "Injected", look: DockModel.pickLook({}), setup: expected.Windows }
  r.presets = [p]
  const before = setup(r)
  apply(r, p.name)
  assert.deepEqual(setup(r), before)
  assert.equal(ctx.activePresetId(r), p.id)
})

test("transitions drive the actual click and minimized-tile policy without desktop actions", () => {
  function logic(file) {
    const source = readFileSync(new URL(file, base), "utf8")
    const scope = vm.createContext({})
    vm.runInContext(source.slice(source.indexOf("QtObject {") + "QtObject {".length, source.lastIndexOf("}")), scope)
    return scope
  }
  const windows = logic("components/logic/DockWindowLogic.qml")
  const style = logic("components/logic/DockStyleLogic.qml")
  const r = root()
  const first = { address: "0x1", appId: "test", title: "First" }
  const second = { address: "0x2", appId: "test", title: "Second" }
  let visible = [first], parked = [], actions = []
  Object.assign(r, {
    appLibrary: {}, urgentMap: {}, minimizedWindows: [first],
    entryForId: () => ({ appId: "test", running: true, windowList: visible.concat(parked) }),
    visibleWindows: () => visible, parkedWindows: () => parked,
    focusedIndex: () => visible.length ? 0 : -1, clearUrgentApp() {},
    stepWindow: () => visible[1] || null,
    minimizeToplevel: (address) => actions.push(["minimize", address]),
    focusWindowByAddress: (address) => actions.push(["focus", address]),
    restoreWindow: (win) => actions.push(["restore", win.address]),
    recentParked: () => parked[0], oldestParked: () => parked[0]
  })
  for (const name of ["Windows", "macOS", "thepathless:ristretto", "Windows", "macOS"]) {
    apply(r, name)
    actions = []
    visible = [first]
    windows.activate(r, "test")
    assert.deepEqual(actions, name === "macOS" ? [] : [["minimize", first.address]], name)
    actions = []
    visible = [first, second]
    windows.activate(r, "test")
    assert.deepEqual(actions, name === "macOS" ? [["focus", second.address]] : [["minimize", first.address]], name)
    assert.equal(style.tileModel(r).length, name === "Windows" ? 0 : 1, `${name} separate minimized tiles`)
    actions = []
    visible = []
    parked = [first]
    windows.activate(r, "test")
    assert.deepEqual(actions, [["restore", first.address]], `${name} still restores a minimized app`)
    parked = []
  }
})

test("shipped active detection fails closed without required setup state; old saved callers still work", () => {
  const list = DockPresets.merge([], DockModel.pickLook)
  for (const p of list) assert.equal(DockPresets.activeId(list, p.look, DockModel.lookIncludes), "")
  const mine = { id: "preset_3", name: "Old saved", look: DockModel.pickLook({}) }
  assert.equal(DockPresets.activeId([mine], mine.look, DockModel.lookIncludes), mine.id)
})
