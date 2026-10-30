// Tests for DockMarkGeometry.js, the one owner of how big a dock mark is and how
// much room it needs. Plain JS with no Qt globals, run in a vm context like
// DockLabels.js.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMARKGEOMETRY || new URL("../../DockMarkGeometry.js", import.meta.url)
const G = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), G)
const plain = (v) => JSON.parse(JSON.stringify(v))
// Style.space: whole pixels, never below one (shell Commons/Style.qml).
const space = (scale) => (n) => Math.max(1, Math.round(n * scale))

test("snap: a size lands on the pixel grid, never below one", () => {
  assert.equal(G.snap(5, 1), 5)
  assert.equal(G.snap(4, 1), 4)
  assert.equal(G.snap(5, 1.5), 8 / 1.5)   // 7.5 device px rounds to 8
  assert.equal(G.snap(4, 1.5), 4)
  assert.equal(G.snap(5, 2), 5)
  assert.equal(G.snap(4, 3), 4)
  assert.equal(G.snap(0.5, 1), 1)
})

test("cell: as wide as the widest mark, a dot or the bar", () => {
  assert.equal(G.cell(space(1), 1, false, false), 5)   // 5px dot
  assert.equal(G.cell(space(1), 1, true, false), 4)    // dense
  assert.equal(G.cell(space(1), 1, false, true), 5)    // side column draws the full dot
  assert.equal(G.cell(space(1), 1, true, true), 5)     // ...dense or not
  assert.equal(G.cell(space(1), 2, false, false), 5)
  assert.equal(G.cell(space(1.5), 1.5, false, false), 8)   // a denser theme, at 1.5x
})

test("dot: the mark itself, a hairline at the very least", () => {
  assert.equal(G.dot(space(1), 1, false, false), 5)
  assert.equal(G.dot(space(1), 1, true, false), 4)
  assert.equal(G.dot(space(1), 1, false, true), 5)
  assert.equal(G.dot(space(1), 1.5, true, true), 8 / 1.5)   // 8 device px at 1.5x, dense or not
  assert.equal(G.dot(space(1), 4, false, false), 5)
  // A theme too dense to draw a whole pixel still gets 2/dpr.
  assert.equal(G.dot(() => 1, 1, false, false), 2)
  assert.equal(G.dot(() => 1, 1, true, true), 2)
})

test("bar: the accent bar's thickness and length", () => {
  assert.equal(G.barThickness(space(1), 1), 4)
  assert.equal(G.barThickness(space(1), 2), 4)
  assert.equal(G.barLength(space(1), 1, false), 12)
  assert.equal(G.barLength(space(1), 1, true), 9)
  assert.equal(G.barLength(space(1), 2, false), 12)
})

test("taskbar: the 12x2 running pill widens to 20x2 when focused", () => {
  assert.equal(G.taskbarLength(space(1), 1, false), 12)
  assert.equal(G.taskbarLength(space(1), 1, true), 20)
  assert.equal(G.taskbarThickness(space(1), 1), 2)
  assert.equal(G.taskbarCell(space(1), 1), 20)
  // The same 12/20/2 style units on a 1.5x output, snapped to device pixels.
  assert.equal(G.taskbarLength(space(1), 1.5, false), 12)
  assert.equal(G.taskbarLength(space(1), 1.5, true), 20)
  assert.equal(G.taskbarThickness(space(1), 1.5), 2)
  // A theme too compact to draw a whole pixel keeps the hairline floor.
  assert.equal(G.taskbarThickness(() => 1, 1), 2)
})

test("spacing and the overflow pill", () => {
  assert.equal(G.rowSpacing(space(1), 1, false), 3)
  assert.equal(G.rowSpacing(space(1), 1, true), 2)
  assert.equal(G.rowSpacing(space(1), 2, false), 3)
  assert.equal(G.pillWidth(space(1), 20), 24)
  assert.equal(G.pillHeight(space(1)), 5)
})

test("a plate reserves exactly the cell the row draws the column in", () => {
  // The pair that used to disagree: the label sized the column from its own copy
  // of the number. A side column draws the full dot and its upright bar as thick,
  // so the reserved room is one cell at every scale and density. The compact end of
  // the range matters: below a spacing scale of about 0.4 Style.space floors a
  // 4 px mark at 1 px while the hairline floor keeps the mark at 2 px, which is
  // where the reserved room and the mark came apart.
  for (const scale of [0.2, 0.3, 0.375, 0.5, 1, 1.25, 1.5, 3]) {
    for (const dpr of [1, 1.25, 1.5, 2, 3]) {
      for (const dense of [false, true]) {
        const col = plain(G.column(space(scale), dpr))
        assert.equal(col.width, G.cell(space(scale), dpr, dense, true),
          `column width vs the row's cell at scale ${scale}, dpr ${dpr}, dense ${dense}`)
      }
    }
  }
  // ...and it is the room plus the plate's own padding that a label measures.
  assert.deepEqual(plain(G.column(space(1), 1)), { edge: 1, width: 5, gap: 5 })
})

test("a mark is never bigger than the cell reserved for it", () => {
  // The hairline floor has one owner and every drawn mark applies it, so the
  // cell - which is the widest of those marks - follows the floor too. It used
  // to be built from Style.space alone: at a compact scale (0.3 here) Style.space
  // floors a 4 px mark at 1 px while the mark stayed 2 px, leaving the row's cell
  // and a plate's column half a pixel narrower than the mark they centre.
  const dense = space(0.3)
  assert.equal(G.dot(dense, 1, true, true), 2)
  assert.equal(G.barThickness(dense, 1), 2)
  assert.equal(G.cell(dense, 1, true, true), 2)      // 1 before the floor had one owner
  assert.equal(G.cell(dense, 1, false, true), 2)
  assert.equal(plain(G.column(dense, 1)).width, 2)   // the plate's room holds the mark
  // At 2x the same compact theme the hairline is a whole pixel, so the floor no
  // longer binds: the column's full dot is 2 px, the bar 1.
  assert.equal(G.cell(dense, 2, true, true), 2)
  for (const scale of [0.2, 0.3, 0.375, 0.5, 1, 1.25, 1.5, 3]) {
    for (const dpr of [1, 1.25, 1.5, 2, 3]) {
      for (const dense of [false, true]) {
        for (const vertical of [false, true]) {
          assert.ok(G.cell(space(scale), dpr, dense, vertical) >= G.dot(space(scale), dpr, dense, vertical),
            `cell vs dot at scale ${scale}, dpr ${dpr}, dense ${dense}, vertical ${vertical}`)
          assert.ok(G.cell(space(scale), dpr, dense, vertical) >= G.barThickness(space(scale), dpr),
            `cell vs bar at scale ${scale}, dpr ${dpr}, dense ${dense}, vertical ${vertical}`)
        }
      }
    }
  }
  // ...and the floor rule the cell derives from has one owner.
  assert.equal(G.hairline(1), 2)
  assert.equal(G.hairline(2), 1)
})
