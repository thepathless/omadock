// Folder stack header count and footer for folders the scan could not
// list in full (more than list-folder.py's MAX_SCAN entries).
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMODEL || new URL("../../DockModel.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), M)

test("stackCountLabel: plain count, capped count, nothing for empty", () => {
  assert.equal(M.stackCountLabel(31, false), "31")
  assert.equal(M.stackCountLabel(20000, true), "20000+")
  assert.equal(M.stackCountLabel(0, false), "")
})

test("stackMoreLabel: entries left over", () => {
  assert.equal(M.stackMoreLabel(310, 300, false), "+ 10 more")
  assert.equal(M.stackMoreLabel(300, 300, false), "")
})

test("stackMoreLabel: a capped scan says there are at least that many", () => {
  assert.equal(M.stackMoreLabel(20000, 300, true), "+ 19700+ more")
})
