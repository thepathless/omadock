// DockIconTheme.js: the installed-theme list the shell helper prints, the
// lookup chain, and the id rule the apply path depends on.
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
  "MixedCase|Mixed Case|",
  "bad id|Nope|",
  "Tëma|Non ASCII|",
  "日本|CJK|",
  "../etc|Escape|",
  ""
].join("\n")

test("the list keeps one row per id, sorts by name and drops unsafe ids", () => {
  const themes = T.parseList(LIST)
  assert.deepEqual(plain(themes.map((t) => t.id)), ["Adwaita", "breeze-dark", "MixedCase", "Papirus", "whitesur-icon-theme", "Yaru", "Yaru-blue"])
  assert.equal(themes.find((t) => t.id === "breeze-dark").name, "Breeze Dark")
  assert.deepEqual(plain(themes.find((t) => t.id === "Yaru-blue").inherits), ["Yaru", "hicolor"])
  assert.equal(T.parseList("").length, 0)
  assert.equal(T.parseList(null).length, 0)
})

test("an id is a directory name: nothing else may reach a path or gsettings", () => {
  for (const ok of ["Yaru", "Yaru-yellow", "whitesur-icon-theme", "Papirus", "Adwaita_dark", "a1+", "MixedCase"]) assert.ok(T.safeId(ok), ok)
  for (const bad of ["", " ", "../etc", "a/b", "a b", "'x'", "a;rm -rf /", "$(id)", "a\nb", "-x", "Tëma", "日本"]) assert.ok(!T.safeId(bad), bad)
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

test("a row's subtitle names the id it applies and what it builds on", () => {
  const themes = T.parseList(LIST)
  assert.equal(T.subtitle(themes.find((t) => t.id === "Yaru")), "builds on hicolor")
  assert.equal(T.subtitle(themes.find((t) => t.id === "breeze-dark")), "breeze-dark · builds on breeze, hicolor")
  assert.equal(T.subtitle(themes.find((t) => t.id === "whitesur-icon-theme")), "whitesur-icon-theme · builds on Adwaita, hicolor")
  assert.equal(T.subtitle(null), "")
})
