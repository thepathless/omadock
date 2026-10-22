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
//   Glass                  gradient fill (PR #13, 7ab8e81) with film grain
//                          (#13, 172407b) and a rim that stays visible over it
//                          (#45, a9fe92c), long theme-coloured dividers
//                          (#17, bbd672b) and the Lift hover (#19, 8f46e06)
//   Pixel                  the pixel icon style with a B/W tint and a coarse
//                          grid, plus the tone controls that keep a poster-like
//                          icon readable (#13, ef69eb5 and 9e34022)
//   Mono                   the transparent dock -- icons only, no card, border
//                          or panel (#12, 23ab907) -- in monochrome with the
//                          accent tint (#13) and the Glow hover (#19, fb70a80)
//                          that was drawn for exactly these glyph-like icons
//   Panels                 Split sections (#14, afb82a6 and b721251): one panel
//                          per dock section over a quiet Mono gradient, with the
//                          panel gap #13 taught to snap to the pixel grid
//   Nameplates             names always on, joined to the icon by a Plate, with
//                          the window marks in the upright column beside the
//                          name (#47, @priard)
//   Silkscreen              the same names in the Silkscreen pixel font the
//                          labels ship with, small on a pill, drawn with the
//                          outline that reads on any fill (#47, @priard)
//   macOS Sequoia          the modern Apple macOS Sequoia dock:
//                          floating 24px squircle shelf with #ffffff neutral
//                          frosted glass (0.22 opacity, blur on), 0.5px white
//                          specular rim highlight, deep ambient shadow (0.55),
//                          bottom-anchored fisheye wave magnification, launch hop
//                          bounce, 4px circular dots, 1px hairline divider, and
//                          floating pill hover tooltips
//
// Deliberately not shipped as presets, and why:
//   - panel layout (#49) is not a look key -- `LOOK_KEYS` has no `layout`, so a
//     preset cannot hold it and one would silently do nothing. It is a
//     placement setting, reachable from any look.
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
    id: "builtin_glass",
    name: "Glass",
    look: {
      bgFill: "gradient", gradientPreset: "aurora", gradientStrength: 0.55, grain: 0.18,
      shadowStrength: 0.5, dividerGeometry: "long", dividerStyle: "theme",
      hoverEffect: "lift", itemSpacing: 6
    }
  },
  {
    id: "builtin_pixel",
    name: "Pixel",
    look: { iconStyle: "pixel", iconTint: "bw", iconGrid: 12, iconContrast: 0.5 }
  },
  {
    id: "builtin_mono",
    name: "Mono",
    look: {
      showBackground: false, showBorder: false, shadowStrength: 0.45,
      iconStyle: "mono", iconTint: "accent", iconContrast: 0.5, iconHoverReveal: true,
      hoverEffect: "glow", itemSpacing: 8, sectionSpacing: 20
    }
  },
  {
    id: "builtin_panels",
    name: "Panels",
    look: {
      bgFill: "gradient", gradientPreset: "mono", gradientStrength: 0.4, grain: 0.12,
      splitSections: true, sectionSpacing: 14, hoverEffect: "zoom"
    }
  },
  {
    id: "builtin_nameplates",
    name: "Nameplates",
    look: {
      labelMode: "always", labelKind: "all", labelBackground: "plate",
      labelPlateHeight: "icon", labelIndicators: "before", labelSize: "medium",
      labelWeight: "medium", labelColor: "auto", labelFont: "theme"
    }
  },
  {
    id: "builtin_silkscreen",
    name: "Silkscreen",
    look: {
      labelMode: "always", labelKind: "all", labelBackground: "pill", labelFont: "pixel",
      labelSize: "small", labelWeight: "bold", labelColor: "auto", labelEffect: "outline",
      labelReveal: "slide"
    }
  },
  {
    id: "builtin_macos_sequoia",
    name: "macOS Sequoia",
    look: {
      showBackground: true, bgColor: "#ffffff", opacity: 0.22, bgFill: "solid", blur: "on",
      showShadow: true, shadowStrength: 0.55,
      showBorder: true, borderWidth: 0.5, borderOpacity: 0.35,
      shape: "rounded", cornerRadius: 24,
      hoverEffect: "wave", launchBounce: true, indicatorShape: "rounded",
      iconSize: 52, itemSpacing: 8, sectionSpacing: 16,
      dividerGeometry: "classic", dividerStyle: "custom", dividerWidth: 1.0, dividerHeight: 55, dividerOpacity: 0.20,
      iconStyle: "original", iconContrast: 0, iconStrength: 1,
      labelMode: "hover", labelBackground: "pill", labelShape: "pill", labelFont: "theme",
      labelSize: "medium", labelWeight: "medium", labelReveal: "slide", labelColor: "auto"
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
    out.push({ id: s.id, name: s.name, look: fillLook(s.look), builtin: true })
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
