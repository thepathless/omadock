// Tests for DockMarks.js, the pure helpers behind the dock's running marks:
// how many an item draws and how many slots the row declares to draw them.
// Plain JS with no Qt globals, run in a vm context like DockLabels.js.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMARKS || new URL("../../DockMarks.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), M)
const plain = (v) => JSON.parse(JSON.stringify(v))
const win = (n) => Array.from({ length: n }, (_, i) => ({ address: "0x" + i }))
// total, dense, overflow, dots, slots for an item with n windows.
const shape = (n) => {
  const p = plain(M.plan(win(n), false))
  return [p.total, p.dense, p.overflow, p.dots, p.slots]
}

test("totalWindows: the windows it knows, else one while the app runs", () => {
  assert.equal(M.totalWindows([], false), 0)
  assert.equal(M.totalWindows(null, false), 0)
  assert.equal(M.totalWindows([], true), 1)
  assert.equal(M.totalWindows(null, true), 1)
  assert.equal(M.totalWindows(win(1), false), 1)
  assert.equal(M.totalWindows(win(9), false), 9)
  // A running app whose windows the dock cannot see yet still draws one mark.
  assert.equal(M.plan([], true).dots, 1)
  assert.deepEqual(plain(M.plan([], true)), { total: 1, dense: false, overflow: false, dots: 1, slots: 1 })
})

test("plan: one mark per window to five, then four and the overflow pill", () => {
  assert.deepEqual(shape(0), [0, false, false, 0, 1])
  assert.deepEqual(shape(1), [1, false, false, 1, 1])
  assert.deepEqual(shape(2), [2, false, false, 2, 2])
  assert.deepEqual(shape(4), [4, false, false, 4, 4])
  assert.deepEqual(shape(5), [5, true, false, 5, 5])
  assert.deepEqual(shape(6), [6, true, true, 4, 5])
  assert.deepEqual(shape(7), [7, true, true, 4, 5])
  assert.deepEqual(shape(40), [40, true, true, 4, 5])
})

// The bug the single owner of the count fixed: a Grid reserves a gap for every
// slot it declares, so a slot with no drawn mark to fill it pushes the marks
// that are drawn off the icon's centre - at eight declared slots, 2 px. However
// many windows there are, the slots must be the marks drawn and never more,
// the one exception being an item that draws nothing at all, where the empty
// Grid still declares a slot.
test("plan: declared slots never outnumber drawn marks", () => {
  for (let n = 0; n <= 60; n++) {
    const { dots, overflow, slots } = plain(M.plan(win(n), false))
    const drawn = dots + (overflow ? 1 : 0)
    assert.equal(drawn, n > 5 ? 5 : n, `marks drawn for ${n} windows`)
    assert.equal(slots, Math.max(1, drawn), `slots declared for ${n} windows`)
    if (drawn > 0) assert.equal(slots, drawn, `spare slot declared for ${n} windows`)
  }
})

// The taskbar look (Windows) speaks for the app, not each window: one mark,
// and the focused app's mark is the accent bar. Per-window mode keeps all
// three states, which is what the rest of the dock ships.
test("markKind: app mode shows the active bar for the focused app", () => {
  assert.equal(M.markKind(true, true, false), "active")
  assert.equal(M.markKind(true, false, false), "window")
  // Minimized but running is still one open window to the taskbar.
  assert.equal(M.markKind(true, false, true), "window")
  assert.equal(M.markKind(false, true, false), "active")
  assert.equal(M.markKind(false, false, false), "window")
  assert.equal(M.markKind(false, false, true), "minimized")
})

test("plan: the pill counts the windows the dots do not show", () => {
  for (let n = 6; n <= 60; n++) {
    const { total, dots } = plain(M.plan(win(n), false))
    assert.equal(total - dots, n - 4, `the +N the pill shows for ${n} windows`)
  }
})
