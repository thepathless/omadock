import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

Item {
  id: item

  property var rootRef: null
  readonly property var root: rootRef
  property var dockCard: root ? root.dockCard : null
  property var appContextMenuColumn: root ? root.appContextMenuColumnRef : null

  property string appId: ""
  property string name: ""
  property string icon: ""
  property bool running: false
  property int windows: 0
  property var windowList: []
  // Minimized windows live as preview tiles on the dock itself, so hover
  // surfaces list only what is actually on screen.
  readonly property var tooltipWindows: root ? root.visibleWindows(windowList || []) : []
  property bool active: false
  property bool pinned: false

  signal activateRequested(string appId)
  signal newWindowRequested(string appId)
  signal menuRequested(string appId, real cx, real cy)
  signal dragStarted(string appId)
  signal dragMoved(string appId, real x)
  signal dragDropped(string appId)
  signal wheelScrolled(string appId, int direction)

  // macOS-style dock layout: Slots maintain constant unmagnified width so the
  // dock shelf background never expands or twitches horizontally. The icon artwork
  // magnifies upwards with natural z-layering and subtle fisheye horizontal offset.
  width: root ? root.iconSlot : 0
  height: root ? root.iconSlot : 0
  z: Math.round(item.magnifyScale * 100)

  property bool isDragging: false
  property bool _dragJustEnded: false
  property real dragStartX: 0
  property real bounceY: 0
  property real homeCenter: 0
  property real magnifyScale: {
    if (!root) return 1
    if (root.waveHover) return root.magnifyScaleAt(item.homeCenter)
    if (root.hoverEffect === "off") return 1
    return (area.containsMouse && !item.isDragging) ? root.zoomPeak : 1
  }

  readonly property real waveNudgeX: root ? root.waveOffsetAt(item.homeCenter) : 0

  readonly property bool isDropTarget: (root && root.dropTargetAppId === item.appId && root.dragAppId !== item.appId)

  Behavior on magnifyScale {
    NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
  }

  // Live window state. The model carries plain primitives, so anything that
  // must be current — urgency, workspace, parked state — resolves through
  // live handle lookups instead of trusting cached values.

  readonly property bool urgent: {
    if (!root || !root.showUrgentHint) return false
    // Foreground Suppression Rule: An app currently focused in the foreground suppresses urgency bounce
    if (item.active || item.isFocused) return false
    // Closed App Invariant: An app that is not running and not actively launching must never bounce
    if (!item.running && !item.starting) return false
    if (item.appId && root.urgentMap && root.urgentMap[item.appId]) return true
    var list = item.windowList || []
    for (var i = 0; i < list.length; i++) {
      var addr = list[i] ? list[i].address : ""
      if (addr && root.urgentMap && root.urgentMap[addr]) return true
    }
    return false
  }

  readonly property bool minimized: root ? DockModel.allWindowsMinimized(item.windowList, root.liveWsNameOf, root.minimizedWorkspace) : false

  readonly property bool onFocusedWorkspace: {
    if (!root) return false
    var list = item.windowList || []
    for (var i = 0; i < list.length; i++) {
      var ws = list[i] ? list[i].workspaceName : ""
      if (ws && (ws === String(root.focusedWorkspaceId) || ws === root.focusedWorkspaceName)) return true
    }
    return false
  }

  // Where a left click would take you, when that is somewhere else.
  readonly property string workspaceHint: {
    if (!item.running || item.minimized || item.onFocusedWorkspace) return ""
    var ws = (item.windowList && item.windowList.length > 0) ? item.windowList[0].workspaceName : ""
    return ws ? DockModel.workspaceShort(ws, ws) : ""
  }

  readonly property bool starting: (root && root.launchPending) ? (root.launchPending[item.appId] !== undefined) : false

  readonly property string tooltipText: {
    if (item.name === "") return ""
    if (item.starting) return item.name + " [starting…]"
    if (item.minimized) return item.name + " [minimized]"
    if (item.workspaceHint !== "") return item.name + " [" + item.workspaceHint + "]"
    return item.name
  }

  // The pulse carries both attention states: urgency, and a launch in
  // progress, where it breathes under the bounce.
  property real pulse: 1.0
  readonly property bool pulsing: item.urgent || item.starting
  onPulsingChanged: if (!item.pulsing) item.pulse = 1.0

  SequentialAnimation on pulse {
    running: item.pulsing
    loops: Animation.Infinite
    NumberAnimation { from: 1.0; to: 0.35; duration: 650; easing.type: Easing.InOutQuad }
    NumberAnimation { from: 0.35; to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
  }

  opacity: item.isDragging ? 0.35 : 1.0
  Behavior on opacity {
    NumberAnimation { duration: 120 }
  }

  readonly property bool bouncing: root ? ((item.starting && root.launchBounce) || (item.urgent && (item.running || item.starting) && root.showUrgentHint)) : false
  onBouncingChanged: if (!item.bouncing) item.bounceY = 0
  onRunningChanged: if (!item.running && !item.starting) item.bounceY = 0

  SequentialAnimation on bounceY {
    running: item.bouncing
    loops: Animation.Infinite
    NumberAnimation { from: 0; to: -Style.space(13); duration: 260; easing.type: Easing.OutQuad }
    NumberAnimation { from: -Style.space(13); to: 0; duration: 260; easing.type: Easing.OutBounce }
    PauseAnimation { duration: item.urgent ? 380 : 220 }
  }

  // The icon carries every state on its own: it grows on hover, dips on
  // press, bounces while starting. No plate, no frame — the only chrome in
  // the slot is the running indicator underneath.
  Item {
    id: iconBox
    anchors.fill: parent
    anchors.bottomMargin: item.running ? Style.space(5) : 0

    scale: area.pressed ? 0.92 : 1.0
    transformOrigin: Item.Bottom
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

    transform: [
      Translate { y: item.bounceY },
      Translate { x: item.waveNudgeX }
    ]

    // Drop target halo for creating an App Folder
    Rectangle {
      visible: item.isDropTarget
      anchors.centerIn: parent
      width: (root ? root.baseIconArt : 32) + Style.space(8)
      height: width
      radius: Style.space(6)
      color: Util.alpha(Color.bar.active, 0.22)
      border.color: Color.bar.active
      border.width: 1.5
      z: -1
      SequentialAnimation on opacity {
        running: item.isDropTarget
        loops: Animation.Infinite
        NumberAnimation { from: 0.5; to: 1.0; duration: 350; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 1.0; to: 0.5; duration: 350; easing.type: Easing.InOutQuad }
      }
    }

    // Sits on the dock floor and grows upward, so a magnified icon never
    // reaches down over the running dot beneath it.
    Image {
      id: iconImg
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.round((iconBox.height - (root ? root.baseIconArt : 32)) / 2)
      width: (root ? root.baseIconArt : 32) * item.magnifyScale
      height: width
      source: {
        var _tv = root ? root.themeVersion : 0
        if (item.icon !== "") return item.icon
        return Quickshell.iconPath("application-x-executable", true)
      }
      sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
      visible: source !== ""
      opacity: item.starting ? (0.4 + 0.6 * item.pulse) : 1.0
      mipmap: true
      smooth: true
    }
  }

  readonly property bool isFocused: {
    if (!root) return false
    if (item.appId && root.activeId && DockModel.isAppMatch(item.appId, root.activeId)) return true
    var list = item.windowList || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].address && list[i].address === root.activeWindowAddress) return true
    }
    return false
  }

  property int selectedWindowIdx: -1

  function isWinMinimized(w) {
    if (!w || !root) return false
    return (w.isMinimized === true) || (root.liveWsNameOf(w) === root.minimizedWorkspace)
  }

  function isWinActive(w) {
    if (!w || !w.address || !root || !root.activeWindowAddress) return false
    return w.address === root.activeWindowAddress
  }

  readonly property int totalWindowCount: (item.windowList && item.windowList.length > 0) ? item.windowList.length : (item.running ? 1 : 0)
  readonly property int maxVisibleDots: totalWindowCount > 5 ? 4 : Math.min(totalWindowCount, 5)
  readonly property real dynamicDotSize: totalWindowCount >= 5 ? Style.space(4) : Style.space(5)
  readonly property real dynamicActiveWidth: totalWindowCount >= 5 ? Style.space(9) : Style.space(12)
  readonly property real dynamicSpacing: totalWindowCount >= 5 ? Style.space(2) : Style.space(3)

  // Fixed at the slot bottom, never scaled or pushed out of the dock.
  Row {
    id: indicatorRow
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(1)
    spacing: item.dynamicSpacing
    visible: item.running
    z: 2

    Repeater {
      model: item.maxVisibleDots
      delegate: Rectangle {
        readonly property var winObj: (item.windowList && item.windowList.length > index) ? item.windowList[index] : null
        readonly property bool winMinimized: winObj ? item.isWinMinimized(winObj) : item.minimized
        readonly property bool winActive: !winMinimized && ((winObj && winObj.address) ? item.isWinActive(winObj) : (index === 0 && item.isFocused))

        width: winActive ? item.dynamicActiveWidth : item.dynamicDotSize
        height: winActive ? Style.space(4) : item.dynamicDotSize
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter

        // 1. Active window: Solid illuminated bar
        // 2. Open visible window: Solid circle
        // 3. Minimized window: Hollow circle (transparent fill with solid border)
        color: winActive
          ? Color.bar.active
          : (winMinimized
              ? "transparent"
              : (item.urgent ? Color.urgent : Util.alpha(root ? root.dockForeground : Color.bar.text, 0.88)))

        border.color: winActive
          ? Qt.rgba(0, 0, 0, 0.45)
          : (winMinimized
              ? (item.urgent ? Color.urgent : Util.alpha(root ? root.dockForeground : Color.bar.text, 0.88))
              : Qt.rgba(0, 0, 0, 0.45))

        border.width: winMinimized ? 1.5 : 1

        opacity: item.urgent ? (0.4 + 0.6 * item.pulse) : 1.0

        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
      }
    }

    // Compact overflow pill when 6+ windows are open
    Rectangle {
      visible: item.totalWindowCount > 5
      width: overflowText.implicitWidth + Style.space(4)
      height: Style.space(5)
      radius: height / 2
      anchors.verticalCenter: parent.verticalCenter
      color: Util.alpha(root ? root.dockForeground : Color.bar.text, 0.20)
      border.color: Qt.rgba(0, 0, 0, 0.35)
      border.width: 1

      Text {
        id: overflowText
        anchors.centerIn: parent
        text: "+" + (item.totalWindowCount - item.maxVisibleDots)
        textFormat: Text.PlainText
        color: root ? root.dockForeground : Color.bar.text
        font.family: Style.font.family
        font.pixelSize: Math.max(7, Style.font.caption - 4)
        font.bold: true
      }
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: item.isDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onWheel: function(wheel) {
      if (wheel.angleDelta.y !== 0) {
        var dir = wheel.angleDelta.y > 0 ? -1 : 1
        var wins = item.tooltipWindows || []
        if (wins.length > 1) {
          var cur = 0
          if (item.selectedWindowIdx < 0) {
            for (var c = 0; c < wins.length; c++) {
              if (root && root.isWindowFocused(wins[c])) { cur = c; break; }
            }
            item.selectedWindowIdx = (cur + dir + wins.length) % wins.length
          } else {
            item.selectedWindowIdx = (item.selectedWindowIdx + dir + wins.length) % wins.length
          }

          // If context menu is open for this app, synchronize its selection
          if (root && root.contextAppId === item.appId) {
            try { appContextMenuColumn.selectedWindowIdx = item.selectedWindowIdx } catch (e) {}
            return
          }

          itemTooltip.shown = true
        } else {
          item.wheelScrolled(item.appId, dir)
        }
      }
    }

    onPressed: function(mouse) {
      if (mouse.button === Qt.LeftButton && (item.pinned || item.running)) {
        item.dragStartX = mouse.x
        item.isDragging = false
        item._dragJustEnded = false
      }
    }

    onPositionChanged: function(mouse) {
      if (area.pressed && mouse.buttons & Qt.LeftButton && (item.pinned || item.running)) {
        var dist = Math.abs(mouse.x - item.dragStartX)
        if (!item.isDragging && dist > 8) {
          item.isDragging = true
          item.dragStarted(item.appId)
        }
        if (item.isDragging) {
          var pt = dockCard ? item.mapToItem(dockCard, mouse.x, 0) : null
          item.dragMoved(item.appId, pt ? pt.x : mouse.x)
        }
      }
    }

    onReleased: function(mouse) {
      if (item.isDragging) {
        item.isDragging = false
        item._dragJustEnded = true
        item.dragDropped(item.appId)
      }
    }

    onCanceled: {
      if (item.isDragging) {
        item.isDragging = false
        item._dragJustEnded = true
        item.dragDropped(item.appId)
      }
    }

    onClicked: function(mouse) {
      if (item._dragJustEnded) {
        item._dragJustEnded = false
        return
      }
      if (mouse.button === Qt.RightButton) {
        var targetWin = root ? root.contentItemRef : null
        var pt = targetWin ? item.mapToItem(targetWin, item.width / 2, 0) : null
        var gx = pt ? pt.x : (item.width / 2)
        item.menuRequested(item.appId, gx, 0)
      } else if (mouse.button === Qt.MiddleButton) {
        item.newWindowRequested(item.appId)
      } else if (mouse.button === Qt.LeftButton) {
        // If context menu is open for this app:
        if (root && root.contextAppId === item.appId) {
          var chosenIdx = item.selectedWindowIdx
          try {
            if (appContextMenuColumn && appContextMenuColumn.selectedWindowIdx >= 0) {
              chosenIdx = appContextMenuColumn.selectedWindowIdx
            }
          } catch (e) {}

          if (chosenIdx >= 0 && item.windowList && chosenIdx < item.windowList.length) {
            var chosenWin = item.windowList[chosenIdx]
            if (chosenWin && chosenWin.address) {
              root.focusWindowByAddress(chosenWin.address, item.appId)
            }
          }
          item.selectedWindowIdx = -1
          try { appContextMenuColumn.selectedWindowIdx = -1 } catch (e2) {}
          root.closeContext()
          return
        }

        // If a specific window was selected via scroll wheel in tooltip:
        if (item.selectedWindowIdx >= 0 && item.tooltipWindows && item.selectedWindowIdx < item.tooltipWindows.length) {
          var chosenWin2 = item.tooltipWindows[item.selectedWindowIdx]
          if (chosenWin2 && chosenWin2.address && root) {
            root.focusWindowByAddress(chosenWin2.address, item.appId)
          }
          item.selectedWindowIdx = -1
          return
        }
        item.activateRequested(item.appId)
      }
    }
  }

  BorderSurface {
    id: itemTooltip
    property bool shown: false
    readonly property bool wanted: area.containsMouse && !item.isDragging
      && item.name !== "" && (root ? (root.showTooltips && root.contextAppId === "") : true)
    visible: itemTooltip.shown && itemTooltip.wanted
    z: 300
    color: Color.tooltip.background
    borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
    padding: Style.space(6)
    x: (item.width - width) / 2
    y: -height - Style.space(10)
    width: tooltipContent.implicitWidth + contentLeftInset + contentRightInset
    height: tooltipContent.implicitHeight + contentTopInset + contentBottomInset

    onWantedChanged: {
      if (itemTooltip.wanted) tooltipDwell.restart()
      else {
        tooltipDwell.stop()
        itemTooltip.shown = false
        if (root && root.contextAppId !== item.appId) {
          item.selectedWindowIdx = -1
        }
      }
    }

    Timer {
      id: tooltipDwell
      interval: root ? root.tooltipDelay : 450
      onTriggered: itemTooltip.shown = true
    }

    Column {
      id: tooltipContent
      x: parent.contentLeftInset
      y: parent.contentTopInset
      spacing: Style.space(3)

      Text {
        text: item.tooltipText !== "" ? item.tooltipText : item.name
        textFormat: Text.PlainText
        color: Color.tooltip.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: root ? (root.advancedTooltips && item.running) : false
        horizontalAlignment: Text.AlignHCenter
        anchors.horizontalCenter: parent.horizontalCenter
      }

      Repeater {
        model: (root && root.advancedTooltips && item.tooltipWindows.length > 0)
          ? Math.min(item.tooltipWindows.length, 8) : 0
        delegate: Row {
          spacing: Style.space(5)
          anchors.horizontalCenter: parent.horizontalCenter
          readonly property bool isSelected: item.selectedWindowIdx === index
          readonly property bool isWinFocused: item.isWinActive(item.tooltipWindows[index])

          Rectangle {
            width: Style.space(5)
            height: Style.space(5)
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: isSelected ? Color.accent : (isWinFocused ? Color.bar.active : Util.alpha(Color.tooltip.text, 0.5))
            border.color: isSelected ? Color.accent : "transparent"
            border.width: 1
          }

          Text {
            text: {
              var w = item.tooltipWindows[index]
              var t = (w && root) ? root.windowRowLabel(w) : ""
              var prefix = isSelected ? "› " : ""
              var str = prefix + t
              return str.length > 32 ? str.slice(0, 30) + "…" : str
            }
            textFormat: Text.PlainText
            color: isSelected ? Color.accent : (isWinFocused ? Color.tooltip.text : Util.alpha(Color.tooltip.text, 0.80))
            font.family: Style.font.family
            font.pixelSize: Math.max(10, Style.font.caption - 1)
            font.bold: isSelected || isWinFocused
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }
      }

      Text {
        visible: root ? (root.advancedTooltips && item.tooltipWindows.length > 8) : false
        anchors.horizontalCenter: parent.horizontalCenter
        text: "+" + (item.tooltipWindows.length - 8) + " more"
        textFormat: Text.PlainText
        color: Util.alpha(Color.tooltip.text, 0.6)
        font.family: Style.font.family
        font.pixelSize: Math.max(9, Style.font.caption - 3)
      }
    }
  }
}
