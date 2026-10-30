import QtQuick 6.11
import Quickshell
import qs.Commons
import "../DockLayout.js" as DockLayout

// Windows 11's clock: the time over the date, in two quiet lines at the far
// right of the taskbar. The bar's own SystemClock updates once a minute, so
// the dock still runs without a polling timer. The width is the constant the
// fit planner reserves for the tray (DockLayout.TASKBAR_CLOCK_WIDTH), which
// keeps the centred app section from growing under it.
Item {
  id: clock

  property var rootRef: null
  readonly property var root: rootRef

  readonly property date now: systemClock.date
  readonly property string timeText: Qt.formatDateTime(clock.now, Qt.locale().timeFormat(Locale.ShortFormat))
  // Windows 11 prints the full year; Qt's short date is often two digits.
  readonly property string dateText: {
    var f = Qt.locale().dateFormat(Locale.ShortFormat)
    if (f.indexOf("yyyy") < 0 && f.indexOf("yy") >= 0) f = f.replace("yy", "yyyy")
    return Qt.formatDateTime(clock.now, f)
  }

  implicitWidth: Style.space(DockLayout.TASKBAR_CLOCK_WIDTH)
  implicitHeight: column.implicitHeight

  // Windows' clock is also the calendar's door; the shell's own clock panel
  // is that calendar, reached through the same IPC its bar uses.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: Quickshell.execDetached(["omarchy-shell", "-q", "omarchy.clock", "toggle"])
  }

  SystemClock {
    id: systemClock
    precision: SystemClock.Minutes
  }

  // Right edges flush with the tray padding, both lines starting at the same
  // x as Windows' clock does (the wider line sets the block's width).
  Column {
    id: column
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)
    width: Math.max(timeLine.implicitWidth, dateLine.implicitWidth)

    Text {
      id: timeLine
      width: parent.width
      text: clock.timeText
      textFormat: Text.PlainText
      color: clock.root ? clock.root.dockForeground : "#f2efec"
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: dateLine
      width: parent.width
      text: clock.dateText
      textFormat: Text.PlainText
      color: clock.root ? clock.root.dockForeground : "#f2efec"
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
}
