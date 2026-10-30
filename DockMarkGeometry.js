// Pure helpers for how big a dock mark is and how much room it needs
// (components/DockIndicatorRow.qml, components/DockIndicator.qml and
// components/DockLabel.qml). Plain JS with no Qt globals, so the node tests run
// it in a vm context like DockLabels.js: the callers pass Style.space as
// `space` (the same way they pass a measuring function to DockLabels) and the
// output's pixel grid as `dpr`.
//
// One owner, because the same numbers are drawn in three places: the row sizes
// the cell each mark sits in, the indicator draws the dot and the bar, and a
// plate reserves the column's room before the icon or after the name. Spelled
// out in each file, changing one silently disagreed with the others - the same
// family as the row that declared a grid slot it did not draw.
//
// The room a mark gets is the mark: `cell` is the widest of the marks the row
// draws (the dot and the bar, each already carrying the hairline floor), so a
// theme that makes the spacing scale very compact can shrink a mark and its
// cell together, but never the cell alone. The floor itself has one owner,
// `hairline`, and every mark that is drawn applies it.

// Style.space units. The dock's classic marks: a 5 px dot (4 px when the marks
// are dense under the icon; a side column keeps 5), a 12x4 accent bar (9x4
// dense) and 3 px between marks (2 px dense).
var DOT = 5
var DOT_DENSE = 4
var BAR = 4
var BAR_LENGTH = 12
var BAR_LENGTH_DENSE = 9
var SPACING = 3
var SPACING_DENSE = 2
// The compact overflow pill past five windows: its own padding and height.
var PILL_PAD = 4
var PILL_HEIGHT = 5
// The room a plate keeps for the column of marks: its inset from the plate's
// edge and the gap from there to the art or the name.
var EDGE = 1
var GAP = 5

// The dot's spacing: dense marks use the smaller one; a side column keeps
// the full dot, dense or not, so a couple of dots beside a plate do not
// look lost (the upright bar there is as thick as the dot).
function dotSpace(dense, vertical) { return (vertical || !dense) ? DOT : DOT_DENSE }

// Whole device pixels, never below one: at a fractional output scale a mark
// lost or gained a row of pixels depending on where it landed.
function snap(v, dpr) { return Math.max(1, Math.round(v * dpr)) / dpr }

// The thinnest a mark may be drawn: a hairline of whole device pixels. The one
// owner of the floor rule - `dot` and `barThickness` apply it, `cell` derives
// from those, so a mark can never be bigger than the room its cell reserves.
function hairline(dpr) { return 2 / dpr }

// The cell the row gives each mark, and the width a plate reserves for its
// column: as wide across the row (or column) as the widest mark the row can
// draw there, so a dot and the accent bar share one centre line - and a
// compact theme that shrinks the spacing scale shrinks cell and mark together.
function cell(space, dpr, dense, vertical) {
  return Math.max(dot(space, dpr, dense, vertical), barThickness(space, dpr))
}

// The size a mark takes when a look names it, on the output's pixel grid:
// "app" mode draws one dot at this size, every other mode keeps dot().
function dotFor(space, dpr, mode, size) {
  if (mode !== "app") return dot(space, dpr, false, false)
  var n = Number(size)
  var px = (isFinite(n) && n > 0) ? n : DOT
  var scale = (dpr > 0) ? dpr : 1
  return Math.max(1 / scale, Math.round(px * scale) / scale)
}

// A dot's own size, a hairline at the very least so it stays visible.
function dot(space, dpr, dense, vertical) {
  return Math.max(hairline(dpr), snap(space(dotSpace(dense, vertical)), dpr))
}

// The accent bar's thickness (the same across the row as a dot) and its length
// along the row - upright in a column, where it is as thick as a dot.
function barThickness(space, dpr) { return Math.max(hairline(dpr), snap(space(BAR), dpr)) }
function barLength(space, dpr, dense) { return snap(space(dense ? BAR_LENGTH_DENSE : BAR_LENGTH), dpr) }

// Room between the marks, and the overflow pill's own box.
function rowSpacing(space, dpr, dense) { return snap(space(dense ? SPACING_DENSE : SPACING), dpr) }
function pillWidth(space, textWidth) { return textWidth + space(PILL_PAD) }
function pillHeight(space) { return space(PILL_HEIGHT) }

// The room a plate reserves for its column of marks: the plate's inset for it,
// the column's width - the cell the row draws the column's marks in, which is
// the marks' own width, so they sit centred in it - and the gap to the art or
// the name.
function column(space, dpr) {
  return { edge: space(EDGE), width: cell(space, dpr, true, true), gap: space(GAP) }
}
