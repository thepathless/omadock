// DockIconTheme.js: the installed-theme list the shell helper prints, the
// lookup chain, search, and the id rule the apply path depends on.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const root = new URL("../../", import.meta.url)
const plain = (v) => JSON.parse(JSON.stringify(v))
const T = vm.createContext({})
vm.runInContext(readFileSync(new URL("DockIconTheme.js", root), "utf8"), T)

const LIST = [
  "Adwaita|Adwaita|AdwaitaLegacy,hicolor",
  "Yaru-blue|Yaru-blue|Yaru,hicolor",
  "Yaru|Yaru|hicolor",
  "breeze-dark|Breeze Dark|breeze,hicolor",
  "whitesur-icon-theme|WhiteSur|Adwaita,hicolor",
  "Papirus|Papirus|hicolor",
  "Yaru-blue|Yaru-blue|Yaru,hicolor",
  "bad id|Nope|",
  "../etc|Escape|",
  ""
].join("\n")

test("the list keeps one row per id, sorts by name and drops unsafe ids", () => {
  const themes = T.parseList(LIST)
  assert.deepEqual(plain(themes.map((t) => t.id)), ["Adwaita", "breeze-dark", "Papirus", "whitesur-icon-theme", "Yaru", "Yaru-blue"])
  assert.equal(themes.find((t) => t.id === "breeze-dark").name, "Breeze Dark")
  assert.deepEqual(plain(themes.find((t) => t.id === "Yaru-blue").inherits), ["Yaru", "hicolor"])
  assert.equal(T.parseList("").length, 0)
  assert.equal(T.parseList(null).length, 0)
})

test("an id is a directory name: nothing else may reach a path or gsettings", () => {
  for (const ok of ["Yaru", "Yaru-yellow", "whitesur-icon-theme", "Papirus", "Adwaita_dark", "a1+"]) assert.ok(T.safeId(ok), ok)
  for (const bad of ["", " ", "../etc", "a/b", "a b", "'x'", "a;rm -rf /", "$(id)", "a\nb", "-x"]) assert.ok(!T.safeId(bad), bad)
})

test("the chain follows Inherits and stops on a cycle or a missing theme", () => {
  const themes = T.parseList(LIST)
  assert.deepEqual(plain(T.chain("Yaru-blue", themes)), ["Yaru-blue", "Yaru", "hicolor"])
  assert.deepEqual(plain(T.chain("whitesur-icon-theme", themes)), ["whitesur-icon-theme", "Adwaita", "hicolor", "AdwaitaLegacy"])
  // No list yet (first start): the active theme is still scanned first.
  assert.deepEqual(plain(T.chain("Papirus", [])), ["Papirus"])
  const cyc = T.parseList("a|A|b\nb|B|a")
  assert.deepEqual(plain(T.chain("a", cyc)), ["a", "b"])
  assert.deepEqual(plain(T.chain("missing", themes)), ["missing"])
})

test("search matches the name or the id and never reorders the empty query", () => {
  const themes = T.parseList(LIST)
  assert.deepEqual(plain(T.filter(themes, "whitesur").map((t) => t.id)), ["whitesur-icon-theme"])
  assert.deepEqual(plain(T.filter(themes, "WHITE").map((t) => t.id)), ["whitesur-icon-theme"])
  assert.deepEqual(plain(T.filter(themes, "dark").map((t) => t.id)), ["breeze-dark"])
  assert.deepEqual(plain(T.filter(themes, "  ").map((t) => t.id)), plain(themes.map((t) => t.id)))
  assert.equal(T.filter(themes, "zzz").length, 0)
})

test("a row's subtitle names the id it applies and what it builds on", () => {
  const themes = T.parseList(LIST)
  assert.equal(T.subtitle(themes.find((t) => t.id === "Yaru")), "builds on hicolor")
  assert.equal(T.subtitle(themes.find((t) => t.id === "breeze-dark")), "breeze-dark · builds on breeze, hicolor")
  assert.equal(T.subtitle(themes.find((t) => t.id === "whitesur-icon-theme")), "whitesur-icon-theme · builds on Adwaita, hicolor")
  assert.equal(T.subtitle(null), "")
})
