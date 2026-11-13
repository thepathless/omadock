// Tests for DockPins.js: the pin list's own operations. The module decides no
// identity, so the toggle is always handed DockModel.isAppMatch; the last test
// pins the two small normalisers it restates to the model's own answers (a root
// JS module cannot import another, see the file header).
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

function load(name) {
  const ctx = vm.createContext({ console })
  vm.runInContext(readFileSync(new URL("../../" + name, import.meta.url), "utf8"), ctx)
  return ctx
}

const M = load("DockModel.js")
const P = load("DockPins.js")
const plain = value => JSON.parse(JSON.stringify(value))
const toggle = (list, id) => P.togglePinned(list, id, M.isAppMatch)

test("isPinned answers for the id as written, with or without .desktop", () => {
  assert.equal(P.isPinned(["foot", "Gmail"], "foot"), true)
  assert.equal(P.isPinned(["foot", "Gmail"], "Gmail.desktop"), true)
  assert.equal(P.isPinned(["foot"], "com.mitchellh.ghostty"), false)
  assert.equal(P.isPinned([], "foot"), false)
  assert.equal(P.isPinned(undefined, "foot"), false)
})

test("isPinned accepts a desktop row as well as an id string", () => {
  assert.equal(P.isPinned(["foot"], { appId: "foot", name: "Foot" }), true)
  assert.equal(P.isPinned(["foot"], { appId: "Gmail" }), false)
})

test("isPinned reads a Qt list, not only a JS array", () => {
  const qtList = { length: 2, 0: "foot", 1: "Gmail" }
  assert.equal(P.isPinned(qtList, "Gmail"), true)
  assert.equal(P.isPinned(qtList, "Discord"), false)
})

test("toggle removes a pin matched by identity, else appends the stripped id", () => {
  // The pin was made as "hermes"; the entry it resolves to now is the vendor id.
  assert.deepEqual(plain(toggle(["foot", "hermes"], "com.nousresearch.hermes")), ["foot"])
  assert.deepEqual(plain(toggle(["foot"], "Discord")), ["foot", "Discord"])
  assert.deepEqual(plain(toggle(["foot"], "Discord.desktop")), ["foot", "Discord"])
})

test("toggle removes every spelling of one app in one pass", () => {
  assert.deepEqual(
    plain(toggle(["foot", "hermes", "Gmail", "com.nousresearch.hermes"], "hermes")),
    ["foot", "Gmail"])
})

test("toggle leaves the list alone for an empty id and never mutates its input", () => {
  const input = ["foot", "", "  "]
  const copy = input.slice()
  assert.deepEqual(plain(toggle(input, "")), input)
  assert.deepEqual(input, copy)
})

test("reorder moves a pin, appends it to the end, and no-ops on itself", () => {
  assert.deepEqual(plain(P.reorderPinned(["a", "b", "c"], "c", "a")), ["c", "a", "b"])
  assert.deepEqual(plain(P.reorderPinned(["a", "b", "c"], "a", null)), ["b", "c", "a"])
  assert.deepEqual(plain(P.reorderPinned(["a", "b", "c"], "a", "")), ["b", "c", "a"])
  assert.deepEqual(plain(P.reorderPinned(["a", "b", "c"], "b", "b")), ["a", "b", "c"])
  assert.deepEqual(plain(P.reorderPinned(["a", "b"], "a", "zz")), ["b", "a"])
})

test("moveBefore moves one slot and returns the list itself when nothing moves", () => {
  const list = [1, 2, 3]
  assert.deepEqual(plain(P.moveBefore(list, 0, 3)), [2, 3, 1])
  assert.deepEqual(plain(P.moveBefore(list, 2, 0)), [3, 1, 2])
  assert.equal(P.moveBefore(list, 1, 1), list)
  assert.equal(P.moveBefore(list, 1, 2), list)
  assert.equal(P.moveBefore(list, 5, 0), list)
  assert.equal(P.moveBefore(list, -1, 0), list)
})

// The two restated normalisers must answer what DockModel.stripDesktop does, or
// the pin list and the model would disagree about which app a row names.
test("the restated normalisers agree with DockModel", () => {
  for (const raw of ["foot", "Gmail.desktop", " Gmail.desktop ", "", "   ", null, undefined, 7,
    { appId: "Gmail" }, { appId: "" }]) {
    const id = M.stripDesktop(raw)
    assert.equal(P.isPinned([id], raw), Boolean(id), `isPinned(${JSON.stringify(raw)})`)
    if (id) assert.equal(P.isPinned([raw], id), true, `isPinned(${JSON.stringify(raw)}) as the list`)
  }
  // A rejected list answers empty, exactly as DockModel.toArray does.
  for (const bad of [null, undefined, "", "foot", () => {}]) {
    assert.equal(P.isPinned(bad, "foot"), false)
    assert.deepEqual(plain(P.reorderPinned(bad, "", null)), [])
  }
})
