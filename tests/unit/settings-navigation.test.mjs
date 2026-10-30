import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync, readdirSync } from "node:fs"
import vm from "node:vm"
const root = new URL("../../", import.meta.url)
const S = vm.createContext({})
vm.runInContext(readFileSync(new URL("SettingsSearch.js", root), "utf8"), S)
const plain = (v) => JSON.parse(JSON.stringify(v))
const pages = ["presets", "appearance", "placement", "behavior", "folders", "about"]

test("all old category entry points remain useful and all search hits use six destinations", () => {
  for (const old of ["labels", "icons", "motion"]) assert.equal(S.category(old), "appearance")
  assert.equal(S.category("groups"), "folders")
  assert.equal(S.category("supporters"), "about")
  assert.equal(S.category("unknown"), "presets")
  for (const p of pages) assert.equal(S.category(p), p)
  for (const e of S.SETTINGS_SEARCH) {
    assert.ok(pages.includes(S.entryFor(e.key).page), e.key)
    assert.equal(S.searchSettings(e.label, [e])[0].page, S.entryFor(e.key).page)
  }
  assert.equal(S.entryFor("autohide").page, "placement")
  assert.equal(S.entryFor("appsButton").page, "folders")
  assert.equal(S.entryFor("missing"), null)
})

const state = () => ({ showBackground: true, bgFill: "solid", dockOpacity: -1,
  showBorder: false, borderOpacity: -1, placement: { split: false, panel: false },
  dividerStyle: "simple", dividerGeometry: "classic", dockShape: "theme",
  sharedState: { appGrid: { available: true } }, showAppsButton: true,
  iconStyle: "original", iconHoverOriginal: false, showShadow: false,
  blurMode: "system", autohide: false, floatingWatch: { available: false },
  showNotificationBadges: false, showTooltips: false, multiMonitor: false,
  labelMode: "off", labelFont: "theme", labelKind: "all", labelBackground: "none" })

test("every conditional target explains its first prerequisite without changing values", () => {
  const r = state(), before = JSON.stringify(r)
  const pairs = { gradientPalette: "bgFill", opacity: "opacityTheme", borderWidth: "border",
    borderOpacity: "border", dividerWidth: "dividerStyle", dividerHeight: "dividerLength",
    cornerRadius: "corners", panelSpacing: "splitSections", iconTint: "iconStyle",
    iconGrid: "iconStyle", iconHoverOriginal: "iconStyle", iconHoverReveal: "iconStyle",
    shadowStrength: "showShadow", blur: "blurSystem", blurSize: "blurSystem",
    revealDelay: "autohide", floatingDock: "", badgeStyle: "badges", badgePosition: "badges",
    badgeColor: "badges", tooltipDelay: "tooltips", windowPreviews: "tooltips",
    perMonitorApps: "multiMonitor", labelFont: "labelMode", labelPlateHeight: "labelMode" }
  for (const [key, prerequisite] of Object.entries(pairs)) {
    const d = S.dependency(key, r)
    assert.ok(d && d.text.length > 10, key)
    assert.equal(d.key, prerequisite, key)
    if (d.key) assert.ok(S.entryFor(d.key), `${key} prerequisite is navigable`)
  }
  assert.equal(JSON.stringify(r), before, "search dependencies are read-only")
  assert.equal(S.dependency("iconSize", r), null)
  assert.equal(S.dependency("blurSize", null), null)
})

test("nested prerequisites advance only after explicit settings changes", () => {
  const r = state()
  r.showBackground = false
  assert.equal(S.dependency("blurSize", r).key, "showBackground")
  r.showBackground = true
  assert.equal(S.dependency("blurSize", r).key, "blurSystem")
  r.blurMode = "off"
  assert.equal(S.dependency("blurSize", r).key, "blur")
  r.blurMode = "on"
  assert.equal(S.dependency("blurSize", r), null)
  r.labelMode = "hover"
  assert.equal(S.dependency("labelPlateHeight", r).key, "labelMode")
  r.labelMode = "always"
  assert.equal(S.dependency("labelPlateHeight", r).key, "labelBackground")
  r.labelBackground = "plate"
  assert.equal(S.dependency("labelPlateHeight", r), null)
})

test("category declarations and every searchable row remain singular", () => {
  const panel = readFileSync(new URL("components/SettingsPanel.qml", root), "utf8")
  assert.deepEqual([...panel.matchAll(/\{ id: "([^"]+)", label: /g)].map((m) => m[1]), pages)
  const sources = readdirSync(new URL("components/settings/", root)).filter((f) => f.endsWith(".qml"))
    .map((f) => readFileSync(new URL(`components/settings/${f}`, root), "utf8")).join("\n")
  for (const e of S.SETTINGS_SEARCH) assert.equal(sources.split(`key: "${e.key}"`).length - 1, 1, e.key)
  assert.equal(S.SETTINGS_SEARCH.length, 88, "the existing searchable options are preserved, plus the icon theme")
  assert.ok(!readFileSync(new URL("components/settings/ChoiceRow.qml", root), "utf8").includes("focusable: false"))
  assert.ok(panel.includes("p.expanded = true"), "search opens advanced ancestors")
})
