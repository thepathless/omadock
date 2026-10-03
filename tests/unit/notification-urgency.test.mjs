// Urgency from notification popups when the shell's notification service is
// not available to the dock (overlay plugins): DockModel.newPopupRows.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMODEL || new URL("../../DockModel.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), M)
const plain = (v) => JSON.parse(JSON.stringify(v))

const row = (app, timestamp) => ({ app, appIcon: "", summary: "s", body: "b", timestamp })

test("newPopupRows: popups not in the previous snapshot are new", () => {
  const prev = [row("A", 1)]
  const next = [row("A", 1), row("B", 2)]
  assert.deepEqual(plain(M.newPopupRows(prev, next)).map((r) => r.app), ["B"])
})

test("newPopupRows: a replaced popup with a new timestamp is new", () => {
  assert.deepEqual(plain(M.newPopupRows([row("A", 1)], [row("A", 5)])).map((r) => r.timestamp), [5])
})

test("newPopupRows: rows without a timestamp cannot be told apart and are skipped", () => {
  assert.deepEqual(plain(M.newPopupRows([], [row("A", 0), row("B", undefined)])), [])
})

test("newPopupRows: junk input", () => {
  assert.deepEqual(plain(M.newPopupRows(null, null)), [])
  assert.deepEqual(plain(M.newPopupRows({ length: 5 }, [row("A", 3)])).map((r) => r.app), ["A"])
})
