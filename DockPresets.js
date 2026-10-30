// The looks OmaDock offers out of the box, beside the presets a user saves.
//
// A shipped preset is a preset as DockModel keeps one -- an id, a name and a
// look -- except that its look lists only the keys that differ from
// DockModel.DEFAULT_LOOK: merge() fills the rest from DEFAULT_LOOK through the
// caller's fill (DockModel.pickLook), so a look key added after this file was
// written gets its default instead of leaking whatever the dock happens to
// hold (the rule PR #48 pinned for saved presets).
//
// Shipping them here, not in the config, is what makes them survive: a fresh
// install has no omadock.json, and merge([], ...) still returns every entry
// below. They are read-only -- DockConfigLogic refuses to rename, update or
// delete one -- so the list a user edits is always the list they saved.
// merge() is also the one place a name is settled: a saved preset that holds a
// shipped look's name is listed instead of it, never beside it.
//
// Every look below is built from options this repository's pull requests
// contributed, and from what their authors said they look like:
//
//   thepathless:ristretto  the owner's own look on the maintainer's desktop
//                          (dot-matrix icons, forest gradient, grain, long
//                          custom dividers, glitch hover, no rim or shadow)
//   macOS                  the modern macOS dock: 53px artwork, floating
//                          rounded squircle shelf (27px radius) with frosted
//                          white glass (#ffffff, blur on, 0.5px specular rim,
//                          soft shadow), wave fisheye hover magnification,
//                          hairline dividers, and OmaDock's signature
//                          multi-window indicator dots (flat bar for focused)
//   Windows                the Windows 11 taskbar: the full-width bottom
//                          panel, always visible, Start at the far left, the
//                          app icons centred and the clock/date on the right,
//                          with 24px artwork, no labels, a rounded hover wash
//                          and a thin running pill per app (wider and accent
//                          while focused), plus the window previews its
//                          tooltips already carry
//
// A shipped look may also carry a `setup` (layout, alignment, autohide and the
// behavior a look cannot spell), because the taskbar's shape is not a look: a
// look-only preset would leave a floating, auto-hiding dock that looks nothing
// like it. Only shipped entries can carry one -- a saved preset is written back
// through boundPresets, which keeps id/name/look, so applying one never moves
// the dock. `applyPreset` applies the setup before it saves; every other
// shipped look leaves the user's placement alone.
//
// Deliberately not shipped as presets, and why:
//   - panel layout (#49) is not a look key -- `LOOK_KEYS` has no `layout`, so a
//     look cannot hold it; it rides in the preset's `setup` instead.
//   - #13's "Zen / Arc-style gradient" has no matching gradient: `Dock.qml`'s
//     `gradientPresets` are the fixed palette (aurora, sunset, ocean, forest,
//     rose, lavender, ember, citrus, mono) plus the theme.
// The label keys are a look's: `DockModel.LOOK_KEYS` carries all thirteen and
// `DockConfigLogic.applyLook` applies them through `DockLabels.pickLabelLook`,
// so names are exactly as shippable as a gradient is.

var SHIPPED = [
  {
    id: "builtin_thepathless_ristretto",
    name: "thepathless:ristretto",
    look: {
      bgFill: "gradient", gradientPreset: "forest", gradientStrength: 0.25, grain: 0.2,
      dividerGeometry: "long", dividerStyle: "custom",
      iconStyle: "dots", iconGrid: 8, iconContrast: 0.4, iconStrength: 0.45, iconSize: 34,
      hoverEffect: "glitch", opacity: "theme", shape: "theme", showBorder: false, showShadow: false
    }
  },
  {
    id: "builtin_macos",
    name: "macOS",
    look: {
      showBackground: true, bgColor: "#ffffff", bgFill: "solid",
      blur: "on", blurSize: 12,
      showShadow: true, shadowStrength: 0.5,
      showBorder: true, borderWidth: 0.5, borderOpacity: 0.5,
      shape: "rounded", cornerRadius: 27,
      dockPaddingPx: 7, iconBaseline: "center", surfaceGlass: 1, iconMargin: 8.5,
      surfaceLift: 0.53, surfaceDesaturate: 1, surfaceStability: 0.87, folderColor: "theme",
      iconSize: 53, itemSpacing: 0, sectionSpacing: 15,
      iconStyle: "original", iconTint: "text", iconContrast: 0, iconStrength: 1,
      indicatorMode: "windows", indicatorSize: 4, indicatorInset: 4, indicatorShape: "rounded",
      hoverEffect: "wave", magnifyPeak: 1.6, magnifyReach: 3.6, launchBounce: true,
      dividerGeometry: "classic", dividerStyle: "custom", dividerWidth: 1.0, dividerHeight: 50, dividerOpacity: 0.18,
      labelMode: "hover", labelBackground: "pill", labelShape: "pill", labelFont: "theme",
      labelSize: "medium", labelWeight: "medium", labelReveal: "slide", labelColor: "auto"
    }
  },
  {
    id: "builtin_windows",
    name: "Windows",
    // The taskbar's setup, which a look cannot hold: always visible (the
    // taskbar's own default), a full-width panel on the bottom edge with the
    // three zones Windows 11 uses (Start left, apps centred, tray right), and
    // one tile per app - a minimized window is its app's mark, never a second
    // tile in the bar. Clicking the focused app minimizes it, as on Windows.
    setup: { layout: "panel", alignment: "taskbar", autohide: false, intelligentAutohide: false, showMinimizedTiles: false, minimizeMode: "active", showAppsButton: true, showTooltips: true, advancedTooltips: true },
    look: {
      showBackground: true, bgColor: "#202020", bgFill: "solid",
      // Windows 11's acrylic: the desktop blurs through the bar rather than
      // the bar drawing its own frost, so the fill stays a touch translucent.
      blur: "system", blurSize: 0, opacity: 0.9,
      showShadow: false, shadowStrength: 0,
      // A panel's border is drawn on the screen edge, where Windows has none;
      // its separation from a window comes from the fill alone.
      showBorder: false, borderWidth: 1, borderOpacity: 0,
      // A square shape draws its card (and its popups) at 0px; the radius is
      // kept at 0 too, and applyLook keeps a 0 through (a look is compared key
      // for key to mark its row active, so a value the clamp changed would be
      // a preset that can never report active).
      shape: "square", cornerRadius: 0,
      // A slim bar: 4px of card padding around a slot of iconSize + iconMargin
      // (11 style units), which lands on 42px buttons and ~24px artwork at this
      // desktop's UI scale.
      dockPaddingPx: 4, iconBaseline: "center", iconMargin: 11,
      iconSize: 29, itemSpacing: 3, sectionSpacing: 12,
      iconStyle: "original", iconTint: "text", iconContrast: 0, iconStrength: 1,
      // Windows does not magnify the taskbar; its hover feedback is a soft
      // rounded wash plus the thumbnail preview in the tooltip.
      hoverEffect: "highlight", magnifyPeak: 1.0, magnifyReach: 1.0, launchBounce: false,
      // One mark per app, not per window, in Windows 11's own shape: a thin
      // 12px running pill that widens to 20px and takes the accent while the
      // app holds the focus (indicatorSize is the "app" dot's size, unused).
      indicatorMode: "taskbar", indicatorShape: "rounded", indicatorSize: 4, indicatorInset: 4,
      dividerGeometry: "classic", dividerStyle: "none", dividerWidth: 1.0, dividerHeight: 32, dividerOpacity: 0,
      // A taskbar carries no names; the tooltip is the whole label.
      labelMode: "off", labelKind: "all", labelFont: "theme",
      labelSize: "small", labelWeight: "medium", labelReveal: "slide", labelColor: "auto",
      labelBackground: "none", labelShape: "pill",
      folderColor: "theme"
    }
  }
]

// The name a preset is listed under, compared without regard to case or
// surrounding space. Both ends arrive cleaned (DockModel.cleanPresetName, for
// shipped names by this file's own test), so nothing more is needed here.
function nameKey(name) {
  return String(name == null ? "" : name).trim().toLowerCase()
}

// The list the dock shows and applies: the shipped looks first, then the ones
// the user saved. `fillLook` is DockModel.pickLook, which completes each
// shipped look and drops anything a look could not hold.
//
// A name identifies a look, so the list carries it once: when a saved preset
// holds a shipped look's name -- which can only happen for a preset saved
// before that look shipped, since saving refuses a taken name -- the one the
// user saved wins the name and the shipped look of that name steps aside for
// that user alone. The saved one is the winner because it is the entry they
// can rename, update and delete: hiding it instead would spend one of their
// six slots on a row they cannot see, and deleting or rewriting it to settle a
// name would throw away a preset they made. A fresh install, which has no
// saved presets, still offers every shipped look.
function merge(userPresets, fillLook) {
  var list = Array.isArray(userPresets) ? userPresets : []
  var saved = Object.create(null)
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (p && p.builtin !== true) saved[nameKey(p.name)] = true
  }
  var out = []
  for (var j = 0; j < SHIPPED.length; j++) {
    var s = SHIPPED[j]
    if (saved[nameKey(s.name)]) continue
    var row = { id: s.id, name: s.name, look: fillLook(s.look), builtin: true }
    // Only a shipped look can carry one (see the header): saved presets are
    // read back through boundPresets, which keeps id/name/look.
    if (s.setup) row.setup = s.setup
    out.push(row)
  }
  for (var k = 0; k < list.length; k++) out.push(list[k])
  return out
}

// The row that stands for the look on screen, for the "active" mark: the first
// entry whose look the current one includes. `lookIncludes` is
// DockModel.lookIncludes, passed the way merge() takes fillLook.
//
// A saved preset and a shipped look can be key-for-key equal without sharing a
// name -- merge() only settles names, and the copy the user saved under a name
// of their own is exactly the row they can edit. Since the shipped looks lead
// the list, a plain first match would light up the read-only row and leave
// theirs reading as inactive, so the entry the user saved wins the tie and a
// shipped look answers only when no saved preset matches.
function activeId(presets, cur, lookIncludes) {
  var list = Array.isArray(presets) ? presets : []
  var shipped = ""
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p || !lookIncludes(cur, p.look)) continue
    if (p.builtin !== true) return p.id
    if (shipped === "") shipped = p.id
  }
  return shipped
}

// The presets a config may hold: everything the list carries that did not ship
// with the dock. Writes go through this, so a shipped look is never saved into
// a user's omadock.json.
function userOnly(presets) {
  var out = []
  var list = Array.isArray(presets) ? presets : []
  for (var i = 0; i < list.length; i++) if (!list[i] || list[i].builtin !== true) out.push(list[i])
  return out
}

// How many presets the user saved, against DockModel.MAX_PRESETS.
function userCount(presets) {
  return userOnly(presets).length
}
