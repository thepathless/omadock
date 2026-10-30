import QtQuick 6.11
import qs.Commons
import qs.Ui
import "../DockMarks.js" as DockMarks
import "../DockMarkGeometry.js" as DockMarkGeometry

// The running-indicator row under a dock item: one mark per window — the
// focused window's mark turns into the accent bar, parked windows become
// hollow dots — with dense marks and a compact "+N" pill past five. Apps
// and app groups draw through this one row, so a foldered app's marks can
// never drift from a pinned app's.
//
// Mark count runs on windowList: an app that runs with no window (a launch
// race, a tray-bound player) still shows one mark via `running`.
Item {
  id: marks

  property var rootRef: null
  readonly property var root: rootRef
  property var windows: []
  property bool running: false
  // Fallback for a mark with no window to name: the first mark shows the
  // active bar while the item (or an app group's member) holds the focus.
  property bool focused: false
  // Fallback minimized state for the same case: every window parked.
  property bool allMinimized: false
  property bool urgent: false
  // 0..1 breathing for urgent marks, driven by the item.
  property real pulse: 1.0
  // A column instead of a row (side indicators on a label plate).
  property bool vertical: false
  // Ink when the marks stand on a label plate (transparent: the dock's own).
  property color markInk: "transparent"
  // Passed to each mark (DockIndicator.moveKey).
  property real moveKey: 0

  // How many marks this item has, and how the row draws them, is policy: it
  // comes from DockMarks.js, which the unit tests pin. The dots the repeater
  // repeats, the slots the Grid declares, the pill's visibility and the count
  // it shows all read this one plan, so a declared slot can never outnumber a
  // drawn mark: a Grid reserves a gap for every slot it declares, and a spare
  // one shifted a lone dot (or accent bar) half a gap - 2 px - off the icon's
  // centre.
  readonly property var plan: DockMarks.plan(marks.windows, marks.running)
  // "app" mode speaks for the app, not its windows: one mark while anything is
  // open, the accent bar while the app holds the focus, no "+N" pill. The same
  // plan shape keeps every reader below unchanged.
  readonly property bool appMode: marks.root ? marks.root.indicatorMode === "app" : false
  readonly property var drawPlan: marks.appMode
    ? { total: (marks.running ? 1 : 0), dense: false, overflow: false,
        dots: (marks.running ? 1 : 0), slots: 1 }
    : marks.plan
  // How big a mark is, and how much room it needs, is policy too: it comes from
  // DockMarkGeometry.js, which the unit tests pin, and the indicators and the
  // label's reserved room read the same module. Sizes are on the output's pixel
  // grid (see DockIndicator), so a dot and the accent bar share one centre
  // line: each mark sits in a cell as wide across the row (or column) as the
  // largest mark, centred by whole device pixels. Left to the Grid, the
  // half-pixel offset rounded the bar against one side of the dots.
  readonly property real dpr: marks.root ? marks.root.outputScale : 1
  readonly property real cross: marks.appMode
    ? DockMarkGeometry.dotFor(Style.space, marks.dpr, "app", marks.root ? marks.root.indicatorSize : 0)
    : DockMarkGeometry.cell(Style.space, marks.dpr, marks.plan.dense, marks.vertical)
  readonly property real dynamicSpacing: DockMarkGeometry.rowSpacing(Style.space, marks.dpr, marks.plan.dense)

  visible: marks.running

  // A mark that goes stays one exit long (it shrinks and fades), and a new
  // one grows from nothing (DockMotion).
  readonly property var motion: marks.root ? marks.root.motion : null
  property int shownDots: marks.plan.dots
  Timer {
    id: dotsLater
    interval: marks.motion ? marks.motion.base : 0
    onTriggered: marks.shownDots = marks.plan.dots
  }
  // A plan that changes again while a mark is going (a window title, the
  // focus) does not hold it longer: the exit keeps its own clock.
  onPlanChanged: {
    if (marks.plan.dots >= marks.shownDots || !marks.motion || marks.motion.base <= 0) {
      dotsLater.stop()
      marks.shownDots = marks.plan.dots
    } else if (!dotsLater.running) {
      dotsLater.start()
    }
  }
  width: indicatorRow.width
  height: indicatorRow.height

  function isWinMinimized(w) {
    if (!w || !marks.root) return marks.allMinimized
    return (w.isMinimized === true) || (marks.root.liveWsNameOf(w) === marks.root.minimizedWorkspace)
  }

  function isWinActive(w) {
    if (!w || !w.address || !marks.root || !marks.root.activeWindowAddress) return false
    return w.address === marks.root.activeWindowAddress
  }

  Grid {
    id: indicatorRow
    spacing: marks.dynamicSpacing
    columns: marks.vertical ? 1 : Math.max(marks.drawPlan.slots, marks.drawPlan.dots + (marks.drawPlan.overflow ? 1 : 0))
    rows: marks.vertical ? Math.max(marks.drawPlan.slots, marks.drawPlan.dots + (marks.drawPlan.overflow ? 1 : 0)) : 1
    flow: marks.vertical ? Grid.TopToBottom : Grid.LeftToRight
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter

    Repeater {
      model: marks.drawPlan.dots
      // Active window: accent bar; open window: dot; minimized: hollow dot.
      delegate: Item {
        id: cell
        required property int index
        readonly property var winObj: (marks.windows && marks.windows.length > index) ? marks.windows[index] : null
        readonly property bool winMinimized: winObj ? marks.isWinMinimized(winObj) : marks.allMinimized
        // In app mode the app's own focus decides: any of its windows may be
        // the active one, not just the first window's address.
        readonly property bool winActive: marks.appMode
          ? marks.focused
          : (!winMinimized && ((winObj && winObj.address) ? marks.isWinActive(winObj) : (index === 0 && marks.focused)))

        // Along the row the cell grows and shrinks with its mark, so the
        // others close up as one goes instead of jumping when it is gone.
        readonly property real along: (marks.motion && marks.motion.layout) ? cell.appear : 1
        width: marks.vertical ? marks.cross : mark.width * cell.along
        height: marks.vertical ? mark.height * cell.along : marks.cross

        readonly property bool going: index >= marks.drawPlan.dots
        property real appear: 0
        property bool _settled: false
        // The easing reads the Behavior's target (set before the animation
        // starts); bound to `going` it could start with the old one.
        Behavior on appear {
          id: appearMotion
          enabled: cell._settled && !!marks.motion && marks.motion.fade
          NumberAnimation {
            duration: marks.motion ? marks.motion.base : 0
            easing.type: appearMotion.targetValue > 0.5 ? Easing.OutCubic : Easing.InCubic
          }
        }
        // Written a turn late: in onCompleted the Behavior would not animate.
        Component.onCompleted: Qt.callLater(function() { cell._settled = true; cell.appear = cell.going ? 0 : 1 })
        onGoingChanged: cell.appear = cell.going ? 0 : 1
        // The mark snaps itself to the pixel grid from its scene position,
        // which the grow (scale) and the column closing up shift without
        // moving the mark inside its cell: snapped mid-grow it kept a pixel
        // off its neighbours. Snap again once the cell has settled or moved.
        onAppearChanged: if (cell.appear >= 1) Qt.callLater(mark.resnap)
        onXChanged: Qt.callLater(mark.resnap)
        onYChanged: Qt.callLater(mark.resnap)
        opacity: cell.appear
        scale: (marks.motion && marks.motion.scale) ? 0.4 + 0.6 * cell.appear : 1

        DockIndicator {
          id: mark
          x: Math.round(((marks.vertical ? marks.cross : cell.width) - width) * marks.dpr / 2) / marks.dpr
          y: Math.round(((marks.vertical ? cell.height : marks.cross) - height) * marks.dpr / 2) / marks.dpr
          rootRef: marks.rootRef
          vertical: marks.vertical
          inkOverride: marks.markInk
          kind: DockMarks.markKind(marks.appMode, cell.winActive, cell.winMinimized)
          dense: marks.drawPlan.dense
          urgent: marks.urgent
          pulse: marks.pulse
          moveKey: marks.moveKey
        }
      }
    }

    // Compact overflow pill when 6+ windows are open
    Rectangle {
      visible: marks.drawPlan.overflow
      width: DockMarkGeometry.pillWidth(Style.space, overflowText.implicitWidth)
      height: DockMarkGeometry.pillHeight(Style.space)
      radius: (marks.root && marks.root.indicatorSquare) ? 0 : height / 2
      color: Util.alpha(marks.root ? marks.root.dockForeground : Color.bar.text, 0.20)
      border.color: Qt.rgba(0, 0, 0, 0.35)
      border.width: 1

      Text {
        id: overflowText
        anchors.centerIn: parent
        text: "+" + (marks.plan.total - marks.plan.dots)
        textFormat: Text.PlainText
        color: marks.markInk.a > 0 ? marks.markInk : (marks.root ? marks.root.dockForeground : Color.bar.text)
        font.family: Style.font.family
        font.pixelSize: Math.max(7, Style.font.caption - 4)
        font.bold: true
      }
    }
  }
}
