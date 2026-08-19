// omadock — centered autohiding app dock with drag reorder, multi-window
// management, workspace hints, and intelligent scale-aware autohide.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

Item {
  id: root

  // ----------------------------------------------------- inline components

  // Hover bubble with a dwell delay, so sweeping the pointer across the dock
  // does not flash a label for every icon it passes.
  component HoverTooltip: BorderSurface {
    id: bubble

    property string text: ""
    property bool hovered: false
    property bool blocked: false
    property bool shown: false

    visible: bubble.shown && bubble.text !== "" && root.showTooltips
      && !bubble.blocked && root.contextAppId === ""
    z: 300
    color: Color.tooltip.background
    borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
    radius: Style.cornerRadius
    padding: Style.space(4)
    width: bubbleLabel.implicitWidth + contentLeftInset + contentRightInset
    height: bubbleLabel.implicitHeight + contentTopInset + contentBottomInset

    onHoveredChanged: {
      if (bubble.hovered) dwell.restart()
      else {
        dwell.stop()
        bubble.shown = false
      }
    }

    onBlockedChanged: if (bubble.blocked) {
      dwell.stop()
      bubble.shown = false
    }

    Timer {
      id: dwell
      interval: root.tooltipDelay
      onTriggered: bubble.shown = true
    }

    Text {
      id: bubbleLabel
      x: bubble.contentLeftInset
      y: bubble.contentTopInset
      width: bubble.width - bubble.contentLeftInset - bubble.contentRightInset
      text: bubble.text
      color: Color.tooltip.text
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }
  }

  component DockItem: Item {
    id: item

    property string appId: ""
    property string name: ""
    property string icon: ""
    property bool running: false
    property int windows: 0
    property var windowList: []
    property bool active: false
    property bool pinned: false

    signal activateRequested(string appId)
    signal newWindowRequested(string appId)
    signal menuRequested(string appId, real cx, real cy)
    signal dragStarted(string appId)
    signal dragMoved(string appId, real x)
    signal dragDropped(string appId)
    signal wheelScrolled(string appId, int direction)

    width: root.iconSlot
    height: root.iconSlot

    property bool isDragging: false
    property bool _dragJustEnded: false
    property real dragStartX: 0
    property real bounceY: 0
    readonly property bool isHovered: area.containsMouse && !item.isDragging

    // Live window state, read straight off the Hyprland handles carried in the
    // model, so urgency and workspace moves land without a model rebuild.

    readonly property bool urgent: {
      if (!root.showUrgentHint) return false
      var list = item.windowList
      for (var i = 0; i < list.length; i++) {
        var handle = list[i] ? list[i].hypr : null
        if (handle && handle.urgent) return true
      }
      return false
    }

    readonly property bool minimized: {
      var list = item.windowList
      if (list.length === 0) return false
      for (var i = 0; i < list.length; i++) {
        var handle = list[i] ? list[i].hypr : null
        var ws = handle ? handle.workspace : null
        if (!ws || ws.name !== root.minimizedWorkspace) return false
      }
      return true
    }

    readonly property bool onFocusedWorkspace: {
      var list = item.windowList
      for (var i = 0; i < list.length; i++) {
        var handle = list[i] ? list[i].hypr : null
        var ws = handle ? handle.workspace : null
        if (ws && ws.id === root.focusedWorkspaceId) return true
      }
      return false
    }

    // Where a left click would take you, when that is somewhere else.
    readonly property string workspaceHint: {
      if (!item.running || item.minimized || item.onFocusedWorkspace) return ""
      var handle = item.windowList.length > 0 ? item.windowList[0].hypr : null
      var ws = handle ? handle.workspace : null
      return ws ? DockModel.workspaceShort(ws.id, ws.name) : ""
    }

    readonly property bool starting: root.launchPending[item.appId] !== undefined

    readonly property string tooltipText: {
      if (item.name === "") return ""
      if (item.starting) return item.name + " [starting…]"
      if (item.minimized) return item.name + " [minimized]"
      if (item.workspaceHint !== "") return item.name + " [" + item.workspaceHint + "]"
      return item.name
    }

    // One pulse drives both attention states: urgency and a cold start.
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

    SequentialAnimation {
      id: bounceAnim
      running: false
      alwaysRunToEnd: true
      NumberAnimation { target: item; property: "bounceY"; to: -Style.space(14); duration: 130; easing.type: Easing.OutQuad }
      NumberAnimation { target: item; property: "bounceY"; to: 0; duration: 130; easing.type: Easing.InQuad }
      NumberAnimation { target: item; property: "bounceY"; to: -Style.space(7); duration: 90; easing.type: Easing.OutQuad }
      NumberAnimation { target: item; property: "bounceY"; to: 0; duration: 90; easing.type: Easing.InQuad }
    }

    // 1. Icon Box: Only the icon scales on hover and bounces on click
    Item {
      id: iconBox
      anchors.fill: parent
      anchors.bottomMargin: item.running ? Style.space(5) : 0

      scale: root.magnification && item.isHovered ? 1.20 : 1.0
      property real hoverLift: root.magnification && item.isHovered ? -Style.space(6) : 0
      y: hoverLift

      Behavior on scale {
        NumberAnimation { duration: 130; easing.type: Easing.OutQuad }
      }
      Behavior on hoverLift {
        NumberAnimation { duration: 130; easing.type: Easing.OutQuad }
      }

      transform: Translate {
        y: item.bounceY
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(2)
        radius: (root.dockShape === "round" || root.dockShape === "pill")
          ? width / 2
          : (root.dockShape === "square" ? 0 : ((root.dockShape === "theme" || root.dockShape === "auto") ? Math.max(4, Math.round(Style.cornerRadius * 0.6)) : 8))
        color: area.containsMouse
          ? (area.pressed ? Style.pressedFill : Style.hoverFill)
          : (item.active ? Style.selectedFill : "transparent")
        border.color: area.containsMouse
          ? Style.hoverBorderColor
          : (item.urgent ? Util.alpha(Color.urgent, 0.3 + 0.6 * item.pulse) : "transparent")
        border.width: Style.hoverBorderWidth

        Image {
          id: iconImg
          anchors.centerIn: parent
          width: root.iconSize - Style.space(10)
          height: width
          source: item.icon !== "" ? item.icon : Quickshell.iconPath("application-x-executable", true)
          sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
          visible: source !== ""
          opacity: item.starting ? item.pulse : 1.0
          mipmap: true
          smooth: true
        }
      }
    }

    // 2. Running Indicator Dots: Fixed at slot bottom, never scaled or pushed out of dock
    Row {
      id: indicatorRow
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(1)
      spacing: Style.space(2)
      visible: item.running
      z: 2

      Rectangle {
        width: (item.active || item.urgent) ? Style.space(7) : Style.space(4)
        height: (item.active || item.urgent) ? Style.space(3) : Style.space(2)
        radius: height / 2
        color: item.urgent
          ? Color.urgent
          : (item.active ? Color.bar.active : Util.alpha(root.dockForeground, item.minimized ? 0.28 : 0.6))
        opacity: item.urgent ? (0.4 + 0.6 * item.pulse) : 1.0
      }

      // Secondary dot for multiple open windows
      Rectangle {
        visible: item.windows > 1
        width: Style.space(3)
        height: Style.space(2)
        radius: height / 2
        color: item.urgent
          ? Color.urgent
          : (item.active ? Color.bar.active : Util.alpha(root.dockForeground, item.minimized ? 0.22 : 0.45))
        opacity: item.urgent ? (0.4 + 0.6 * item.pulse) : 1.0
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
          item.wheelScrolled(item.appId, dir)
        }
      }

      onPressed: function(mouse) {
        if (mouse.button === Qt.LeftButton && item.pinned) {
          item.dragStartX = mouse.x
          item.isDragging = false
          item._dragJustEnded = false
        }
      }

      onPositionChanged: function(mouse) {
        if (area.pressed && mouse.buttons & Qt.LeftButton && item.pinned) {
          var dist = Math.abs(mouse.x - item.dragStartX)
          if (!item.isDragging && dist > 8) {
            item.isDragging = true
            item.dragStarted(item.appId)
          }
          if (item.isDragging) {
            var pt = item.mapToItem(dockCard, mouse.x, 0)
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
          var pt = item.mapToItem(dockCard, item.width / 2, 0)
          var gx = dockCard.x + (pt ? pt.x : (item.x + item.width / 2))
          item.menuRequested(item.appId, gx, 0)
        } else if (mouse.button === Qt.MiddleButton) {
          item.newWindowRequested(item.appId)
        } else if (mouse.button === Qt.LeftButton) {
          if (root.launchBounce) bounceAnim.restart()
          item.activateRequested(item.appId)
        }
      }
    }

    BorderSurface {
      id: itemTooltip
      property bool shown: false
      visible: itemTooltip.shown && item.name !== "" && root.showTooltips && !item.isDragging && root.contextAppId === ""
      z: 300
      color: Color.tooltip.background
      borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
      padding: Style.space(6)
      x: (item.width - width) / 2
      y: -height - Style.space(10)
      width: tooltipContent.implicitWidth + contentLeftInset + contentRightInset
      height: tooltipContent.implicitHeight + contentTopInset + contentBottomInset

      Connections {
        target: area
        function onContainsMouseChanged() {
          if (area.containsMouse && !item.isDragging) tooltipDwell.restart()
          else {
            tooltipDwell.stop()
            itemTooltip.shown = false
          }
        }
      }

      Timer {
        id: tooltipDwell
        interval: root.tooltipDelay
        onTriggered: itemTooltip.shown = true
      }

      Column {
        id: tooltipContent
        x: parent.contentLeftInset
        y: parent.contentTopInset
        spacing: Style.space(3)

        Text {
          text: item.tooltipText !== "" ? item.tooltipText : item.name
          color: Color.tooltip.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: root.advancedTooltips && item.running
          horizontalAlignment: Text.AlignHCenter
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Repeater {
          model: (root.advancedTooltips && item.windowList && item.windowList.length > 0) ? Math.min(item.windowList.length, 3) : 0
          delegate: Row {
            spacing: Style.space(4)
            anchors.horizontalCenter: parent.horizontalCenter
            Rectangle {
              width: Style.space(4)
              height: Style.space(4)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: (item.windowList[index] && item.windowList[index].activated) ? Color.bar.active : Util.alpha(Color.tooltip.text, 0.4)
            }
            Text {
              text: {
                var w = item.windowList[index]
                var t = w ? root.windowRowLabel(w) : ""
                return t.length > 30 ? t.slice(0, 28) + "…" : t
              }
              color: (item.windowList[index] && item.windowList[index].activated) ? Color.tooltip.text : Util.alpha(Color.tooltip.text, 0.75)
              font.family: Style.font.family
              font.pixelSize: Math.max(10, Style.font.caption - 2)
              elide: Text.ElideRight
              maximumLineCount: 1
            }
          }
        }
      }
    }
  }

  component DockIconButton: Item {
    id: btn

    property string glyph: ""
    property string tooltip: ""
    property color glyphColor: root.dockForeground
    property real glyphSize: root.iconSize * 0.42
    signal pressed()
    signal menuRequested(real x, real y)

    width: root.iconSlot
    height: root.iconSlot

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      radius: (root.dockShape === "round" || root.dockShape === "pill")
        ? width / 2
        : (root.dockShape === "square" ? 0 : ((root.dockShape === "theme" || root.dockShape === "auto") ? Math.max(4, Math.round(Style.cornerRadius * 0.6)) : 8))
      color: area.containsMouse ? (area.pressed ? Style.pressedFill : Style.hoverFill) : "transparent"
      border.color: area.containsMouse ? Style.hoverBorderColor : "transparent"
      border.width: Style.hoverBorderWidth

      Text {
        anchors.centerIn: parent
        text: btn.glyph
        font.family: "omarchy"
        font.pixelSize: btn.glyphSize
        color: btn.glyphColor
        scale: root.magnification && area.containsMouse ? 1.15 : 1.0
        Behavior on scale {
          NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
        }
      }
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          var pt = btn.mapToItem(dockCard, btn.width / 2, 0)
          var gx = dockCard.x + (pt ? pt.x : (btn.x + btn.width / 2))
          btn.menuRequested(gx, 0)
        } else {
          btn.pressed()
        }
      }
    }

    HoverTooltip {
      text: btn.tooltip
      hovered: area.containsMouse
      x: (btn.width - width) / 2
      y: -height - Style.space(8)
    }
  }

  component ContextRow: Item {
    id: crow

    property string text: ""
    property string glyph: ""
    property bool checked: false
    property color textColor: Color.menu.text
    property bool danger: false
    property bool isHeader: false
    signal triggered()

    // Rows ask for what they need, then all get drawn at the menu's width, so
    // hover and checked fills line up down the menu instead of stepping in and
    // out with the length of each label.
    readonly property bool isMenuContent: true
    readonly property real markWidth: Style.space(14)

    implicitWidth: Math.max(180, Style.space(8) + crow.markWidth + Style.space(6)
      + label.implicitWidth + Style.space(8))
    width: contextMenu.rowWidth > 0 ? contextMenu.rowWidth : crow.implicitWidth
    height: crow.isHeader ? Math.max(22, Style.space(22)) : Math.max(28, Style.space(28))

    Rectangle {
      anchors.fill: parent
      visible: !crow.isHeader
      radius: Style.cornerRadius
      color: area.containsMouse
        ? (crow.danger ? Util.alpha(Color.urgent, 0.16) : Color.menu.selectedBackground)
        : (crow.checked ? Util.alpha(Color.bar.active, 0.12) : "transparent")
    }

    Row {
      id: content
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      // The mark column is always reserved, so labels stay on one left edge and
      // a row keeps its width when it gets checked.
      Text {
        id: mark
        width: crow.markWidth
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        opacity: (crow.glyph !== "" || crow.checked) ? 1 : 0
        text: crow.glyph !== "" ? crow.glyph : "\ue92b"
        font.family: "omarchy"
        font.pixelSize: Style.font.caption
        color: crow.checked ? Color.bar.active : (crow.isHeader ? Util.alpha(Color.menu.text, 0.5) : crow.textColor)
      }

      Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        width: content.width - mark.width - content.spacing
        text: crow.text
        color: crow.isHeader
          ? Util.alpha(Color.menu.text, 0.5)
          : (crow.checked ? Color.bar.active : (area.containsMouse && crow.danger ? Color.urgent : crow.textColor))
        font.family: Style.font.family
        font.pixelSize: crow.isHeader ? Style.font.caption : Style.font.body
        font.weight: (crow.isHeader || crow.checked) ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: area
      anchors.fill: parent
      enabled: !crow.isHeader
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: crow.triggered()
    }
  }

  // -------------------------------------------------- shell integration

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  readonly property string dockPath: Quickshell.env("HOME") + "/.config/omarchy/dock.json"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/omadock.json"
  readonly property string legacyConfigPath: Quickshell.env("HOME") + "/.config/omarchy/suva.dock.json"

  property string screenName: ""
  readonly property var dockScreen: root.screenName
    ? root.screenForName(root.screenName)
    : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

  function screenForName(name) {
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++)
      if (list[i].name === name) return list[i]
    return null
  }

  readonly property var appLibrary: shell ? shell.appLibrary : null

  // ------------------------------------------------- contrast

  // The bar foreground is tuned for the bar's own background. A custom dock
  // colour can land on the same side of the scale — a light theme's dark text
  // on a dark card, or the reverse — so flip only when the two collide.
  function isLight(value) {
    return (0.2126 * value.r + 0.7152 * value.g + 0.0722 * value.b) > 0.5
  }

  readonly property color dockForeground: {
    var custom = String(root.dockBgColor || "")
    if (custom.charAt(0) !== "#") return Color.bar.text

    var cardIsLight = root.isLight(Qt.color(custom))
    if (cardIsLight !== root.isLight(Color.bar.text)) return Color.bar.text
    return cardIsLight ? "#12100f" : "#f2efec"
  }

  // ------------------------------------------------- sizing

  property int configuredIconSize: 0
  readonly property int iconSize: root.configuredIconSize > 0
    ? root.configuredIconSize
    : Math.max(28, Math.round(Style.bar.sizeHorizontal * 0.9))
  readonly property int iconSlot: root.iconSize + Style.space(10)

  // ------------------------------------------------- model

  property var pinnedIds: []
  property var appRows: []
  property var dockModel: ({ pinned: [], running: [] })
  readonly property var pinnedSection: root.dockModel.pinned || []
  readonly property var runningSection: root.dockModel.running || []

  function refreshDock() {
    root.dockModel = root.shell && root.shell.appLibrary
      ? DockModel.buildEntries(root.pinnedIds, ToplevelManager.toplevels.values, root.appRows,
                               root.shell.appLibrary, root.hyprToplevelFor)
      : { pinned: [], running: [] }
    root.pruneLaunching()
    root.pruneMinimized()
  }

  readonly property string activeId: ToplevelManager.activeToplevel
    ? DockModel.normalizeId(ToplevelManager.activeToplevel.appId)
    : ""

  readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace
    ? Hyprland.focusedWorkspace.id
    : -99999

  // Hyprland has no minimize, so a window is parked on its own hidden special
  // workspace. The workspace name is the state, which means it survives a shell
  // restart; only the origin workspace is remembered here, and losing it just
  // means the window comes back to wherever you are.
  readonly property string minimizedWorkspace: "special:minimized"
  property var minimizedOrigins: ({})

  // Apps whose launch has been asked for but whose window has not shown up yet.
  property var launchPending: ({})
  readonly property int launchTimeout: 12000

  // ------------------------------------------------- drag reorder state

  property string dragAppId: ""
  property string dropBeforeId: ""
  property real dropIndicatorX: 0

  // ------------------------------------------------- context menu

  property string contextAppId: ""
  property string contextName: ""
  property bool contextPinned: false
  property int contextWindows: 0
  property var contextWindowList: []
  property real contextX: 0
  property real contextY: 0

  // ------------------------------------------------- configuration options

  property bool autohide: true
  property bool intelligentAutohide: true
  property bool showAppsButton: true
  property bool showTooltips: true
  property bool magnification: true
  property bool launchBounce: true
  property bool advancedTooltips: true
  property real dockOpacity: 1.0
  property string dockShape: "rounded"
  property string dockBgColor: "theme"
  property int itemSpacing: 4
  property bool clickToMinimize: false
  property bool showUrgentHint: true
  property int revealDelay: 160
  property int tooltipDelay: 450
  property string settingsSubmenu: ""

  // ------------------------------------------------- autohide state

  property bool dockVisible: false
  readonly property int revealHeight: 6

  property bool windowsOverlapDock: false

  Timer {
    id: hideTimer
    interval: 350
    onTriggered: root.dockVisible = false
  }

  // Dwell on the screen edge before revealing, so a pointer travelling to the
  // bottom of a window does not summon the dock on its way past.
  Timer {
    id: revealTimer
    interval: root.revealDelay
    onTriggered: root.dockVisible = true
  }

  // Coalesces model rebuilds: several signals can describe one window change.
  Timer {
    id: modelTimer
    interval: 40
    onTriggered: root.refreshDock()
  }

  Timer {
    id: launchPruneTimer
    interval: 500
    repeat: true
    onTriggered: root.pruneLaunching()
  }

  // Reactive, debounced overlap check — zero CPU polling loops
  Timer {
    id: debounceOverlapTimer
    interval: 60
    repeat: false
    onTriggered: {
      if (root.autohide && root.intelligentAutohide) {
        overlapProc.running = true
      }
    }
  }

  // Periodic safety check while dock is visible on desktop to catch live window drag/moves
  Timer {
    id: intelligentOverlapCheckTimer
    interval: 350
    repeat: true
    running: root.autohide && root.intelligentAutohide && root.dockVisible && !(cardHover && cardHover.hovered) && !(revealHover && revealHover.hovered) && root.contextAppId === "" && root.dragAppId === ""
    onTriggered: overlapProc.running = true
  }

  Process {
    id: overlapProc
    command: ["hyprctl", "-j", "clients"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var clients = []
        try {
          clients = JSON.parse(this.text) || []
        } catch (e) {
          return
        }

        // Logical monitor dimensions accounting for fractional scaling
        var mon = Hyprland.focusedMonitor
        var scale = (mon && mon.scale > 0)
          ? mon.scale
          : (dockScreen && dockScreen.devicePixelRatio ? dockScreen.devicePixelRatio : 1.0)
        var screenLogicalW = (mon && mon.width > 0)
          ? (mon.width / scale)
          : (dockScreen ? dockScreen.width : 1920)
        var screenLogicalH = (mon && mon.height > 0)
          ? (mon.height / scale)
          : (dockScreen ? dockScreen.height : 1080)

        var cardW = dockCard.width > 0 ? (dockCard.width + Style.gapsOut * 2) : 320
        var cardH = dockCard.height > 0 ? (dockCard.height + Style.gapsOut * 2) : 60
        var dockLeft = (screenLogicalW - cardW) / 2
        var dockRight = (screenLogicalW + cardW) / 2
        var dockTop = screenLogicalH - cardH - 12
        var dockBottom = screenLogicalH

        var overlap = false
        var focusedWsId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

        for (var i = 0; i < clients.length; i++) {
          var c = clients[i]
          if (!c.mapped || c.hidden) continue
          if (!c.workspace || c.workspace.id !== focusedWsId) continue

          var at = c.at
          var sz = c.size
          if (!at || !sz || at.length < 2 || sz.length < 2) continue

          var winLeft = at[0]
          var winTop = at[1]
          var winRight = at[0] + sz[0]
          var winBottom = at[1] + sz[1]

          // 2D Axis-Aligned Bounding Box (AABB) intersection check with dock area
          var intersectsX = (winRight >= dockLeft) && (winLeft <= dockRight)
          var intersectsY = (winBottom >= dockTop) && (winTop <= dockBottom)

          if (intersectsX && intersectsY) {
            overlap = true
            break
          }
        }

        root.windowsOverlapDock = overlap
      }
    }
  }

  function syncVisibility() {
    // Mode 1: Always Show
    if (!root.autohide) {
      hideTimer.stop()
      revealTimer.stop()
      root.dockVisible = true
      return
    }

    var isHovered = (cardHover && cardHover.hovered) || (revealHover && revealHover.hovered) || root.contextAppId !== "" || root.dragAppId !== ""

    // Hovered, Context Menu Open, or Dragging: keep visible
    if (isHovered) {
      hideTimer.stop()
      if (root.dockVisible) revealTimer.stop()
      else if (!revealTimer.running) revealTimer.restart()
      return
    }

    revealTimer.stop()

    // Mode 3: Intelligent Autohide without window overlap -> stay visible on empty desktop
    if (root.intelligentAutohide && !root.windowsOverlapDock) {
      hideTimer.stop()
      root.dockVisible = true
      return
    }

    // Standard Autohide OR Intelligent Autohide with overlapping window -> hide after delay
    if (root.dockVisible) {
      hideTimer.restart()
    }
  }

  onContextAppIdChanged: root.syncVisibility()
  onDragAppIdChanged: root.syncVisibility()
  onAutohideChanged: root.syncVisibility()
  onIntelligentAutohideChanged: {
    if (root.intelligentAutohide) debounceOverlapTimer.restart()
    root.syncVisibility()
  }
  onWindowsOverlapDockChanged: root.syncVisibility()

  // ------------------------------------------------- file views

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    onLoaded: root.loadConfig()
    onFileChanged: configFile.reload()
  }

  FileView {
    id: dockFile
    path: root.dockPath
    watchChanges: true
    atomicWrites: true
    onLoaded: root.loadPinned()
    onFileChanged: dockFile.reload()
  }

  // ------------------------------------------------- reactive event connections

  Connections {
    target: root.appLibrary
    enabled: target !== null
    function onAppsChanged() { root.rescanApps() }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() {
      modelTimer.restart()
      debounceOverlapTimer.restart()
    }
  }

  // Hyprland resolves its own handle for a window slightly apart from the
  // Wayland announcement; rebuilding on both is what keeps the handles attached.
  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { modelTimer.restart() }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      debounceOverlapTimer.restart()
    }
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      debounceOverlapTimer.restart()
    }
    function onRawEvent(event) {
      var n = String((event && event.name) || "")
      if (n === "workspace" || n === "workspacev2" || n === "openwindow" || n === "closewindow" ||
          n === "movewindow" || n === "movewindowv2" || n === "activewindow" || n === "activewindowv2" ||
          n === "changefloatingmode" || n === "fullscreen" || n === "pin" || n === "focusedmon") {
        debounceOverlapTimer.restart()
      }
      if (n === "openwindow" || n === "closewindow") modelTimer.restart()
    }
  }

  onShellChanged: root.rescanApps()
  onPinnedIdsChanged: root.refreshDock()

  // ------------------------------------------------- functions

  function loadPinned() {
    root.pinnedIds = DockModel.parsePinned(dockFile.text())
  }

  function loadConfig() {
    var raw = String(configFile.text() || "").trim()
    var parsed = {}
    if (raw) {
      try {
        parsed = JSON.parse(raw)
      } catch (e) {
        parsed = {}
      }
    }
    root.autohide = parsed && parsed.autohide !== false
    root.intelligentAutohide = parsed && parsed.intelligentAutohide !== false
    root.showAppsButton = parsed && parsed.showAppsButton !== false
    root.showTooltips = parsed && parsed.showTooltips !== false
    root.magnification = parsed && parsed.magnification !== false
    root.launchBounce = parsed && parsed.launchBounce !== false
    root.advancedTooltips = parsed && parsed.advancedTooltips !== false
    root.screenName = parsed && typeof parsed.screen === "string" ? parsed.screen : ""
    root.configuredIconSize = parsed && typeof parsed.iconSize === "number" ? parsed.iconSize : 0
    root.dockOpacity = parsed && typeof parsed.opacity === "number" ? Math.max(0.0, Math.min(1.0, parsed.opacity)) : 1.0
    root.dockShape = parsed && typeof parsed.shape === "string" ? parsed.shape : "rounded"
    root.dockBgColor = parsed && typeof parsed.bgColor === "string" ? parsed.bgColor : "theme"
    root.itemSpacing = parsed && typeof parsed.itemSpacing === "number" ? parsed.itemSpacing : 4
    root.clickToMinimize = !!(parsed && parsed.clickToMinimize === true)
    root.showUrgentHint = parsed ? parsed.showUrgentHint !== false : true
    root.revealDelay = parsed && typeof parsed.revealDelay === "number"
      ? Math.max(0, Math.min(2000, Math.round(parsed.revealDelay)))
      : 160
    root.tooltipDelay = parsed && typeof parsed.tooltipDelay === "number"
      ? Math.max(0, Math.min(5000, Math.round(parsed.tooltipDelay)))
      : 450
  }

  function rescanApps() {
    root.appRows = root.shell && root.shell.appLibrary ? root.shell.appLibrary.sortedEntries("") : []
    root.refreshDock()
  }

  function toggleAppsMenu() {
    if (root.shell) root.shell.toggle("omarchy.menu", '{"menu":"apps"}')
  }

  function openDockSettingsMenu(x, y) {
    root.contextName = "Dock Settings"
    root.contextWindows = 0
    root.contextWindowList = []
    root.contextPinned = false
    root.contextX = x
    root.contextY = y
    root.settingsSubmenu = ""
    root.contextAppId = "__dock_settings__"
  }

  function setAutohideMode(mode) {
    if (mode === "always") {
      root.autohide = false
      root.intelligentAutohide = false
    } else if (mode === "intelligent") {
      root.autohide = true
      root.intelligentAutohide = true
    } else if (mode === "autohide") {
      root.autohide = true
      root.intelligentAutohide = false
    }
    root.saveConfig()
    root.syncVisibility()
  }

  function setDockOpacity(val) {
    root.dockOpacity = val
    root.saveConfig()
  }

  function setDockShape(shape) {
    root.dockShape = shape
    root.saveConfig()
  }

  function setDockBgColor(col) {
    root.dockBgColor = col
    root.saveConfig()
  }

  function setIconSize(sz) {
    root.configuredIconSize = sz
    root.saveConfig()
  }

  function setItemSpacing(sp) {
    root.itemSpacing = sp
    root.saveConfig()
  }

  function cycleApp(appId, direction) {
    root.focusToplevel(DockModel.pickAppWindow(
      ToplevelManager.toplevels.values, ToplevelManager.activeToplevel, appId, direction))
  }

  // ------------------------------------------------- window plumbing

  function hyprToplevelFor(toplevel) {
    if (!toplevel || !Hyprland.toplevels) return null
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].wayland === toplevel) return list[i]
    return null
  }

  function windowAddress(handle) {
    var value = String((handle && handle.address) || "").trim()
    if (!value) return ""
    if (value.slice(0, 2) === "0x" || value.slice(0, 2) === "0X") value = value.slice(2)
    return "0x" + value
  }

  function luaString(value) {
    return String(value == null ? "" : value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  }

  // Hyprland 0.56 moved dispatchers to Lua; Quickshell reports which syntax
  // the running compositor speaks.
  function hyprDispatch(lua, legacy) {
    Hyprland.dispatch(Hyprland.usingLua ? lua : legacy)
  }

  function workspaceTarget(workspace) {
    if (!workspace) return ""
    var name = String(workspace.name || "")
    return name !== "" ? name : String(workspace.id)
  }

  // Brings a window forward for real. The Wayland activate request only hands
  // over keyboard focus, which leaves scrolling layouts parked where they were,
  // so the compositor's own focus dispatcher does the work whenever we know the
  // window's address.
  function focusToplevel(toplevel) {
    if (!toplevel) return
    var handle = root.hyprToplevelFor(toplevel)
    var workspace = handle ? handle.workspace : null

    if (workspace && workspace.name === root.minimizedWorkspace) {
      root.restoreWindow(handle)
      return
    }

    var address = root.windowAddress(handle)
    if (!address) {
      DockModel.focusWindow(toplevel)
      return
    }

    root.hyprDispatch('hl.dsp.focus({ window = "address:' + address + '" })',
                      "focuswindow address:" + address)
  }

  function minimizeToplevel(toplevel) {
    var handle = root.hyprToplevelFor(toplevel)
    var address = root.windowAddress(handle)
    if (!address) return false

    var origin = root.workspaceTarget(handle.workspace)
    if (origin === root.minimizedWorkspace) return false

    var origins = DockModel.copyMap(root.minimizedOrigins)
    origins[address] = origin
    root.minimizedOrigins = origins

    root.hyprDispatch(
      'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
        + root.luaString(root.minimizedWorkspace) + '", follow = false })',
      "movetoworkspacesilent " + root.minimizedWorkspace + ",address:" + address)
    return true
  }

  function restoreWindow(handle) {
    var address = root.windowAddress(handle)
    if (!address) return false

    var target = root.minimizedOrigins[address] || root.workspaceTarget(Hyprland.focusedWorkspace)
    if (!target) return false

    var origins = DockModel.copyMap(root.minimizedOrigins)
    delete origins[address]
    root.minimizedOrigins = origins

    root.hyprDispatch(
      'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
        + root.luaString(target) + '", follow = true })',
      "movetoworkspace " + target + ",address:" + address)
    root.hyprDispatch('hl.dsp.focus({ window = "address:' + address + '" })',
                      "focuswindow address:" + address)
    return true
  }

  // Drop origins for windows that are gone, so the map cannot grow forever.
  function pruneMinimized() {
    var origins = root.minimizedOrigins
    var addresses = Object.keys(origins)
    if (addresses.length === 0) return

    var live = {}
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      var address = root.windowAddress(list[i])
      if (address) live[address] = true
    }

    var next = {}
    var dropped = false
    for (var j = 0; j < addresses.length; j++) {
      if (live[addresses[j]]) next[addresses[j]] = origins[addresses[j]]
      else dropped = true
    }
    if (dropped) root.minimizedOrigins = next
  }

  // ------------------------------------------------- launch feedback

  function launchApp(appId, entry) {
    if (!root.shell || !root.shell.appLibrary) return
    var target = entry || root.entryForId(appId)
    var deskEntry = DockModel.entryFor(root.appRows, appId)
    var targetId = (deskEntry && deskEntry.id) ? deskEntry.id : appId
    var targetName = (deskEntry && deskEntry.name) ? deskEntry.name : (target && target.name ? target.name : appId)
    if (deskEntry && deskEntry.id) {
      root.shell.appLibrary.launch(deskEntry.id, targetName)
    } else {
      var webAppMatch = String(appId).match(/^(?:chrome|chromium|brave|edge|microsoft-edge)-(.*?)__?-(?:default|profile.*)$/i)
                     || String(appId).match(/^(?:chrome|chromium|brave|edge|microsoft-edge)-(.*?)$/i)
      if (webAppMatch) {
        var webDomain = webAppMatch[1].replace(/^https?___?/i, "").replace(/__.*$/, "")
        Quickshell.execDetached(["omarchy-launch-webapp", "https://" + webDomain])
      } else {
        root.shell.appLibrary.launch(targetId, targetName)
      }
    }
    root.markLaunching(appId, target ? target.windows : 0)
  }

  function markLaunching(appId, windowsBefore) {
    var pending = DockModel.copyMap(root.launchPending)
    pending[appId] = { deadline: Date.now() + root.launchTimeout, windows: windowsBefore || 0 }
    root.launchPending = pending
    launchPruneTimer.start()
  }

  // A pending launch ends when the app gained a window, or when waiting stops
  // being informative.
  function pruneLaunching() {
    var now = Date.now()
    var next = {}
    var remaining = 0
    var changed = false

    for (var appId in root.launchPending) {
      var pending = root.launchPending[appId]
      var entry = root.entryForId(appId)
      if ((entry && entry.windows > pending.windows) || now >= pending.deadline) {
        changed = true
        continue
      }
      next[appId] = pending
      remaining++
    }

    if (changed) root.launchPending = next
    if (remaining === 0) launchPruneTimer.stop()
  }

  function saveConfig() {
    var conf = {}
    try {
      var txt = String(configFile.text() || "").trim()
      if (txt) conf = JSON.parse(txt) || {}
    } catch (e) {
      conf = {}
    }
    conf.autohide = root.autohide
    conf.intelligentAutohide = root.intelligentAutohide
    conf.showAppsButton = root.showAppsButton
    conf.showTooltips = root.showTooltips
    conf.magnification = root.magnification
    conf.launchBounce = root.launchBounce
    conf.advancedTooltips = root.advancedTooltips
    if (root.screenName) conf.screen = root.screenName
    if (root.configuredIconSize > 0) conf.iconSize = root.configuredIconSize
    else delete conf.iconSize
    conf.opacity = root.dockOpacity
    conf.shape = root.dockShape
    conf.bgColor = root.dockBgColor
    conf.itemSpacing = root.itemSpacing
    conf.clickToMinimize = root.clickToMinimize
    conf.showUrgentHint = root.showUrgentHint
    conf.revealDelay = root.revealDelay
    conf.tooltipDelay = root.tooltipDelay
    configFile.setText(JSON.stringify(conf, null, 2))
  }

  function activate(appId) {
    if (!root.shell || !root.shell.appLibrary) return

    var entry = root.entryForId(appId)
    if (!entry || !entry.running) {
      root.launchApp(appId, entry)
      return
    }

    // Clicking the app you are already in is otherwise a dead click. With one
    // window there is no ambiguity about what to put away; with several,
    // cycling stays the more useful answer.
    var windows = entry.windowList || []
    if (root.clickToMinimize && appId === root.activeId && windows.length === 1
        && root.minimizeToplevel(windows[0].toplevel)) return

    root.focusToplevel(DockModel.pickAppWindow(
      ToplevelManager.toplevels.values, ToplevelManager.activeToplevel, appId, 1))
  }

  // Menu rows name the workspace a window sits on, including the parked ones.
  function windowRowLabel(window) {
    var title = String((window && window.title) || "Window")
    var handle = window ? window.hypr : null
    var workspace = handle ? handle.workspace : null
    var label = workspace ? DockModel.workspaceLabel(workspace.name, workspace.id) : ""
    return label !== "" ? "[" + label + "] " + title : title
  }

  function entryForId(appId) {
    var i
    for (i = 0; i < root.pinnedSection.length; i++)
      if (root.pinnedSection[i].appId === appId) return root.pinnedSection[i]
    for (i = 0; i < root.runningSection.length; i++)
      if (root.runningSection[i].appId === appId) return root.runningSection[i]
    return null
  }

  function setPinned(next) {
    root.pinnedIds = next
    dockFile.setText(DockModel.serializePinned(next))
  }

  function togglePin(appId) {
    root.setPinned(DockModel.togglePinned(root.pinnedIds, appId))
  }

  function openContext(appId, x, y) {
    var entry = root.entryForId(appId)
    root.contextName = entry ? entry.name : appId
    root.contextWindows = entry ? entry.windows : 0
    root.contextWindowList = entry && entry.windowList ? entry.windowList : []
    var deskEntry = DockModel.entryFor(root.appRows, appId)
    var canonicalId = (deskEntry && deskEntry.id) ? deskEntry.id : appId
    root.contextPinned = DockModel.isPinned(root.pinnedIds, appId) || (canonicalId !== appId && DockModel.isPinned(root.pinnedIds, canonicalId))
    root.contextX = x
    root.contextY = y
    root.contextAppId = appId
  }

  function closeContext() {
    root.contextAppId = ""
  }

  // Widest piece of content in the open menu. Only implicit widths are read, so
  // feeding the result back into every row cannot loop.
  function menuContentWidth(item) {
    var widest = 0
    if (!item) return widest

    var kids = item.children
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i]
      if (!kid || !kid.visible) continue
      if (kid.isMenuContent === true && kid.implicitWidth > widest) widest = kid.implicitWidth
      var nested = root.menuContentWidth(kid)
      if (nested > widest) widest = nested
    }
    return widest
  }

  // ------------------------------------------------- panel window

  PanelWindow {
    id: dockWindow

    screen: root.dockScreen
    color: "transparent"
    WlrLayershell.namespace: "omadock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: (!root.autohide) ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: (!root.autohide) ? Math.round(dockCard.height + Style.gapsOut * 2) : 0

    anchors { bottom: true; left: true; right: true }
    implicitHeight: 450

    mask: Region {
      item: dockCard
      regions: [
        Region { item: contextMenu },
        Region { item: revealStrip },
        Region { item: globalDismiss }
      ]
    }

    // Bottom edge reveal strip — thin edge trigger with zero click-swallowing
    Item {
      id: revealStrip
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: root.revealHeight

      HoverHandler {
        id: revealHover
        onHoveredChanged: root.syncVisibility()
      }

      Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: revealHover.hovered ? Style.space(48) : Style.space(24)
        height: Style.space(3)
        radius: height / 2
        color: Util.alpha(Color.bar.text, revealHover.hovered ? 0.6 : 0.25)
        Behavior on width { NumberAnimation { duration: 150 } }
        Behavior on color { ColorAnimation { duration: 150 } }
      }
    }

    // Global dismiss area - catches clicks outside context menu
    Item {
      id: globalDismiss
      width: root.contextAppId !== "" ? dockWindow.width : 0
      height: root.contextAppId !== "" ? dockWindow.height : 0
      MouseArea {
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        onClicked: function(mouse) {
          if (root.contextAppId !== "") {
            root.closeContext()
          }
        }
        onReleased: function(mouse) {
          if (root.dragAppId !== "") {
            root.dragAppId = ""
            root.dropBeforeId = ""
            root.syncVisibility()
          }
        }
      }
    }

    // ------------------------------------------------------------ dock card

    BorderSurface {
      id: dockCard

      readonly property color effectiveBgColor: {
        if (root.dockBgColor === "none") return "transparent"
        if (root.dockBgColor === "theme" || !root.dockBgColor) return Color.bar.background
        return root.dockBgColor
      }

      color: Util.alpha(effectiveBgColor, root.dockOpacity)
      borderSpec: Border.flat(Util.alpha(root.dockForeground, Math.max(0.28, root.dockOpacity * 0.4)), 1)
      radius: (root.dockShape === "round" || root.dockShape === "pill")
        ? Math.round(height / 2)
        : (root.dockShape === "square" ? 0 : ((root.dockShape === "theme" || root.dockShape === "auto") ? (Style.cornerRadius > 0 ? Style.cornerRadius : Math.max(14, Style.space(14))) : Math.max(14, Style.space(14))))
      padding: Style.space(4)
      z: 1

      HoverHandler {
        id: cardHover
        onHoveredChanged: root.syncVisibility()
      }

      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.dockVisible ? Style.gapsOut : -(dockCard.height + Style.gapsOut + 10)

      Behavior on anchors.bottomMargin {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
      }

      opacity: root.dockVisible ? 1 : 0
      Behavior on opacity {
        NumberAnimation { duration: 180 }
      }

      width: row.implicitWidth + contentLeftInset + contentRightInset
      height: row.implicitHeight + contentTopInset + contentBottomInset

      // Click on card padding dismisses context menu
      MouseArea {
        id: cardArea
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton
        onClicked: if (root.contextAppId !== "") root.closeContext()
        onReleased: {
          if (root.dragAppId !== "") {
            root.dragAppId = ""
            root.dropBeforeId = ""
            root.syncVisibility()
          }
        }
      }

      Row {
        id: row
        z: 1
        spacing: Style.space(root.itemSpacing)

        anchors.left: parent.left
        anchors.leftMargin: dockCard.contentLeftInset
        anchors.right: parent.right
        anchors.rightMargin: dockCard.contentRightInset
        anchors.top: parent.top
        anchors.topMargin: dockCard.contentTopInset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dockCard.contentBottomInset

        DockIconButton {
          visible: root.showAppsButton
          glyph: "\ue900"
          tooltip: "Apps"
          onPressed: root.toggleAppsMenu()
          onMenuRequested: function(cx, cy) {
            root.openDockSettingsMenu(cx, cy)
          }
        }

        Repeater {
          id: pinnedRepeater
          model: root.pinnedSection
          delegate: DockItem {
            appId: modelData.appId
            name: modelData.name
            icon: modelData.icon
            running: modelData.running
            windows: modelData.windows
            windowList: modelData.windowList
            pinned: true
            active: modelData.appId === root.activeId
            onActivateRequested: function(aid) { root.activate(aid) }
            onNewWindowRequested: function(aid) { root.launchApp(aid, null) }
            onMenuRequested: function(aid, cx, cy) { root.openContext(aid, cx, cy) }
            onWheelScrolled: function(aid, dir) { root.cycleApp(aid, dir) }
            onDragStarted: function(aid) {
              root.dragAppId = aid
              root.dropBeforeId = ""
            }
            onDragMoved: function(aid, mx) {
              root.dropBeforeId = ""
              var count = pinnedRepeater.count
              var found = false
              for (var i = 0; i < count; i++) {
                var child = pinnedRepeater.itemAt(i)
                if (!child || !child.visible) continue
                var childGlobalX = row.x + child.x
                var childCenter = childGlobalX + child.width / 2
                if (mx < childCenter) {
                  root.dropBeforeId = child.appId
                  root.dropIndicatorX = childGlobalX - Style.space(1)
                  found = true
                  break
                }
              }
              if (!found && count > 0) {
                for (var j = count - 1; j >= 0; j--) {
                  var lastChild = pinnedRepeater.itemAt(j)
                  if (lastChild && lastChild.visible) {
                    root.dropBeforeId = ""
                    root.dropIndicatorX = row.x + lastChild.x + lastChild.width + Style.space(1)
                    break
                  }
                }
              }
            }
            onDragDropped: function(aid) {
              var dragId = root.dragAppId
              var beforeId = root.dropBeforeId
              root.dragAppId = ""
              root.dropBeforeId = ""
              if (dragId !== "") {
                root.setPinned(DockModel.reorderPinned(root.pinnedIds, dragId, beforeId))
              }
              root.syncVisibility()
            }
          }
        }

        Rectangle {
          id: separator
          visible: root.pinnedSection.length > 0 && root.runningSection.length > 0
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(1)
          height: root.iconSize * 0.7
          color: Util.alpha(root.dockForeground, 0.25)
        }

        Repeater {
          model: root.runningSection
          delegate: DockItem {
            appId: modelData.appId
            name: modelData.name
            icon: modelData.icon
            running: modelData.running
            windows: modelData.windows
            windowList: modelData.windowList
            pinned: false
            active: modelData.appId === root.activeId
            onActivateRequested: function(aid) { root.activate(aid) }
            onNewWindowRequested: function(aid) { root.launchApp(aid, null) }
            onMenuRequested: function(aid, cx, cy) { root.openContext(aid, cx, cy) }
            onWheelScrolled: function(aid, dir) { root.cycleApp(aid, dir) }
          }
        }
      }

      // Drop indicator line
      Rectangle {
        visible: root.dragAppId !== ""
        x: root.dropIndicatorX
        anchors.verticalCenter: row.verticalCenter
        width: Style.space(2)
        height: root.iconSize + Style.space(4)
        radius: 1
        color: Color.bar.active
        z: 10
      }
    }

    // ------------------------------------------------------------ context menu

    BorderSurface {
      id: contextMenu
      visible: root.contextAppId !== ""
      z: 100
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
      radius: Style.cornerRadius
      padding: Style.space(4)

      readonly property real rowWidth: root.contextAppId !== ""
        ? root.menuContentWidth(menuColumn)
        : 0

      width: root.contextAppId !== ""
        ? rowWidth + contentLeftInset + contentRightInset
        : 0
      height: root.contextAppId !== ""
        ? menuColumn.implicitHeight + contentTopInset + contentBottomInset
        : 0

      anchors.bottom: dockCard.top
      anchors.bottomMargin: Style.space(6)
      x: Math.max(Style.gapsOut, Math.min(dockWindow.width - width - Style.gapsOut, root.contextX - width / 2))

      Column {
        id: menuColumn
        spacing: Style.space(2)

        anchors.left: parent.left
        anchors.leftMargin: contextMenu.contentLeftInset
        anchors.right: parent.right
        anchors.rightMargin: contextMenu.contentRightInset
        anchors.top: parent.top
        anchors.topMargin: contextMenu.contentTopInset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: contextMenu.contentBottomInset

        // Dock Settings Menu (when right-clicking leftmost Omarchy icon)
        Column {
          spacing: Style.space(1)
          visible: root.contextAppId === "__dock_settings__"

          // 1. Main Settings Menu Page
          Column {
            spacing: Style.space(2)
            visible: root.settingsSubmenu === ""

            ContextRow {
              text: "Omadock Settings"
              isHeader: true
            }

            ContextRow {
              text: "Autohide: " + (root.autohide ? (root.intelligentAutohide ? "Intelligent" : "Auto Hide") : "Always Show") + " ›"
              onTriggered: root.settingsSubmenu = "autohide"
            }

            ContextRow {
              text: "Shape: " + (root.dockShape === "theme" || root.dockShape === "auto" ? "Auto (Theme)" : (root.dockShape === "round" || root.dockShape === "pill" ? "Round" : (root.dockShape === "square" ? "Square" : "Rounded"))) + " ›"
              onTriggered: root.settingsSubmenu = "shape"
            }

            ContextRow {
              text: "Background: " + (root.dockOpacity >= 0.95 ? "Opaque" : (root.dockOpacity >= 0.75 ? "Glass" : (root.dockOpacity >= 0.55 ? "Frosted Glass" : (root.dockOpacity >= 0.20 ? "Translucent" : "Transparent")))) + " ›"
              onTriggered: root.settingsSubmenu = "opacity"
            }

            ContextRow {
              text: "Color: " + (root.dockBgColor === "theme" || !root.dockBgColor ? "Theme" : (root.dockBgColor === "none" ? "No Color" : "Custom")) + " ›"
              onTriggered: root.settingsSubmenu = "color"
            }

            ContextRow {
              text: "Icon Size: " + root.iconSize + "px ›"
              onTriggered: root.settingsSubmenu = "size"
            }

            ContextRow {
              text: "Spacing: " + (root.itemSpacing <= 2 ? "Compact" : (root.itemSpacing <= 5 ? "Normal" : "Relaxed")) + " ›"
              onTriggered: root.settingsSubmenu = "spacing"
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Util.alpha(Color.menu.border, 0.4)
            }

            ContextRow {
              text: "Magnification (Zoom)"
              checked: root.magnification
              onTriggered: {
                root.magnification = !root.magnification
                root.saveConfig()
              }
            }

            ContextRow {
              text: "Launch Bounce"
              checked: root.launchBounce
              onTriggered: {
                root.launchBounce = !root.launchBounce
                root.saveConfig()
              }
            }

            ContextRow {
              text: "Window Previews"
              checked: root.advancedTooltips
              onTriggered: {
                root.advancedTooltips = !root.advancedTooltips
                root.saveConfig()
              }
            }

            ContextRow {
              text: "Show Tooltips"
              checked: root.showTooltips
              onTriggered: {
                root.showTooltips = !root.showTooltips
                root.saveConfig()
              }
            }

            ContextRow {
              text: "Urgent Highlights"
              checked: root.showUrgentHint
              onTriggered: {
                root.showUrgentHint = !root.showUrgentHint
                root.saveConfig()
              }
            }

            ContextRow {
              text: "Click Active to Minimize"
              checked: root.clickToMinimize
              onTriggered: {
                root.clickToMinimize = !root.clickToMinimize
                root.saveConfig()
              }
            }
          }

          // 2. Autohide Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "autohide"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = ""
            }

            ContextRow {
              text: "Autohide Mode"
              isHeader: true
            }

            ContextRow {
              text: "Always Show"
              checked: !root.autohide
              onTriggered: root.setAutohideMode("always")
            }

            ContextRow {
              text: "Intelligent Autohide"
              checked: root.autohide && root.intelligentAutohide
              onTriggered: root.setAutohideMode("intelligent")
            }

            ContextRow {
              text: "Auto Hide"
              checked: root.autohide && !root.intelligentAutohide
              onTriggered: root.setAutohideMode("autohide")
            }
          }

          // 3. Shape Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "shape"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = ""
            }

            ContextRow {
              text: "Dock Shape"
              isHeader: true
            }

            ContextRow {
              text: "Auto (Theme)"
              checked: root.dockShape === "theme" || root.dockShape === "auto"
              onTriggered: root.setDockShape("theme")
            }

            ContextRow {
              text: "Rounded"
              checked: root.dockShape === "rounded"
              onTriggered: root.setDockShape("rounded")
            }

            ContextRow {
              text: "Round (Pill)"
              checked: root.dockShape === "round" || root.dockShape === "pill"
              onTriggered: root.setDockShape("round")
            }

            ContextRow {
              text: "Square"
              checked: root.dockShape === "square"
              onTriggered: root.setDockShape("square")
            }
          }

          // 4. Background Color Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "color"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = ""
            }

            ContextRow {
              text: "Background Color"
              isHeader: true
            }

            ContextRow {
              text: "Theme (Default)"
              checked: root.dockBgColor === "theme" || !root.dockBgColor
              onTriggered: root.setDockBgColor("theme")
            }

            ContextRow {
              text: "No Color"
              checked: root.dockBgColor === "none"
              onTriggered: root.setDockBgColor("none")
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Util.alpha(Color.menu.border, 0.4)
            }

            ContextRow {
              text: "Presets"
              isHeader: true
            }

            Grid {
              readonly property bool isMenuContent: true
              columns: 5
              spacing: Style.space(3)
              anchors.horizontalCenter: parent.horizontalCenter
              topPadding: Style.space(2)
              bottomPadding: Style.space(2)

              readonly property var presetColors: [
                "#000000", "#181825", "#1e1e2e", "#0f172a", "#111827",
                "#062e24", "#1c1917", "#2c0b16", "#1e102d", "#334155"
              ]

              Repeater {
                model: parent.presetColors
                delegate: Rectangle {
                  id: swatchRect
                  required property string modelData
                  width: Style.space(24)
                  height: Style.space(24)
                  radius: Style.space(4)
                  color: modelData
                  border.color: root.dockBgColor === modelData
                    ? Color.bar.active
                    : Util.alpha(Color.menu.border, 0.8)
                  border.width: root.dockBgColor === modelData ? 2 : 1

                  Rectangle {
                    visible: root.dockBgColor === swatchRect.modelData
                    anchors.centerIn: parent
                    width: Style.space(8)
                    height: Style.space(8)
                    radius: Style.space(4)
                    color: Color.bar.active
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setDockBgColor(swatchRect.modelData)
                  }
                }
              }
            }
          }

          // 4. Background Opacity Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "opacity"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = ""
            }

            ContextRow {
              text: "Background Opacity"
              isHeader: true
            }

            ContextRow {
              text: "Opaque (100%)"
              checked: root.dockOpacity >= 0.95
              onTriggered: root.setDockOpacity(1.0)
            }

            ContextRow {
              text: "Glass (80%)"
              checked: root.dockOpacity >= 0.75 && root.dockOpacity < 0.95
              onTriggered: root.setDockOpacity(0.80)
            }

            ContextRow {
              text: "Frosted Glass (65%)"
              checked: root.dockOpacity >= 0.55 && root.dockOpacity < 0.75
              onTriggered: root.setDockOpacity(0.65)
            }

            ContextRow {
              text: "Translucent (35%)"
              checked: root.dockOpacity >= 0.20 && root.dockOpacity < 0.55
              onTriggered: root.setDockOpacity(0.35)
            }

            ContextRow {
              text: "Transparent (0%)"
              checked: root.dockOpacity < 0.20
              onTriggered: root.setDockOpacity(0.0)
            }
          }

          // 5. Icon Size Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "size"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = ""
            }

            ContextRow {
              text: "Icon Size"
              isHeader: true
            }

            ContextRow {
              text: "Small (28px)"
              checked: root.configuredIconSize === 28
              onTriggered: root.setIconSize(28)
            }

            ContextRow {
              text: "Medium (36px)"
              checked: root.configuredIconSize === 36 || (root.configuredIconSize === 0 && root.iconSize === 36)
              onTriggered: root.setIconSize(36)
            }

            ContextRow {
              text: "Large (44px)"
              checked: root.configuredIconSize === 44
              onTriggered: root.setIconSize(44)
            }

            ContextRow {
              text: "Extra Large (52px)"
              checked: root.configuredIconSize === 52
              onTriggered: root.setIconSize(52)
            }
          }

          // 6. Icon Spacing Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "spacing"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = ""
            }

            ContextRow {
              text: "Icon Spacing"
              isHeader: true
            }

            ContextRow {
              text: "Compact (2px)"
              checked: root.itemSpacing === 2
              onTriggered: root.setItemSpacing(2)
            }

            ContextRow {
              text: "Normal (4px)"
              checked: root.itemSpacing === 4
              onTriggered: root.setItemSpacing(4)
            }

            ContextRow {
              text: "Relaxed (8px)"
              checked: root.itemSpacing === 8
              onTriggered: root.setItemSpacing(8)
            }
          }
        }

        // Regular App Context Menu
        Column {
          spacing: Style.space(2)
          visible: root.contextAppId !== "" && root.contextAppId !== "__dock_settings__"

          // Multi-window instance list
          Column {
            spacing: Style.space(1)
            visible: root.contextWindowList.length > 1

            ContextRow {
              text: "Windows (" + root.contextWindowList.length + ")"
              isHeader: true
            }

            Repeater {
              model: root.contextWindowList
              delegate: ContextRow {
                text: root.windowRowLabel(modelData)
                onTriggered: {
                  root.focusToplevel(modelData.toplevel)
                  root.closeContext()
                }
              }
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Util.alpha(Color.menu.border, 0.5)
            }
          }

          ContextRow {
            text: root.contextWindows > 0 ? "New Window" : "Launch"
            onTriggered: {
              root.launchApp(root.contextAppId, null)
              root.closeContext()
            }
          }

          ContextRow {
            text: root.contextPinned ? "Unpin from Dock" : "Pin to Dock"
            onTriggered: {
              var deskEntry = DockModel.entryFor(root.appRows, root.contextAppId)
              var canonicalId = (deskEntry && deskEntry.id) ? deskEntry.id : root.contextAppId
              root.togglePin(canonicalId)
              root.closeContext()
            }
          }

          ContextRow {
            text: root.contextWindows > 1 ? "Close All Windows" : "Close Window"
            visible: root.contextWindows > 0
            danger: true
            onTriggered: {
              DockModel.closeApp(ToplevelManager.toplevels.values, root.contextAppId)
              root.closeContext()
            }
          }
        }
      }
    }
  }
}

