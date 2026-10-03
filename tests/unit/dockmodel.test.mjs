// Regression tests for DockModel.js. The file is plain JS with no Qt
// globals, so it runs in a vm context; DOCKMODEL overrides the path.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMODEL || new URL("../../DockModel.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), M)
// Values from the vm realm have foreign prototypes; compare plain copies.
const plain = (v) => JSON.parse(JSON.stringify(v))

test("boundAppGroups ignores array-like objects", () => {
  assert.deepEqual(plain(M.boundAppGroups({ length: 1, 0: { id: "g" } })), [])
})

test("boundAppGroups keeps real arrays", () => {
  assert.equal(M.boundAppGroups([{ id: "g", apps: ["a"] }]).length, 1)
})

test("group apps must be a real array", () => {
  const g = M.boundAppGroups([{ id: "g", apps: { length: 1, 0: "a" } }])
  assert.deepEqual(plain(g[0].apps), [])
})

test("boundPinnedFolders ignores array-like objects", () => {
  assert.deepEqual(plain(M.boundPinnedFolders({ length: 1, 0: { path: "/tmp" } })), [])
})

test("parsePinned ignores array-like pinned lists", () => {
  assert.deepEqual(plain(M.parsePinned('{"pinned": {"length": 1, "0": "a"}}')), [])
  assert.deepEqual(plain(M.parsePinned('{"length": 1, "0": "a"}')), [])
})

test("parsePinned keeps real lists, deduped and without .desktop", () => {
  assert.deepEqual(plain(M.parsePinned('{"pinned": ["a.desktop", "b", "a"]}')), ["a", "b"])
  assert.deepEqual(plain(M.parsePinned('["x"]')), ["x"])
})

test("a huge claimed length returns at once", () => {
  const t0 = performance.now()
  M.boundAppGroups({ length: 1e7 })
  M.parsePinned('{"pinned": {"length": 10000000}}')
  assert.ok(performance.now() - t0 < 50, `took ${performance.now() - t0} ms`)
})

test("configBase: empty text starts from an empty object", () => {
  assert.deepEqual(plain(M.configBase("")), {})
  assert.deepEqual(plain(M.configBase("   \n")), {})
})

test("configBase: a JSON object is kept", () => {
  assert.deepEqual(plain(M.configBase('{"a": 1, "b": [2]}')), { a: 1, b: [2] })
})

test("configBase: anything else means do not write", () => {
  for (const t of ["garbage{", "[]", "[1]", '"str"', "null", "42", "true"])
    assert.equal(M.configBase(t), null, t)
})

test("boundSystemBlurSize clamps to 0..100", () => {
  assert.equal(M.boundSystemBlurSize(8), 8)
  assert.equal(M.boundSystemBlurSize(7.6), 8)
  assert.equal(M.boundSystemBlurSize(1e12), 100)
  assert.equal(M.boundSystemBlurSize(Infinity), 0)
  assert.equal(M.boundSystemBlurSize(-3), 0)
  assert.equal(M.boundSystemBlurSize("9"), 0)
})

test("cleanSoundName accepts theme sound ids and none", () => {
  assert.equal(M.cleanSoundName("message-new-instant"), "message-new-instant")
  assert.equal(M.cleanSoundName("none"), "none")
})

test("cleanSoundName rejects paths and junk", () => {
  for (const v of ["../../x", "/usr/share/a.oga", "Bell", "", "a".repeat(49), 5, null])
    assert.equal(M.cleanSoundName(v), "bell", String(v))
})

test("pinned folders must be absolute or home-relative", () => {
  const out = plain(M.boundPinnedFolders([
    { path: "/srv/a" }, { path: "~/b" }, { path: "~" }, { path: "-x" }, { path: "rel/c" }, { path: 5 },
  ]))
  assert.deepEqual(out.map((f) => f.path), ["/srv/a", "~/b", "~"])
})

test("localPathsFromUrls decodes file URLs", () => {
  assert.deepEqual(plain(M.localPathsFromUrls(["file:///home/u/a%20b", "https://x/y"])), ["/home/u/a b"])
})

test("localPathsFromUrls drops paths with line breaks", () => {
  assert.deepEqual(plain(M.localPathsFromUrls(["file:///tmp/a%0A/etc", "file:///tmp/b%0D"])), [])
})

test("localPathsFromUrls skips malformed escapes and relative paths", () => {
  assert.deepEqual(plain(M.localPathsFromUrls(["file:///bad%E0%A4%A", "file://host/x"])), [])
})

// ------------------------------------------------- settings fuzzy search
test("searchSettings: 'pixl' finds the pixel icon style", () => {
  const hits = M.searchSettings("pixl")
  assert.ok(hits.length > 0)
  assert.equal(hits[0].key, "iconStyle")
})

test("searchSettings: 'shad' finds the shadow toggle", () => {
  const hits = M.searchSettings("shad")
  assert.ok(hits.length > 0)
  assert.equal(hits[0].key, "showShadow")
})

test("searchSettings: partial words reach notification badges", () => {
  const keys = M.searchSettings("not").map((h) => h.key)
  assert.ok(keys.includes("badges"))
})

test("searchSettings: exact label outranks a synonym", () => {
  const hits = M.searchSettings("opacity")
  assert.equal(hits[0].key, "opacity")
})

test("searchSettings: every hit names a page for the jump", () => {
  for (const hit of M.searchSettings("icon"))
    assert.ok(["appearance", "icons", "motion", "behavior", "placement", "folders", "groups", "presets", "about"].includes(hit.page))
})

test("searchSettings: garbage queries return nothing", () => {
  assert.deepEqual(plain(M.searchSettings("zzqxwv")), [])
})

test("fuzzyScore: order matters and gaps are allowed", () => {
  assert.ok(M.fuzzyScore("pixl", "pixel") > 0)
  assert.equal(M.fuzzyScore("xelpi", "pixel"), -1)
  assert.ok(M.fuzzyScore("", "pixel"), -1)
})

test("every search key registers exactly one row in SettingsPanel.qml", () => {
  const src = readFileSync(new URL("../../components/SettingsPanel.qml", import.meta.url), "utf8")
  for (const e of M.SETTINGS_SEARCH) {
    const n = src.split(`key: "${e.key}"`).length - 1
    assert.equal(n, 1, `expected exactly one row for search key ${e.key}, found ${n}`)
  }
})

test("SettingsPanel.qml keeps no retired page ids", () => {
  const src = readFileSync(new URL("../../components/SettingsPanel.qml", import.meta.url), "utf8")
  assert.ok(!src.includes('panel.page === "effects"'))
  assert.ok(!src.includes('panel.page === "size"'))
})
