import QtQuick 6.11
import Quickshell
import qs.Commons
import qs.Ui
import "../../DockLabels.js" as DockLabels

// Logic module: name-label policy for dock tiles (apps, app groups,
// folders). style() is everything one DockLabel needs; the width registry
// (root.labelExtras) is what lets zoom/wave centres and the card's hover
// anchor account for labels. Helpers with no Qt in them live in DockLabels.js.

QtObject {
  function style(root, kind) {
    var show = !!root && DockLabels.labelVisible(root.labelMode, root.labelKind, kind)
    var pixel = !!root && root.labelFont === "pixel"
    var base = Style.font.caption
    // The macOS callout is the Dock's own label: 13px (Style.font.subtitle)
    // at its medium setting, regular weight, the system sans. Silkscreen is
    // drawn on an 8 px grid; the dock chip follows the theme scale.
    var mac = !!root && root.labelChip === "macos"
    var sizes = pixel ? { small: 8, medium: 12, large: 16 }
      : mac ? { small: Math.max(10, Style.font.subtitle - 2), medium: Style.font.subtitle, large: Style.font.subtitle + 2 }
      : { small: base - 2, medium: base, large: base + 2 }
    // Auto: one black-or-white ink for every label, the one that reads best
    // where the dock is hardest for it (steadyInk over the gradient).
    var ink = root ? steadyInk(root) : Color.bar.text
    if (root && root.labelColor === "theme") ink = root.dockForeground
    else if (root && root.labelColor === "accent") ink = Color.accent
    var weights = { regular: Font.Normal, medium: Font.Medium, bold: Font.Bold }
    var dockH = (root && root.dockCard) ? root.dockCard.height : 0
    // Hover labels are drawn over the neighbouring icons: always a pill,
    // and a denser one.
    var hover = !!root && root.labelMode === "hover"
    var background = hover ? "pill" : (root ? root.labelBackground : "none")
    return {
      show: show,
      hover: hover,
      mirror: !!root && (root.placement.align === "right" || (root.placement.align === "spread" && kind === "folders")),
      fontPx: sizes[root ? root.labelSize : "medium"] || sizes.medium,
      weight: pixel ? Font.Normal : (weights[root ? root.labelWeight : "medium"] || Font.Medium),
      family: pixel ? "Silkscreen" : ((root && root.labelFont === "sans") ? "sans-serif" : Style.font.family),
      ink: ink,
      // A lighter accent: themes often fill the dock from the same palette,
      // and a plain accent glow vanishes into it.
      glow: Qt.lighter(Color.accent, 1.6),
      background: background,
      // The hover name's callout: the dock's own chip, or the macOS Dock's
      // (HoverNamePlate, variant "macos"): a dark translucent label that
      // tracks the magnified icon. A look key, so only a preset asks for it.
      chip: mac ? "macos" : "dock",
      shape: root ? root.labelShape : "dock",
      // Where the tile's window indicators go: beside the art on the plate, or under it.
      marks: (root && root.labelSideMarks) ? root.labelIndicators : "under",
      dockRatio: (root && dockH > 0) ? root.effectiveCardRadius / dockH : 0.25,
      // Nested corners: the panel's drawn radius less the plate gap.
      nestedRadius: (root && dockH > 0 && root.labelPlates) ? Math.max(0, Math.min(root.effectiveCardRadius, dockH / 2) - root.plateSpacing.gap) : 0,
      // The smallest edge corner that stays inside the panel's curve.
      plateFit: (root && dockH > 0 && root.labelPlates) ? DockLabels.plateFitRadius(Math.min(root.effectiveCardRadius, dockH / 2), root.plateSpacing.gap) : 0,
      reveal: root ? root.labelReveal : "slide",
      effect: root ? root.labelEffect : "none",
      // The dock's fit (DockFit.js) may shorten names to make room.
      maxWidth: root ? ((root.fitHostRef && root.fitHostRef.plan.labelMax > 0) ? Math.min(root.labelMaxWidth, root.fitHostRef.plan.labelMax) : root.labelMaxWidth) : 140
    }
  }

  // What is behind card point (x, y): the gradient there (DockLabels.gradientAt,
  // the shader's own formula), or the flat backdrop.
  function backdropAt(root, x, y) {
    if (!root || !root.showBackground || root.bgFill !== "gradient" || !root.dockCard) return root ? root.iconBackdropColor : Color.bar.background
    var b = Color.bar.background
    var cols = (root.gradientColors || []).map(function(c) { var q = Qt.color(c); return { r: q.r, g: q.g, b: q.b } })
    var g = DockLabels.gradientAt({ r: b.r, g: b.g, b: b.b }, cols, root.gradientStrength, root.dockCard.width, root.dockCard.height, x, y)
    return Qt.rgba(g.r, g.g, g.b, 1)
  }

  // Auto ink: of near-black and near-white (as blackOrWhiteOn), the one
  // whose weakest contrast along the label row is highest. A gradient is
  // sampled at nine points across the card; a flat fill is one backdrop.
  // A translucent dock lets what is under it through, so each sample is
  // laid over the theme's background at the dock's opacity.
  function steadyInk(root) {
    var dark = Qt.color("#141414"), light = Qt.color("#f2f2f2")
    var samples = []
    var card = root.dockCard
    if (root.showBackground && root.bgFill === "gradient" && card && card.width > 0) {
      for (var i = 0; i < 9; i++) {
        samples.push(seen(root, backdropAt(root, card.width * (i + 0.5) / 9, card.height / 2)))
      }
    } else {
      samples.push(seen(root, Qt.color(root.iconBackdropColor)))
    }
    var pick = DockLabels.steadyInk(samples, { r: dark.r, g: dark.g, b: dark.b }, { r: light.r, g: light.g, b: light.b })
    return pick.r < 0.5 ? dark : light
  }

  // Plate row spacing (DockLabels.plateSpacing) on the output's pixel grid.
  function plateSpacing(root) {
    var s = root.outputScale > 0 ? root.outputScale : 1
    var line = Math.max(1, Math.round(root.dividerLineWidth * s)) / s
    return DockLabels.plateSpacing(Style.space(root.itemSpacing), line, s, Style.space(4), Style.space(12))
  }

  // A plate's vertical box in its tile (tile height tileH), the same for
  // label plates and the unlabelled tiles' plates. "dock" height: one plate
  // gap from the card's inner top and bottom. With indicators beside the
  // art (or on an unlabelled tile in that mode): centred in the card, an
  // even margin above and below on the device-pixel grid. With indicators
  // under the art: from just above the art to just below the indicators.
  function plateBox(root, tileH) {
    var s = root.outputScale > 0 ? root.outputScale : 1
    var card = root.dockCard
    var top = card ? card.topPadding : 0
    var inner = tileH + top + (card ? card.bottomPadding : 0)
    var art = root.baseIconArt
    var artTop = tileH - root.iconArtBottom - art
    var v = Style.space(4)
    if (root.labelPlates && root.labelPlateHeight === "dock") {
      var g = root.plateSpacing.gap
      return { y: g - top, h: inner - 2 * g }
    }
    if (root.labelIndicators !== "under") {
      var m = DockLabels.gridRound((inner - art - 2 * v) / 2, s)
      return { y: m - top, h: inner - 2 * m }
    }
    var y = DockLabels.gridRound(artTop - v, s)
    var bottom = DockLabels.gridRound(tileH - Style.space(1) - root.indicatorLift + v, s)
    return { y: y, h: bottom - y }
  }

  // A dock colour as seen: over the theme background at the dock's opacity.
  function seen(root, c) {
    var a = root.showBackground ? root.effectiveDockOpacity : 0
    var u = Color.background
    return { r: u.r + (c.r - u.r) * a, g: u.g + (c.g - u.g) * a, b: u.b + (c.b - u.b) * a }
  }

  // Background for a name or plate in that ink: the other end of the scale.
  function fillFor(root, ink, hover) {
    return root.isLight(Qt.color(ink)) ? Util.alpha("#141414", hover ? 0.9 : 0.62) : Util.alpha("#f2f2f2", hover ? 0.94 : 0.72)
  }

  // The mono / dots icon colour on a label plate: the user's choice kept
  // readable against the plate rather than the dock (B/W gives the plate's
  // own ink).
  function plateIconTint(root) {
    if (root.labelMode !== "always" || root.labelBackground !== "plate") return root.iconTintColor
    return root.tintFor(root.iconTint, root.dockForeground, plateBackdrop(root))
  }

  // A plate at rest as seen: its fill (fillFor the label ink, at the
  // plate's resting opacity) laid over the dock behind the icons.
  function plateBackdrop(root) {
    var fill = Qt.color(fillFor(root, style(root, "app").ink, false))
    var under = seen(root, Qt.color(root.iconBackdropColor))
    var k = 0.55
    return Qt.rgba(under.r + (fill.r - under.r) * k, under.g + (fill.g - under.g) * k, under.b + (fill.b - under.b) * k, 1)
  }

  // The user's name wins; an app without a desktop entry (its name is its
  // class id) gets a readable one.
  function displayName(root, appId, name) {
    var custom = (root && appId && root.labelNames && Object.prototype.hasOwnProperty.call(root.labelNames, appId)) ? root.labelNames[appId] : undefined
    if (typeof custom === "string" && custom !== "") return custom
    if (appId && (name === "" || name === appId)) return DockLabels.prettyAppId(appId)
    return name
  }

  function tooltipNeeded(root, kind, hasWindows, hasStateHint, shortened) {
    var shown = !!root && DockLabels.labelVisible(root.labelMode, root.labelKind, kind)
    return DockLabels.tooltipNeeded(shown, hasWindows, hasStateHint, shortened)
  }

  // Label width before a slot's icon, the part of its own extra ahead of
  // the icon included (a mirrored label, a side-indicator column).
  function extraBefore(root, slot, ownLabel) {
    return root ? DockLabels.homeExtra(root.labelExtras, slot, ownLabel !== false) : 0
  }

  function setExtra(root, slot, owner, width, before) {
    if (!root || slot < 0) return
    var next = DockLabels.withExtra(root.labelExtras, slot, owner, width, before)
    if (next !== root.labelExtras) root.labelExtras = next
  }

  function setName(root, appId, name) {
    root.labelNames = DockLabels.withLabelName(root.labelNames, appId, name)
    root.saveConfig()
  }

  // Apps the Labels page lists: pinned first, then running, once each.
  function nameRows(root) {
    var rows = []
    var seen = {}
    var lists = [root.dockModel.pinned || [], root.dockModel.running || []]
    for (var l = 0; l < lists.length; l++) {
      for (var i = 0; i < lists[l].length; i++) {
        var e = lists[l][i]
        if (!e || !e.appId || seen[e.appId]) continue
        seen[e.appId] = true
        var auto = (e.name === "" || e.name === e.appId) ? DockLabels.prettyAppId(e.appId) : e.name
        rows.push({ appId: e.appId, auto: auto })
      }
    }
    return rows
  }
}
