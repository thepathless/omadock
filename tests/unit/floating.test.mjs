// Tests for DockFloating.js: which dock a floating workspace gets.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKFLOATING || new URL("../../DockFloating.js", import.meta.url)
const F = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), F)

test("an unknown choice falls back to hiding Omarchy's dock", () => {
  assert.equal(F.normalizeChoice("hide-omadock"), "hide-omadock")
  assert.equal(F.normalizeChoice("both"), "both")
  assert.equal(F.normalizeChoice(undefined), "hide-omarchy")
  assert.equal(F.normalizeChoice("omadock"), "hide-omarchy")
})

test("a workspace's own mode file decides, else the default", () => {
  const own = 'o.workspace_mode({ workspace = "3", mode = "floating" })\n'
  const tiled = 'o.workspace_mode({ workspace = "3", mode = "dwindle" })\n'
  const floatDefault = 'o.workspace_default_mode({ default = "floating" })\n'
  assert.equal(F.isFloating(3, own, ""), true)
  assert.equal(F.isFloating(3, tiled, floatDefault), false)
  // No file of its own (the toggle removes it on reaching the default).
  assert.equal(F.isFloating(3, "", floatDefault), true)
  assert.equal(F.isFloating(3, "", ""), false)
})

test("special and named workspaces never float", () => {
  const own = 'mode = "floating"'
  assert.equal(F.isFloating(-98, own, ""), false)
  assert.equal(F.isFloating(0, own, ""), false)
  assert.equal(F.isFloating(undefined, own, ""), false)
})

test("omarchy.dock is switched only when its state differs from the choice", () => {
  const on = JSON.stringify({ version: 1, disabledPlugins: ["omarchy.lock"] })
  const off = JSON.stringify({ version: 1, disabledPlugins: ["omarchy.lock", "omarchy.dock"] })
  const none = JSON.stringify({ version: 1 })
  assert.equal(F.omarchyDockAction("hide-omarchy", on), "disable")
  assert.equal(F.omarchyDockAction("hide-omarchy", none), "disable")
  assert.equal(F.omarchyDockAction("hide-omarchy", off), "")
  assert.equal(F.omarchyDockAction("hide-omadock", off), "enable")
  assert.equal(F.omarchyDockAction("hide-omadock", on), "")
  assert.equal(F.omarchyDockAction("both", on), "")
  assert.equal(F.omarchyDockAction("both", off), "")
})

test("the scratchpad hides the dock only on a positive word from Hyprland", () => {
  assert.equal(F.scratchpadOpen({ lastIpcObject: { specialWorkspace: { id: -99, name: "special:scratchpad" } } }), true)
  assert.equal(F.scratchpadOpen({ lastIpcObject: { specialWorkspace: { id: -99, name: "scratchpad" } } }), true)
  // Every unknown shape leaves the dock on screen: it must never be guessed away.
  assert.equal(F.scratchpadOpen(null), false)
  assert.equal(F.scratchpadOpen(undefined), false)
  assert.equal(F.scratchpadOpen({}), false)
  assert.equal(F.scratchpadOpen({ lastIpcObject: null }), false)
  assert.equal(F.scratchpadOpen({ lastIpcObject: {} }), false)
  assert.equal(F.scratchpadOpen({ lastIpcObject: { specialWorkspace: { id: 0, name: "" } } }), false)
  assert.equal(F.scratchpadOpen({ lastIpcObject: { specialWorkspace: { name: "special:magic" } } }), false)
  assert.equal(F.scratchpadOpen({ lastIpcObject: { specialWorkspace: { name: 7 } } }), false)
  assert.equal(F.scratchpadOpen({ lastIpcObject: { specialWorkspace: "special:scratchpad" } }), false)
})

test("an unreadable shell.json changes nothing", () => {
  assert.equal(F.omarchyDockAction("hide-omarchy", ""), "")
  assert.equal(F.omarchyDockAction("hide-omarchy", "{ not json"), "")
  assert.equal(F.omarchyDockAction("hide-omadock", "[]"), "")
  assert.equal(F.omarchyDockAction("hide-omarchy", "null"), "")
})
