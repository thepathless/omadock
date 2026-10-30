// Tests for DockLayout.js, the pure helpers behind the Dock / Panel layouts
// and the alignments. Plain JS with no Qt globals, run in a vm context.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKLAYOUT || new URL("../../DockLayout.js", import.meta.url)
const L = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), L)
const plain = (v) => JSON.parse(JSON.stringify(v))

test("normalizeLayout keeps panel, everything else is dock", () => {
  assert.equal(L.normalizeLayout("panel"), "panel")
  assert.equal(L.normalizeLayout("PANEL"), "panel")
  assert.equal(L.normalizeLayout("dock"), "dock")
  for (const v of ["", null, undefined, "taskbar", 3, {}]) assert.equal(L.normalizeLayout(v), "dock")
})

test("normalizeAlignment accepts the five values, else center", () => {
  for (const v of ["left", "right", "spread", "taskbar", "center"]) assert.equal(L.normalizeAlignment(v), v)
  assert.equal(L.normalizeAlignment("Right"), "right")
  for (const v of ["", null, undefined, "both", "top", 7]) assert.equal(L.normalizeAlignment(v), "center")
})

test("placement: panel ignores split", () => {
  assert.deepEqual(plain(L.placement("panel", "left", true, true)), { panel: true, split: false, align: "left", taskbar: false })
  assert.deepEqual(plain(L.placement("dock", "left", true, true)), { panel: false, split: true, align: "left", taskbar: false })
})

test("placement: taskbar needs the panel, then draws Start, apps and tray", () => {
  assert.deepEqual(plain(L.placement("panel", "taskbar", true, true)),
    { panel: true, split: false, align: "taskbar", taskbar: true })
  // A floating dock has no room for three zones: it centres instead.
  assert.equal(L.placement("dock", "taskbar", true, true).align, "center")
  assert.equal(L.placement("dock", "taskbar", true, true).taskbar, false)
})

test("taskbar geometry: the app section centres between Start and the tray", () => {
  // 10 apps of 44px with 4px gaps, a 44px Start button, a 98px clock.
  const apps = L.taskbarAppWidth(44, 10, 0, 0, 0, 0, 4)
  assert.equal(apps, 476)
  // Apps start at 44 + 4 + 670 + 4 = 722, centre 960.
  assert.equal(L.taskbarStartGap(1920, apps, 44, 524, 98, 4, true), 670)
  // Without Start, the gap alone puts them at 718 + 4, still centred.
  assert.equal(L.taskbarStartGap(1920, apps, 0, 476, 98, 4, false), 718)
  // A packed bar leaves no free room to open.
  assert.equal(L.taskbarStartGap(600, apps, 44, 590, 98, 4, true), 0)
  // A hidden divider is a negative slot, counted as Dock.baseRowWidth counts it.
  assert.equal(L.taskbarAppWidth(40, 3, 0, 0, 1, -4, 4), 128)
  assert.equal(L.TASKBAR_CLOCK_WIDTH, 74)
})

test("placement: spread needs panel or split, and a right group", () => {
  assert.equal(L.placement("dock", "spread", false, true).align, "center")
  assert.equal(L.placement("dock", "spread", true, true).align, "spread")
  assert.equal(L.placement("panel", "spread", false, true).align, "spread")
  assert.equal(L.placement("panel", "spread", false, false).align, "left")
  assert.equal(L.placement("dock", "spread", true, false).align, "left")
  assert.equal(L.placement("bogus", "bogus", "yes", true).align, "center")
  assert.equal(L.placement("bogus", "bogus", "yes", true).split, false)
})

test("spreadAvailable", () => {
  assert.equal(L.spreadAvailable("panel", false), true)
  assert.equal(L.spreadAvailable("dock", true), true)
  assert.equal(L.spreadAvailable("dock", false), false)
})

test("stretchedBox: panel spans the window, dock spread keeps the inset", () => {
  assert.deepEqual(plain(L.stretchedBox({ panel: true, split: false, align: "center" }, 5120, 20)), { x: 0, width: 5120 })
  assert.deepEqual(plain(L.stretchedBox({ panel: false, split: true, align: "spread" }, 5120, 20)), { x: 20, width: 5080 })
  assert.equal(L.stretchedBox({ panel: false, split: false, align: "center" }, 5120, 20), null)
  assert.equal(L.stretchedBox({ panel: false, split: true, align: "left" }, 5120, 20), null)
  assert.deepEqual(plain(L.stretchedBox({ panel: false, split: true, align: "spread" }, 10, 20)), { x: 20, width: 0 })
})

test("rowOffset per alignment, clamped at 0 on overflow", () => {
  assert.equal(L.rowOffset("left", 1000, 400), 0)
  assert.equal(L.rowOffset("right", 1000, 400), 600)
  assert.equal(L.rowOffset("center", 1000, 401), 300)
  assert.equal(L.rowOffset("spread", 1000, 400), 0)
  assert.equal(L.rowOffset("right", 300, 400), 0)
  assert.equal(L.rowOffset("center", 300, 400), 0)
})

test("spreadGap fills what is left between the groups, never below one pixel", () => {
  // The gap item starts at x 300 (the row spacing after the left group is
  // already in that x); one more spacing separates it from the right group.
  assert.equal(L.spreadGap(1000, 300, 200, 4), 496)
  // Used up: one logical pixel, or one device pixel given a scale, so the
  // Row keeps the gap item and the spacing after it.
  assert.equal(L.spreadGap(400, 300, 200, 4), 1)
  assert.equal(L.spreadGap(400, 300, 200, 4, 1.5), 1 / 1.5)
  assert.equal(L.spreadGap(400, 300, 200, 4, 2), 0.5)
})

test("spreadGap: the right group never jumps back as the gap is used up", () => {
  // The left group growing under magnification pushes gapX right; where the
  // right group starts (gap + the spacing after it) must keep moving the same
  // way, without the drop of one spacing a zero-width gap item would cause
  // (a Row skips it and the spacing after it). Snapping the gap to device
  // pixels may step back by less than one of them.
  for (const dpr of [0, 1.5]) {
    const px = dpr > 0 ? 1 / dpr : 1
    let last = -Infinity
    for (let gapX = 280; gapX <= 320; gapX += 0.25) {
      const gap = L.spreadGap(500, gapX, 200, 6, dpr)
      const start = gap > 0 ? gapX + gap + 6 : gapX
      assert.ok(start > last - px, `dpr ${dpr} gapX ${gapX}: ${start} after ${last}`)
      last = start
    }
  }
})

test("spreadGap puts the right group's end on the inner edge", () => {
  for (const [inner, gapX, right, spacing] of [[1000, 300, 200, 4], [5108, 1210.5, 640, 6], [2000, 4, 300, 12]]) {
    const gap = L.spreadGap(inner, gapX, right, spacing)
    assert.equal(gapX + gap + spacing + right, inner, `${inner} ${gapX} ${right} ${spacing}`)
  }
})

test("spreadHomeShift moves resting right-group centres by the free width", () => {
  assert.equal(L.spreadHomeShift(1000, 600), 400)
  assert.equal(L.spreadHomeShift(500, 600), 0)
})

test("rowOffset and spreadGap land on whole device pixels when given a scale", () => {
  const whole = (v, d) => Math.abs(v * d - Math.round(v * d)) < 1e-9
  for (const align of ["center", "right"])
    for (const row of [401, 402, 433.3]) assert.ok(whole(L.rowOffset(align, 1000, row, 1.5), 1.5), `${align} ${row}`)
  assert.ok(whole(L.spreadGap(1000, 300.4, 200, 2.67, 1.5), 1.5))
  assert.equal(L.rowOffset("center", 1000, 401), 300)
})
