// Pure helpers for the dock's running marks - how many an item speaks for and
// how the row draws them (components/DockIndicatorRow.qml, drawn mark by mark
// through components/DockIndicator.qml). Plain JS with no Qt globals, so the
// node tests run it in a vm context like DockLabels.js.

// Past this many windows the marks go dense and the count moves into the
// compact "+N" overflow pill, which takes the last slot.
var DENSE_AT = 5

// How many windows an item speaks for: the windows the dock knows about, or
// one for an app that runs with no window (a launch race, a tray-bound
// player).
function totalWindows(windows, running) {
  var n = (windows && windows.length) || 0
  return n > 0 ? n : (running ? 1 : 0)
}

// What the row draws for those windows, in the order it draws it:
//   total    what the overflow pill counts to
//   dense    past DENSE_AT-1 the marks shrink
//   overflow past DENSE_AT the count moves into the pill
//   dots     what the repeater repeats
//   slots    what the Grid declares - exactly the marks drawn, so a Grid can
//            never reserve a gap for a slot with no mark to fill it (a spare
//            one shifted a lone dot, or accent bar, half a gap off the icon's
//            centre)
// The dots, the slots, the pill and the count it shows all read this one plan.
// The kind of mark a slot draws. "app" mode speaks for the app: one mark,
// which turns into the active bar while any of its windows holds the focus
// (Windows 11's wider accent pill). Per-window mode keeps its three states:
// active bar, open dot, hollow minimized dot.
function markKind(appMode, winActive, winMinimized) {
  if (appMode) return winActive ? "active" : "window"
  return winActive ? "active" : (winMinimized ? "minimized" : "window")
}

function plan(windows, running) {
  var total = totalWindows(windows, running)
  var overflow = total > DENSE_AT
  var dots = overflow ? DENSE_AT - 1 : Math.min(total, DENSE_AT)
  return {
    total: total,
    dense: total >= DENSE_AT,
    overflow: overflow,
    dots: dots,
    slots: Math.max(1, dots + (overflow ? 1 : 0))
  }
}
