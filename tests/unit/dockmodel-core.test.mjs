// Behaviour of DockModel.js that the dock relies on (id normalising, app
// matching, grouping, presets). The pin list's own operations live in
// DockPins.js and are covered by pins.test.mjs. DOCKMODEL overrides the file
// under test.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMODEL || new URL("../../DockModel.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), M)
// workspaceShort lives in DockLabels.js now; the assertions are unchanged.
vm.runInContext(readFileSync(new URL("../../DockLabels.js", import.meta.url), "utf8"), M)
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
  // The quiet cases, captured before the move: a nameless workspace has no
  // label, a two-character numeric name is its own label, and anything else
  // falls back to the id (an id that is not a number has nothing to fall back
  // to, so it prints nothing).
  assert.equal(M.workspaceShort(10, ""), "")
  assert.equal(M.workspaceShort(0, "special:scratch"), "")
  assert.equal(M.workspaceShort(3, null), "")
  assert.equal(M.workspaceShort("", "3"), "3")
  assert.equal(M.workspaceShort("2", "12"), "12")
  assert.equal(M.workspaceShort("x", "x"), "")
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

test("isAppMatch keeps distinct apps under one reverse-DNS vendor apart", () => {
  // Issue #76: the vendor token is not the app. Three Storyteller apps share
  // ai.storyteller but are three products, and the old candidate loop matched
  // any shared 4+ character token.
  assert.equal(M.isAppMatch("ai.storyteller.wordcraft", "ai.storyteller.gridcraft"), false)
  assert.equal(M.isAppMatch("ai.storyteller.pdfcraft", "ai.storyteller.wordcraft"), false)
  assert.equal(M.isAppMatch("com.vendor.app1", "com.vendor.app2"), false)
  // A shared app token still means the same product: ghostty-gui is Ghostty's
  // own GUI class, and the notification path relies on this match.
  assert.equal(M.isAppMatch("com.mitchellh.ghostty", "com.mitchellh.ghostty-gui"), true)
  assert.equal(M.isAppMatch("vivaldi-web.whatsapp.com__-Default", "WhatsApp"), true)
  assert.equal(M.isAppMatch("org.mozilla.firefox", "firefox"), true)
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
  assert.ok(!("foo" in look))
  assert.equal(look.shape, "rounded")
  assert.equal(look.iconSize, 0)
  assert.equal(look.cornerRadius, -1)
})

test("every look key has a default, and pickLook fills the missing ones", () => {
  assert.deepEqual(Object.keys(M.DEFAULT_LOOK).sort(), [...M.LOOK_KEYS].sort())
  const look = plain(M.pickLook({ iconStyle: "dots" }))
  assert.equal(look.iconStyle, "dots")
  for (const k of M.LOOK_KEYS) if (k !== "iconStyle") assert.deepEqual(look[k], M.DEFAULT_LOOK[k], k)
})

test("boundPresets validates ids, drops duplicates, caps at six", () => {
  const list = [{ id: "a", name: "A", look: {} }, { id: "a", name: "dup", look: {} }, { id: "bad id", name: "B", look: {} },
    { id: "c", name: "", look: {} }, { id: "d", name: "D", look: [] }]
  for (let i = 0; i < 10; i++) list.push({ id: "p" + i, name: "P" + i, look: {} })
  const out = plain(M.boundPresets(list))
  assert.equal(out.length, 6)
  assert.deepEqual(out.slice(0, 2).map((p) => p.id), ["a", "p0"])
})

test("entryFor ignores the directories of an absolute Icon= path (issue #66)", () => {
  // An AppImage's Icon= is an absolute path; its directory names used to match
  // the web app id's "home" token, so the result depended on row order.
  const photo = { id: "ai.storyteller.photocraft", name: "PhotoCraft", icon: "/home/user/.local/share/applications/icons/photocraft.png" }
  const drive = { id: "Drive", name: "Drive", icon: "drive" }
  const id = "chrome-drive.google.com__drive_home-Default"
  assert.equal(M.entryFor([photo, drive], id).name, "Drive")
  assert.equal(M.entryFor([drive, photo], id).name, "Drive")
})

// JetBrains Toolbox installs: ids carry a per-install uuid, the window class is
// the StartupWMClass, and every IDE shares the "jetbrains" prefix.
const toolboxIdes = [
  { id: "jetbrains-idea-5c7acef6-a7e9-47ec-8218-4d9145293083", name: "IntelliJ IDEA", icon: "jetbrains-idea-5c7acef6-a7e9-47ec-8218-4d9145293083", startupClass: "jetbrains-idea" },
  { id: "jetbrains-goland-4d5a0b99-2743-43ec-a55c-1d69bb3e8554", name: "GoLand", icon: "jetbrains-goland-4d5a0b99-2743-43ec-a55c-1d69bb3e8554", startupClass: "jetbrains-goland" },
  { id: "jetbrains-rustrover-f644acce-031d-4a55-a03b-a88b97a9a51e", name: "RustRover", icon: "jetbrains-rustrover-f644acce-031d-4a55-a03b-a88b97a9a51e", startupClass: "jetbrains-rustrover" },
]

test("entryFor resolves each JetBrains window class to its own IDE, whatever the row order", () => {
  for (const rows of [toolboxIdes, [...toolboxIdes].reverse()]) {
    assert.equal(M.entryFor(rows, "jetbrains-idea").name, "IntelliJ IDEA")
    assert.equal(M.entryFor(rows, "jetbrains-goland").name, "GoLand")
    assert.equal(M.entryFor(rows, "jetbrains-rustrover").name, "RustRover")
  }
})

test("entryFor matches a window class through StartupWMClass", () => {
  // The decoy shares the "thing" token and comes first, so only the declared
  // class can pick the right row.
  const rows = [{ id: "thing-other", name: "Decoy", icon: "a" }, { id: "com.example.App42", name: "Thing", icon: "x", startupClass: "Thing-Main" }]
  assert.equal(M.entryFor(rows, "thing-main").name, "Thing")
})

test("a pinned JetBrains IDE claims only its own windows", () => {
  const [idea, goland, rustrover] = toolboxIdes.map((e) => e.id)
  assert.equal(M.isAppMatch(idea, "jetbrains-idea"), true)
  assert.equal(M.isAppMatch(goland, "jetbrains-goland"), true)
  assert.equal(M.isAppMatch(idea, "jetbrains-goland"), false)
  assert.equal(M.isAppMatch(goland, "jetbrains-rustrover"), false)
  assert.equal(M.isAppMatch(rustrover, "jetbrains-idea"), false)

  const lib = { iconSource: (n) => "file:///" + n, entryName: (e) => e.name }
  const out = plain(M.buildEntries([idea, goland], [{ appId: "jetbrains-goland", title: "GoLand" }], toolboxIdes, lib, () => ({ address: "0x1" })))
  assert.deepEqual(out.pinned.map((e) => [e.name, e.running]), [["IntelliJ IDEA", false], ["GoLand", true]])
  assert.equal(out.pinned[1].icon, "file:///" + toolboxIdes[1].icon)
})

test("lookIncludes compares only the preset's keys", () => {
  assert.equal(M.lookIncludes({ grain: true, iconSize: 48 }, { grain: true }), true)
  assert.equal(M.lookIncludes({ grain: false }, { grain: true }), false)
})
