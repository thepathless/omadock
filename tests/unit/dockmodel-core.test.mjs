// Behaviour of DockModel.js that the dock relies on (pinning, grouping,
// app matching, presets). DOCKMODEL overrides the file under test.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMODEL || new URL("../../DockModel.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), M)
const plain = (v) => JSON.parse(JSON.stringify(v))

test("stripDesktop", () => {
  assert.equal(M.stripDesktop("firefox.desktop"), "firefox")
  assert.equal(M.stripDesktop({ appId: "x.DESKTOP" }), "x")
  assert.equal(M.stripDesktop(null), "")
})

test("workspaceShort", () => {
  assert.equal(M.workspaceShort(3, "3"), "3")
  assert.equal(M.workspaceShort(-98, "special:magic"), "")
  assert.equal(M.workspaceShort(5, "mail"), "5")
  assert.equal(M.workspaceShort(-1, "7"), "7")
})

test("getCandidates drops vendor tokens", () => {
  const c = plain(M.getCandidates("org.mozilla.firefox"))
  assert.ok(c.includes("firefox"))
  assert.ok(!c.includes("org") && !c.includes("mozilla"))
})

test("isAppMatch", () => {
  assert.equal(M.isAppMatch("firefox", "org.mozilla.firefox"), true)
  assert.equal(M.isAppMatch("Alacritty.desktop", "alacritty"), true)
  assert.equal(M.isAppMatch("zen", "zen-browser"), true)
  assert.equal(M.isAppMatch("vlc", "foot"), false)
  assert.equal(M.isAppMatch("", "foot"), false)
})

test("extractNotificationWebDomain", () => {
  assert.equal(M.extractNotificationWebDomain('<a href="https://web.whatsapp.com/">x</a>', ""), "web.whatsapp.com")
  assert.equal(M.extractNotificationWebDomain("", "Visit https://Music.YouTube.com/watch"), "music.youtube.com")
  assert.equal(M.extractNotificationWebDomain("hello", ""), "")
})

test("serializePinned and parsePinned round-trip", () => {
  const text = M.serializePinned(["a.desktop", "b", "a"])
  assert.deepEqual(JSON.parse(text), { pinned: ["a", "b"] })
  assert.deepEqual(plain(M.parsePinned(text)), ["a", "b"])
})

test("togglePinned", () => {
  assert.deepEqual(plain(M.togglePinned(["a", "b"], "a.desktop")), ["b"])
  assert.deepEqual(plain(M.togglePinned(["a"], "c")), ["a", "c"])
  assert.deepEqual(plain(M.togglePinned(["a"], "")), ["a"])
})

test("reorderPinned", () => {
  assert.deepEqual(plain(M.reorderPinned(["a", "b", "c"], "c", "a")), ["c", "a", "b"])
  assert.deepEqual(plain(M.reorderPinned(["a", "b", "c"], "a", null)), ["b", "c", "a"])
  assert.deepEqual(plain(M.reorderPinned(["a", "b", "c"], "b", "b")), ["a", "b", "c"])
  assert.deepEqual(plain(M.reorderPinned(["a", "b"], "a", "zz")), ["b", "a"])
})

test("moveBefore", () => {
  const list = [1, 2, 3]
  assert.deepEqual(plain(M.moveBefore(list, 0, 3)), [2, 3, 1])
  assert.deepEqual(plain(M.moveBefore(list, 2, 0)), [3, 1, 2])
  assert.equal(M.moveBefore(list, 1, 1), list)
  assert.equal(M.moveBefore(list, 1, 2), list)
  assert.equal(M.moveBefore(list, 5, 0), list)
})

const entries = [{ appId: "a" }, { appId: "b" }]
const groups = [{ id: "g", before: "b", apps: ["a", "c"] }, { id: "h", before: "zz", apps: [] }]

test("pinnedRow places groups before their app, orphans at the end", () => {
  const row = plain(M.pinnedRow(entries, groups))
  assert.deepEqual(row.map((r) => r.kind + ":" + (r.appId || r.id)), ["app:a", "group:g", "app:b", "group:h"])
})

test("rowState turns a row back into pins and anchored groups", () => {
  const st = plain(M.rowState(M.pinnedRow(entries, groups), ["a", "b", "x"]))
  assert.deepEqual(st.pins, ["a", "b", "x"])
  assert.deepEqual(st.groups.map((g) => [g.id, g.before]), [["g", "b"], ["h", ""]])
})

test("ungroupRow puts the group's unshown apps in its place", () => {
  const row = plain(M.ungroupRow(M.pinnedRow(entries, groups), "g"))
  assert.deepEqual(row.map((r) => r.kind + ":" + (r.appId || r.id)), ["app:a", "app:c", "app:b", "group:h"])
})

test("reanchorGroups moves a group past an unpinned anchor", () => {
  const g = [{ id: "g", before: "b" }]
  assert.deepEqual(plain(M.reanchorGroups(g, ["a", "b", "c"], ["a", "c"]))[0].before, "c")
  assert.equal(M.reanchorGroups(g, ["a", "b"], ["a", "b"]), g)
})

test("boundAppGroups defaults and clamps", () => {
  const out = plain(M.boundAppGroups([{ id: "g", cols: 99 }, { id: "h", cols: -5 }, { id: "i" }, { name: "no id" }]))
  assert.deepEqual(out.map((g) => g.cols), [6, 1, 3])
  assert.equal(out[2].name, "Group")
  assert.equal(out[2].icon, "folder")
})

test("boundPinnedFolders whitelists sort and view, caps the count", () => {
  const many = Array.from({ length: 20 }, (_, i) => ({ path: "/f" + i, sort: i ? "bogus" : "name", view: i ? "list" : "grid" }))
  const out = plain(M.boundPinnedFolders(many))
  assert.equal(out.length, 12)
  assert.deepEqual([out[0].sort, out[0].view, out[1].sort, out[1].view], ["name", "grid", "modified", "stack"])
})

test("readCapped counts bytes, not characters", () => {
  assert.equal(M.readCapped("abc", 3), "abc")
  assert.equal(M.readCapped("ąć", 3), "")
  assert.equal(M.readCapped("abcd", 3), "")
})

test("cleanPresetName strips bidi/control characters and caps length", () => {
  assert.equal(M.cleanPresetName("  a\u202eb\u0007  "), "ab")
  assert.equal(M.cleanPresetName("x".repeat(100)).length, 40)
})

test("pickLook keeps look keys only, scalars, capped strings", () => {
  const look = plain(M.pickLook({ bgColor: "x".repeat(100), foo: 1, iconSize: Infinity, shape: { a: 1 } }))
  assert.equal(look.bgColor.length, 64)
  assert.ok(!("foo" in look) && !("shape" in look))
  assert.equal(look.iconSize, 0)
  assert.equal(look.cornerRadius, -1)
})

test("boundPresets validates ids, drops duplicates, caps at six", () => {
  const list = [{ id: "a", name: "A", look: {} }, { id: "a", name: "dup", look: {} }, { id: "bad id", name: "B", look: {} },
    { id: "c", name: "", look: {} }, { id: "d", name: "D", look: [] }]
  for (let i = 0; i < 10; i++) list.push({ id: "p" + i, name: "P" + i, look: {} })
  const out = plain(M.boundPresets(list))
  assert.equal(out.length, 6)
  assert.deepEqual(out.slice(0, 2).map((p) => p.id), ["a", "p0"])
})

test("lookIncludes compares only the preset's keys", () => {
  assert.equal(M.lookIncludes({ grain: true, iconSize: 48 }, { grain: true }), true)
  assert.equal(M.lookIncludes({ grain: false }, { grain: true }), false)
})
