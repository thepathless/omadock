// Pure helpers for the dock's layout (Dock or Panel) and its alignment
// (Dock.qml placement, components/DockCard.qml). Plain JS with no Qt
// globals, so the node tests run it in a vm context like DockLabels.js.

// "panel" spans the screen's bottom edge; anything else is the floating dock.
function normalizeLayout(v) {
  return String(v === undefined || v === null ? "" : v).toLowerCase() === "panel" ? "panel" : "dock"
}

// "spread" (Both sides) puts folders and drives at the right edge; "taskbar"
// centres Start and apps together, with the tray on the right.
function normalizeAlignment(v) {
  var a = String(v === undefined || v === null ? "" : v).toLowerCase()
  return (a === "left" || a === "right" || a === "spread" || a === "taskbar") ? a : "center"
}

// Both sides needs room to open a gap: the full-width panel, or a dock
// split into panels.
function spreadAvailable(layout, splitSections) {
  return normalizeLayout(layout) === "panel" || splitSections === true
}

// What the dock draws for the stored settings. The panel is one bar, so
// it ignores split sections; Both sides falls back to center where it
// cannot open a gap, and to left when nothing would go right. The taskbar
// needs the panel's full width for its three zones, so a floating dock
// centres instead.
function placement(layout, alignment, splitSections, hasRightGroup) {
  var panel = normalizeLayout(layout) === "panel"
  var split = !panel && splitSections === true
  var align = normalizeAlignment(alignment)
  if (align === "spread" && !spreadAvailable(layout, splitSections)) align = "center"
  if (align === "spread" && !hasRightGroup) align = "left"
  if (align === "taskbar" && !panel) align = "center"
  return { panel: panel, split: split, align: align, taskbar: align === "taskbar" }
}

// The card's x and width when it does not hug its icons: the panel spans
// the window; a spread dock spans it less the inset on each side. null:
// the card is as wide as its row.
function stretchedBox(place, windowWidth, inset) {
  if (place.panel) return { x: 0, width: windowWidth }
  if (place.align === "spread") return { x: inset, width: Math.max(0, windowWidth - 2 * inset) }
  return null
}

// The strip along the screen edge that reveals a hidden dock. "dock": under
// the card plus a margin, aligned with it. "edge": the whole edge less
// cornerInset at each end, so hot corners keep working.
function revealStripBox(area, windowWidth, cardWidth, stretch, align, gapsOut, margin, cornerInset) {
  if (area === "edge") return { x: cornerInset, width: Math.max(0, windowWidth - 2 * cornerInset) }
  if (stretch) return { x: 0, width: windowWidth }
  var width = Math.min(windowWidth, cardWidth + margin)
  if (align === "left") return { x: gapsOut, width: width }
  if (align === "right") return { x: windowWidth - width - gapsOut, width: width }
  return { x: Math.round((windowWidth - width) / 2), width: width }
}

// The strip's height: a thin line while the dock hides. Revealed from the
// whole edge it stays as tall as the dock (dockHeight) while the dock shows,
// so the pointer can travel from where it touched the edge to the card
// without the dock hiding on the way. Not while the dock is held open
// (intelligent autohide with nothing overlapping it): nothing would hide it,
// and the band would take clicks from windows beside the dock.
function revealStripHeight(area, active, shown, held, lineHeight, dockHeight) {
  if (!active) return 0
  if (!shown) return lineHeight
  return area === "edge" && !held ? dockHeight : 0
}

// Rounds to whole device pixels when a scale is given (label plates keep
// their edges on the grid); whole logical pixels otherwise.
function snap(v, dpr) {
  return dpr > 0 ? Math.round(v * dpr) / dpr : Math.round(v)
}

// Where the row starts inside a stretched card, past the content inset.
// A row wider than the card starts at the left edge.
function rowOffset(align, innerWidth, rowWidth, dpr) {
  var free = Math.max(0, innerWidth - rowWidth)
  if (align === "right") return dpr > 0 ? snap(free, dpr) : free
  if (align === "center") return snap(free / 2, dpr)
  return 0
}

// Width of the gap between the left group and the right one, so the right
// group ends on the inner edge. gapX is where the gap item starts (the row
// spacing after the left group is already in it); one more spacing stands
// between the gap and the right group.
// The gap never reaches 0: a Row skips a zero-width child together with the
// spacing after it, so when magnification used up a small gap the right
// group would jump left by one spacing. It bottoms out at one device pixel
// (one logical pixel without a scale) instead.
function spreadGap(innerWidth, gapX, rightWidth, spacing, dpr) {
  var w = innerWidth - gapX - rightWidth - spacing
  return dpr > 0 ? Math.max(1 / dpr, Math.floor(w * dpr) / dpr) : Math.max(1, w)
}

// How far the right group's resting centres sit past where a packed row
// would put them: the card's free width at rest.
function spreadHomeShift(innerWidth, restWidth) {
  return Math.max(0, innerWidth - restWidth)
}

// Windows 11's taskbar: Start and apps centred together on the screen,
// the tray (the clock) at the right edge. The clock's room is
// reserved in style units so the fit planner and the clock agree on it.
var TASKBAR_CLOCK_WIDTH = 74

// The width the app section takes between Start and the tray, from the slots
// the row draws plus the tiles and separators that sit inside it. Every app,
// group, folder and drive takes one icon slot; a separator can be a negative
// width (a hidden divider), exactly as Dock.baseRowWidth counts it.
function taskbarAppWidth(iconSlot, appSlots, tileCount, tileWidth, separators, separatorWidth, gap) {
  var elements = appSlots + tileCount + separators
  if (elements <= 0) return 0
  return appSlots * iconSlot + tileCount * tileWidth + separators * separatorWidth + (elements - 1) * gap
}

// The free room BEFORE Start (or apps when Start is hidden): centre the
// whole Start + app group, clamped so a packed bar never overflows.
// `packedWidth` is the whole row at rest (Dock.baseRowWidth), without the
// clock; adding the leading gap and the clock costs one row spacing each.
function taskbarStartGap(innerWidth, appsWidth, buttonWidth, packedWidth, clockWidth, spacing, hasButton) {
  var groupWidth = appsWidth + (hasButton ? buttonWidth + (appsWidth > 0 ? spacing : 0) : 0)
  var ideal = (innerWidth - groupWidth) / 2 - spacing
  var slack = innerWidth - packedWidth - clockWidth - 2 * spacing
  return Math.max(0, Math.min(ideal, slack))
}
