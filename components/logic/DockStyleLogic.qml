import QtQuick 6.11
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../../DockModel.js" as DockModel

// Logic extracted from Dock.qml: stateless functions, the dock root
// is passed in and owns all state. Bodies are verbatim.

QtObject {
  // Slot index of running entry idx among VISIBLE icons only. Fully-tiled
  // entries collapse to zero width, so they must not consume a slot in the
  // wave home-center arithmetic — every icon after one would drift by a
  // full slot. Same predicate as visibleRunningCount, so they never disagree.
  function visibleRunningSlotBefore(root, idx) {
    var n = 0
    for (var i = 0; i < idx && i < root.runningSection.length; i++) {
      var e = root.runningSection[i]
      if (!(root.showMinimizedTiles && e && DockModel.allWindowsMinimized(e.windowList, root.liveWsNameOf, root.minimizedWorkspace))) n++
    }
    return n
  }

  // ownLabel false: the slot is not a labelled tile (a preview tile sharing
  // the next running app's index), so a mirrored label is not its own.
  function slotHomeCenter(root, elementIndex, slotsBefore, sepCount, extraLeftWidth, ownLabel) {
    var seps = (typeof sepCount === "number") ? sepCount : (sepCount ? 1 : 0)
    return root.baseRowLeft
      + elementIndex * root.gapWidth
      + slotsBefore * root.iconSlot
      + seps * root.separatorWidth
      + (extraLeftWidth || 0)
      + root.labelExtraBefore(slotsBefore, ownLabel)
      + root.iconSlot / 2
  }

  // Where the pointer sits in the row's unmagnified frame, which is the frame
  // the home centres are measured in. The card grows around its centre as
  // slots magnify, so its left edge moves out by half that growth and a fixed
  // pointer reads that much further right - enough to put the peak a slot off
  // the tile under the cursor.
  function wavePointer(root, cardX, rowOffset, cardWidth) {
    var rest = root.baseRowWidth + 2 * root.baseRowLeft
    var growth = Math.max(0, cardWidth - rest)
    return cardX - rowOffset - growth / 2
  }

  // The wave's window: a raised cosine over `magnifyReach` slots, carried one
  // step wider through the 0.7 power. Both ends stay where the cosine put
  // them -- flat at the peak, and 1.0 (no scale) exactly at the reach -- while
  // the shoulder between them widens, so three neighbours rise with the tile
  // under the pointer instead of the single one the plain cosine lit.
  function magnifyAt(root, homeCenter) {
    if (!root.waveHover) return 0
    var t = Math.abs(root.pointerX - homeCenter) / root.magnifyRange
    if (t >= 1) return 0
    return Math.pow(0.5 * (1 + Math.cos(Math.PI * t)), 0.7)
  }

  function magnifyScaleAt(root, homeCenter) {
    return 1 + (root.magnifyPeak - 1) * root.magnifyAt(homeCenter)
  }

  // Layout slot expansion handles spacing naturally; manual translation nudges are deprecated.
  function waveOffsetAt(root, homeCenter) {
    return 0
  }

  // The bar foreground is tuned for the bar's own background. A custom dock
  // colour can land on the same side of the scale — a light theme's dark text
  // on a dark card, or the reverse — so flip only when the two collide.
  function isLight(root, value) {
    return (0.2126 * value.r + 0.7152 * value.g + 0.0722 * value.b) > 0.5
  }

  function cardRadius(root, height) {
    return root.effectiveCardRadius
  }

  // The card's body: the material's own colour, at the look's lightness
  // (surfaceLift) and pulled toward neutral by surfaceDesaturate. Without a
  // body a translucent fill is only a film over whatever is behind it, so the
  // card renders at the wallpaper's brightness and has no tone of its own.
  // surfaceStability is the share of the card that body fills, and so the only
  // opacity that matters once a look sets it. Lift -1, no desaturation and no
  // stability reproduce the fill as written, exactly.
  function surfaceBody(root, fill, opacity) {
    var c = Qt.color(fill)
    var lift = root.surfaceLift
    var desat = root.surfaceDesaturate
    var stability = root.surfaceStability
    if (lift < 0 && desat <= 0 && stability <= 0) return Util.alpha(c, opacity)
    var l = lift >= 0 ? lift : c.hslLightness
    var s = c.hslSaturation * (1 - desat)
    return Qt.hsla(c.hslHue < 0 ? 0 : c.hslHue, s, l, stability > 0 ? stability : opacity)
  }

  // The body for a surface that floats on its own (the hover name): it sits
  // over the wallpaper rather than over the card's blurred backdrop, so it
  // cannot borrow a body from what is behind it - it takes the material's own
  // body at full stability - and that body is moved away from the ink the
  // dock chose for it (lighter under dark ink, deeper under light ink) until
  // the pair reads at the floating floor. Same hue, same chroma: only the
  // separation grows, so no wallpaper can leave the name under-contrasted.
  function floatingBody(root, fill, opacity, ink) {
    var body = surfaceBody(root, fill, opacity)
    var h = body.hslHue < 0 ? 0 : body.hslHue
    var sat = body.hslSaturation
    var l = body.hslLightness
    // 6.5: WCAG AA for body text is 4.5, and the light end of the band already
    // held 6.1 through the wallpaper showing in a translucent body; an opaque
    // body gives every wallpaper that pair, not just the bright ones.
    var floor = 6.5
    // The dock's own light/dark test (the one inkOn uses): dark ink lifts the
    // body, light ink deepens it, so the two always move apart.
    var dir = root.isLight(ink) ? -1 : 1
    for (var i = 0; i < 100; i++) {
      var c = Qt.hsla(h, sat, l, 1)
      if (root.contrastRatio(c, ink) >= floor) return c
      l += dir * 0.01
      if (l <= 0 || l >= 1) break
    }
    return Qt.hsla(h, sat, Math.max(0, Math.min(1, l)), 1)
  }

  // The card as it renders at one end of the backdrop's range: the body over
  // black (dark) or over white (light). A translucent surface is a band, not a
  // colour, and the two ends are all an ink choice needs to know.
  function surfaceAt(root, fill, dark) {
    var body = surfaceBody(root, fill, root.effectiveDockOpacity)
    var k = body.a
    var end = dark ? 0 : 1
    return Qt.rgba(body.r + (end - body.r) * (1 - k), body.g + (end - body.g) * (1 - k),
                   body.b + (end - body.b) * (1 - k), 1)
  }

  // A fill as it actually renders: below full opacity the backdrop shows
  // through far more than the paint, so anything choosing ink against the card
  // (its text, its dot) has to judge this rather than the colour as written.
  // Over a body that backdrop is unknown, so the answer is the middle of the
  // band the card can land in.
  function fillOnBackdrop(root, fill) {
    if (root.surfaceStability > 0) {
      var lo = surfaceAt(root, fill, true)
      var hi = surfaceAt(root, fill, false)
      return Qt.rgba((lo.r + hi.r) / 2, (lo.g + hi.g) / 2, (lo.b + hi.b) / 2, 1)
    }
    var a = root.effectiveDockOpacity
    if (a >= 1) return fill
    var back = Color.bar.background
    return Qt.rgba(back.r + (fill.r - back.r) * a, back.g + (fill.g - back.g) * a,
                   back.b + (fill.b - back.b) * a, 1)
  }

  // Ink for text, dots and glyphs over the rendered card: the best of the
  // theme's own ink and the two hard contrast ends. A material with a body does
  // not follow the theme's background any more, so matching the card's side of
  // the scale against the theme ink stops being the right question.
  function inkOn(root, fill) {
    var lo = surfaceAt(root, fill, true)
    var hi = surfaceAt(root, fill, false)
    var cands = [Color.bar.text, Qt.color("#12100f"), Qt.color("#f2efec")]
    var best = cands[0]
    var bestMin = -1
    for (var i = 0; i < cands.length; i++) {
      // The candidate has to read at both ends: the band, not one sample.
      var m = Math.min(root.contrastRatio(cands[i], lo), root.contrastRatio(cands[i], hi))
      if (m > bestMin) { best = cands[i]; bestMin = m }
    }
    return best
  }

  // Distance from the slot's bottom edge to the bottom of the artwork.
  // "center" (and a label plate's side marks) centres the art in the slot;
  // otherwise it is lifted clear of the indicator band.
  function iconArtBottom(root) {
    if (root.labelSideMarks || root.iconBaseline === "center")
      return Math.round((root.iconSlot - root.baseIconArt) / 2)
    return Math.round(root.indicatorBand + (root.iconSlot - root.indicatorBand - root.baseIconArt) / 2) + root.indicatorLift
  }

  // Bottom offset for the running marks: the classic slot-relative place, or
  // the look's own distance above the card's bottom edge (negative, drawn in
  // the card's padding) when it asks for one.
  function markBottomMargin(root) {
    if (root.indicatorInset < 0) return Style.space(1) + root.indicatorLift
    // The look names the dot's distance above the card's bottom edge in
    // pixels, and the card's padding resolves to pixels too (dockPadPx), so
    // this lands on that distance whatever the padding is: the two numbers do
    // not trade against each other.
    return root.indicatorInset - (root.dockPadPx + root.borderWidth)
  }

  // Keys and lookups for the keyed Repeater models (KeyedListModel), which
  // keep the delegates of items that stay when these lists are replaced.
  function pinnedRowKey(root, item) {
    return item.kind === "group" ? "group:" + item.id : "app:" + item.appId
  }

  // Tint for an iconTint mode ("text", "accent", "bw") over a backdrop.
  function tintFor(root, mode, textColor, backdrop) {
    if (mode === "bw") return root.blackOrWhiteOn(backdrop)
    return root.readableOn(mode === "accent" ? Color.accent : textColor, backdrop)
  }

  // Near black or near white, whichever contrasts more with the backdrop.
  function blackOrWhiteOn(root, backdrop) {
    var dark = Qt.color("#141414")
    var light = Qt.color("#f2f2f2")
    return root.contrastRatio(dark, backdrop) >= root.contrastRatio(light, backdrop) ? dark : light
  }

  // WCAG relative luminance and contrast ratio.
  function luminance(root, c) {
    function lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
  }

  function contrastRatio(root, a, b) {
    var la = root.luminance(a), lb = root.luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  // A colour with the given hue and saturation, moved in lightness away
  // from the backdrop (darker on a light one, lighter on a dark one) until
  // it reaches a 3:1 contrast ratio, the WCAG minimum for graphics.
  function readableOn(root, color, backdrop) {
    var c = Qt.color(color)
    var bg = Qt.color(backdrop)
    if (root.contrastRatio(c, bg) >= 3) return c
    var darker = root.luminance(bg) > 0.18
    var h = c.hslHue < 0 ? 0 : c.hslHue
    var sat = c.hslSaturation
    var best = c
    for (var step = 1; step <= 20; step++) {
      var l = darker ? Math.max(0, c.hslLightness - step * 0.05) : Math.min(1, c.hslLightness + step * 0.05)
      best = Qt.hsla(h, sat, l, c.a)
      if (root.contrastRatio(best, bg) >= 3) break
    }
    return best
  }

  // Symbolic icon colour over a given backdrop: white or black when set,
  // for "bw" whichever of the two contrasts more with that backdrop (so a
  // folder can be dark on the dock and light in a dark stack popup), and
  // otherwise white or black to suit the theme.
  function symbolicColorOn(root, backdrop) {
    var c
    if (root.folderColor === "white") c = Qt.color("#ffffff")
    else if (root.folderColor === "black") c = Qt.color("#111111")
    else if (root.folderColor === "bw") c = root.blackOrWhiteOn(backdrop)
    else c = Qt.color((Color.bar.background.hslLightness < 0.5 || Color.background.hslLightness < 0.5) ? "#ffffff" : "#111111")
    // Pure white glares next to the app icons; mix a little of the backdrop
    // into light glyphs so they sit in the panel instead.
    if (c.hslLightness > 0.5) {
      var bg = Qt.color(backdrop)
      var k = root.symbolicLightSoftening
      c = Qt.rgba(c.r + (bg.r - c.r) * k, c.g + (bg.g - c.g) * k, c.b + (bg.b - c.b) * k, 1)
    }
    return c
  }

  function isWindowFocused(root, win) {
    if (!win || !win.address || !root.activeWindowAddress) return false
    return win.address === root.activeWindowAddress
  }

  function isWindowParked(root, win) {
    if (!win) return false
    return root.isWinParkedLive(win)
  }

  // Minimized-window preview tiles (macOS-style section on the dock's right).
  // In minimizeMode "all", a parked app's windows compress into ONE stacked
  // group tile; in "active" mode every window keeps its own tile.
  function tileModel(root) {
    if (!root.showMinimizedTiles) return []
    var list = root.minimizedWindows
    if (root.minimizeMode !== "all") {
      var singles = []
      for (var s = 0; s < list.length; s++) singles.push({ type: "single", win: list[s] })
      return singles
    }
    var groups = {}
    var order = []
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      var key = w.appId || w.address
      if (!groups[key]) {
        groups[key] = { type: "group", appId: key, title: w.title, windows: [] }
        order.push(key)
      }
      groups[key].windows.push(w)
    }
    // Oldest member parks the group's slot in line.
    order.sort(function (a, b) {
      var ta = root.parkedAt[groups[a].windows[0].address] !== undefined ? root.parkedAt[groups[a].windows[0].address] : 0
      var tb = root.parkedAt[groups[b].windows[0].address] !== undefined ? root.parkedAt[groups[b].windows[0].address] : 0
      return ta - tb
    })
    var out = []
    for (var g = 0; g < order.length; g++) out.push(groups[order[g]])
    return out
  }

  // Theme gradient colors, mined from the theme's colors.toml: the accent
  // plus up to two hues far enough apart, falling back to the accent.
  // Moved verbatim from the composition root (ratchet); themeText is the
  // theme file's content, read through the root's FileView by the caller so
  // the binding keeps its original dependencies (themeVersion, file text).
  function themeGradientColors(root, themeText) {
    var _tv = root.themeVersion
    var text = ""
    try {
      text = DockModel.readCapped(themeText, DockModel.MAX_COLORS_TOML_BYTES)
    } catch (e) {
      console.warn("[omadock] Failed reading theme colors:", e)
    }
    var named = {}
    var re = /^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/gm
    var m
    while ((m = re.exec(text)) !== null) named[m[1]] = m[2]
    var accent = named.accent || String(Color.accent)
    var picked = [accent]
    var order = ["magenta", "blue", "cyan", "red", "green", "orange", "yellow"]
    function hueGap(a, b) {
      var ha = Qt.color(a).hslHue, hb = Qt.color(b).hslHue
      if (ha < 0 || hb < 0) return 1
      var d = Math.abs(ha - hb)
      return Math.min(d, 1 - d)
    }
    for (var i = 0; i < order.length && picked.length < 3; i++) {
      var c = named[order[i]]
      if (!c) continue
      var ok = true
      for (var j = 0; j < picked.length; j++) if (hueGap(c, picked[j]) < 0.07) ok = false
      if (ok) picked.push(c)
    }
    while (picked.length < 3) picked.push(accent)
    return picked
  }
}
