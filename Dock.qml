// omadock — centered autohiding app dock with drag reorder, multi-window
// management, workspace hints, and intelligent scale-aware autohide.

import QtQuick
import QtQuick.Effects
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

    // Only the wave lets a slot grow; zoom keeps the layout still and simply
    // draws its icon larger.
    width: root.iconSlot * (root.waveHover ? item.magnifyScale : 1)
    height: root.iconSlot

    property bool isDragging: false
    property bool _dragJustEnded: false
    property real dragStartX: 0
    property real bounceY: 0
    property real homeCenter: 0
    property real magnifyScale: {
      if (root.waveHover) return root.magnifyScaleAt(item.homeCenter)
      if (root.hoverEffect === "off") return 1
      return (area.containsMouse && !item.isDragging) ? root.zoomPeak : 1
    }

    Behavior on magnifyScale {
      NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
    }

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

    // Live, unlike a flag copied into the model: only one window is focused, and
    // the manager always knows which.
    function windowFocused(window) {
      return !!window && !!ToplevelManager.activeToplevel
        && window.toplevel === ToplevelManager.activeToplevel
    }

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

    SequentialAnimation on bounceY {
      running: item.starting && root.launchBounce
      loops: Animation.Infinite
      NumberAnimation { from: 0; to: -Style.space(13); duration: 260; easing.type: Easing.OutQuad }
      NumberAnimation { from: -Style.space(13); to: 0; duration: 260; easing.type: Easing.OutBounce }
      PauseAnimation { duration: 220 }
    }
    onStartingChanged: if (!item.starting) item.bounceY = 0

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

      transform: Translate {
        y: item.bounceY
      }

      // Sits on the dock floor and grows upward, so a magnified icon never
      // reaches down over the running dot beneath it.
      Image {
        id: iconImg
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round((iconBox.height - root.baseIconArt) / 2)
        width: root.baseIconArt * item.magnifyScale
        height: width
        source: item.icon !== "" ? item.icon : Quickshell.iconPath("application-x-executable", true)
        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
        visible: source !== ""
        opacity: item.starting ? (0.4 + 0.6 * item.pulse) : 1.0
        mipmap: true
        smooth: true

        // Urgency has to reach past the icon art itself, so it rings the slot.
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + Style.space(8)
          height: width
          radius: width / 2
          visible: item.urgent
          color: "transparent"
          border.width: Math.max(1, Style.space(2))
          border.color: Util.alpha(Color.urgent, 0.25 + 0.65 * item.pulse)
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
        width: Style.space(4)
        height: width
        radius: width / 2
        color: item.urgent
          ? Color.urgent
          : (item.active ? Color.bar.active : Util.alpha(root.dockForeground, item.minimized ? 0.3 : 0.65))
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
          item.activateRequested(item.appId)
        }
      }
    }

    BorderSurface {
      id: itemTooltip
      property bool shown: false
      readonly property bool wanted: area.containsMouse && !item.isDragging
        && item.name !== "" && root.showTooltips && root.contextAppId === ""
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
              color: item.windowFocused(item.windowList[index]) ? Color.bar.active : Util.alpha(Color.tooltip.text, 0.4)
            }
            Text {
              text: {
                var w = item.windowList[index]
                var t = w ? root.windowRowLabel(w) : ""
                return t.length > 30 ? t.slice(0, 28) + "…" : t
              }
              color: item.windowFocused(item.windowList[index]) ? Color.tooltip.text : Util.alpha(Color.tooltip.text, 0.75)
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

    property real homeCenter: 0
    property real magnifyScale: {
      if (root.waveHover) return root.magnifyScaleAt(btn.homeCenter)
      if (root.hoverEffect === "off") return 1
      return area.containsMouse ? root.zoomPeak : 1
    }

    Behavior on magnifyScale {
      NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
    }

    width: root.iconSlot * (root.waveHover ? btn.magnifyScale : 1)
    height: root.iconSlot

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      text: btn.glyph
      font.family: "omarchy"
      font.pixelSize: btn.glyphSize
      color: btn.glyphColor
      transformOrigin: Item.Bottom
      scale: btn.magnifyScale * (area.pressed ? 0.92 : 1.0)
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

  // ------------------------------------------------- magnification

  // Raised cosine falloff, the curve Juan Pablo Zamora derived for this effect:
  //   size = min + ((1 - cos t) / 2) * (max - min)
  // over an effectWidth-wide window centred on the cursor, which is
  // 0.5 * (1 + cos(pi * d / R)) for a distance d and half-range R. Flat at the
  // peak and flat where the effect ends, so icons neither snap at the apex nor
  // pop into motion at the edge of the range.
  //
  // Slots grow, and the row grows with them. That is not a stylistic choice:
  // the displacement an icon needs is the accumulated growth between it and the
  // cursor, which integrates to (peak - 1) * R / 2 at the range edge — around
  // 30px per side here. A fixed-width card has nowhere to put that, so nudging
  // icons by a hand-picked amount instead leaves holes next to the pointer and
  // crowding further out. Letting the row carry the extra width is what keeps
  // every gap even.
  //
  // Distances are measured from each slot's *unmagnified* home centre, in
  // window coordinates. Nothing that magnification changes feeds back into
  // those numbers, so the wave cannot chase itself.
  readonly property real magnifyPeak: 1.4
  readonly property real zoomPeak: 1.22
  readonly property real magnifyRange: root.iconSlot * 2.2
  readonly property real baseIconArt: root.iconSize - Style.space(4)

  // The card's own handler, lifted into window coordinates. Both terms move
  // together as the card grows, so their sum stays the physical pointer.
  readonly property real pointerX: cardHover.hovered
    ? dockCard.x + cardHover.point.position.x
    : -1e6

  readonly property int appsSlots: root.showAppsButton ? 1 : 0
  readonly property bool hasSeparator: root.pinnedSection.length > 0 && root.runningSection.length > 0
  readonly property real gapWidth: Style.space(root.itemSpacing)
  readonly property real separatorWidth: Style.space(1)
  readonly property int slotTotal: root.appsSlots + root.pinnedSection.length + root.runningSection.length
  readonly property int elementTotal: root.slotTotal + (root.hasSeparator ? 1 : 0)

  readonly property real baseRowWidth: root.slotTotal * root.iconSlot
    + (root.hasSeparator ? root.separatorWidth : 0)
    + Math.max(0, root.elementTotal - 1) * root.gapWidth

  // Where the row would start if nothing were magnified. The card is centred,
  // so this only moves when the dock's contents change.
  readonly property real baseRowLeft: (dockWindow.width
    - (root.baseRowWidth + dockCard.contentLeftInset + dockCard.contentRightInset)) / 2
    + dockCard.contentLeftInset

  function slotHomeCenter(elementIndex, slotsBefore, sepBefore) {
    return root.baseRowLeft
      + elementIndex * root.gapWidth
      + slotsBefore * root.iconSlot
      + (sepBefore ? root.separatorWidth : 0)
      + root.iconSlot / 2
  }

  function magnifyAt(homeCenter) {
    if (!root.waveHover) return 0
    var distance = root.pointerX - homeCenter
    if (Math.abs(distance) >= root.magnifyRange) return 0
    return 0.5 * (1 + Math.cos(Math.PI * distance / root.magnifyRange))
  }

  function magnifyScaleAt(homeCenter) {
    return 1 + (root.magnifyPeak - 1) * root.magnifyAt(homeCenter)
  }

  // ------------------------------------------------- contrast

  // The bar foreground is tuned for the bar's own background. A custom dock
  // colour can land on the same side of the scale — a light theme's dark text
  // on a dark card, or the reverse — so flip only when the two collide.
  function isLight(value) {
    return (0.2126 * value.r + 0.7152 * value.g + 0.0722 * value.b) > 0.5
  }

  // Corner radius for the dock card. "rounded" tracks the card's own height, so
  // the panel keeps the same visual softness at any icon size.
  function cardRadius(height) {
    if (root.dockShape === "round" || root.dockShape === "pill") return Math.round(height / 2)
    if (root.dockShape === "square") return 0
    if (root.dockShape === "theme" || root.dockShape === "auto")
      return Style.cornerRadius > 0 ? Style.cornerRadius : Math.max(14, Style.space(14))
    return Math.max(Style.space(14), Math.min(Style.space(28), Math.round(height * 0.26)))
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
    root.pruneWindowState()
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

  // Per app: the window it parked last, and the window it was in last. Both
  // hold addresses rather than live handles — a closed window then leaves a
  // stale string that the next prune drops, instead of a dangling object.
  // Hyprland's own focusHistoryID would save the bookkeeping, but Quickshell
  // only refreshes lastIpcObject on window open/close, so it goes stale the
  // moment focus moves.
  property var appParkedWindow: ({})
  property var appRecentWindow: ({})
  property string lastPreDockActiveApp: ""

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
  // "zoom" grows only the icon under the pointer and leaves the layout alone —
  // the behaviour this dock shipped with, and the default. "wave" is the
  // falloff: neighbours respond and the row carries the extra width. "off" is
  // no hover growth at all.
  property string hoverEffect: "zoom"
  readonly property bool waveHover: root.hoverEffect === "wave"
  property bool launchBounce: true
  property bool advancedTooltips: true
  property real dockOpacity: 1.0
  property string dockShape: "rounded"
  property string dockBgColor: "theme"
  property int itemSpacing: 4
  property string minimizeMode: "off"
  readonly property bool clickToMinimize: root.minimizeMode !== "off"
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
      var top = ToplevelManager.activeToplevel
      if (top) {
        var aid = DockModel.normalizeId(top.appId)
        var address = root.windowAddress(root.hyprToplevelFor(top))
        if (aid && address) {
          var recent = DockModel.copyMap(root.appRecentWindow)
          recent[aid] = address
          root.appRecentWindow = recent
        }
        if (!(cardHover && cardHover.hovered) && !(revealHover && revealHover.hovered) && root.contextAppId === "") {
          root.lastPreDockActiveApp = aid
        }
      }
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
    // Migrates the old boolean: an explicit magnification:false meant no growth.
    root.hoverEffect = parsed && typeof parsed.hoverEffect === "string"
      ? parsed.hoverEffect
      : ((parsed && parsed.magnification === false) ? "off" : "zoom")
    root.launchBounce = parsed && parsed.launchBounce !== false
    root.advancedTooltips = parsed && parsed.advancedTooltips !== false
    root.screenName = parsed && typeof parsed.screen === "string" ? parsed.screen : ""
    root.configuredIconSize = parsed && typeof parsed.iconSize === "number" ? parsed.iconSize : 0
    root.dockOpacity = parsed && typeof parsed.opacity === "number" ? Math.max(0.0, Math.min(1.0, parsed.opacity)) : 1.0
    root.dockShape = parsed && typeof parsed.shape === "string" ? parsed.shape : "rounded"
    root.dockBgColor = parsed && typeof parsed.bgColor === "string" ? parsed.bgColor : "theme"
    root.itemSpacing = parsed && typeof parsed.itemSpacing === "number" ? parsed.itemSpacing : 4
    if (parsed && typeof parsed.minimizeMode === "string") {
      root.minimizeMode = parsed.minimizeMode
    } else if (parsed && parsed.clickToMinimize === true) {
      root.minimizeMode = "active"
    } else {
      root.minimizeMode = "off"
    }
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

  function setHoverEffect(mode) {
    root.hoverEffect = mode
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
  // window's address. It switches the workspace on its way, so nothing else has
  // to ask for that.
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

    var aid = DockModel.normalizeId(toplevel.appId)
    if (aid) {
      var parked = DockModel.copyMap(root.appParkedWindow)
      parked[aid] = address
      root.appParkedWindow = parked
    }

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

    if (handle && handle.wayland) {
      var aid = DockModel.normalizeId(handle.wayland.appId)
      if (aid && root.appParkedWindow[aid] === address) {
        var parked = DockModel.copyMap(root.appParkedWindow)
        delete parked[aid]
        root.appParkedWindow = parked
      }
    }

    root.hyprDispatch(
      'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
        + root.luaString(target) + '", follow = true })',
      "movetoworkspace " + target + ",address:" + address)
    root.hyprDispatch('hl.dsp.focus({ window = "address:' + address + '" })',
                      "focuswindow address:" + address)
    return true
  }

  // The window an app should act on: the one it was last focused in, as long as
  // it is still around and not parked.
  function windowByAddress(windows, address) {
    if (!address) return null
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      if (!win || !win.toplevel) continue
      var handle = root.hyprToplevelFor(win.toplevel)
      if (root.windowAddress(handle) !== address) continue
      var ws = handle ? handle.workspace : null
      return (ws && ws.name === root.minimizedWorkspace) ? null : win
    }
    return null
  }

  function recentWindow(appId, windows) {
    return root.windowByAddress(windows, root.appRecentWindow[appId])
  }

  function minimizeApp(entry) {
    if (!entry) return false
    var windows = entry.windowList || []
    if (windows.length === 0) return false

    if (root.minimizeMode === "all") {
      var anyMin = false
      for (var i = 0; i < windows.length; i++) {
        var w = windows[i]
        if (w && w.toplevel) {
          var handle = root.hyprToplevelFor(w.toplevel)
          var ws = handle ? handle.workspace : null
          if (ws && ws.name !== root.minimizedWorkspace) {
            root.minimizeToplevel(w.toplevel)
            anyMin = true
          }
        }
      }
      return anyMin
    } else {
      var targetWin = root.recentWindow(entry.appId, windows)

      if (!targetWin) {
        for (var j = 0; j < windows.length; j++) {
          if (windows[j] && windows[j].toplevel === ToplevelManager.activeToplevel) {
            targetWin = windows[j]
            break
          }
        }
      }

      if (!targetWin) {
        for (var m = 0; m < windows.length; m++) {
          var mhandle = root.hyprToplevelFor(windows[m].toplevel)
          var mws = mhandle ? mhandle.workspace : null
          if (mws && mws.name !== root.minimizedWorkspace) {
            targetWin = windows[m]
            break
          }
        }
      }

      if (targetWin && targetWin.toplevel) {
        return root.minimizeToplevel(targetWin.toplevel)
      }
      return false
    }
  }

  // Everything the dock remembers about a window is keyed by address, so one
  // pass over the live windows is enough to drop what closed.
  function pruneWindowState() {
    var live = {}
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      var address = root.windowAddress(list[i])
      if (address) live[address] = true
    }

    root.minimizedOrigins = root.keepLive(root.minimizedOrigins, live, false)
    root.appParkedWindow = root.keepLive(root.appParkedWindow, live, true)
    root.appRecentWindow = root.keepLive(root.appRecentWindow, live, true)
  }

  // byValue: the map holds addresses as values (app -> window) rather than keys.
  function keepLive(map, live, byValue) {
    var keys = Object.keys(map)
    if (keys.length === 0) return map

    var next = {}
    var dropped = false
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (live[byValue ? map[key] : key]) next[key] = map[key]
      else dropped = true
    }
    return dropped ? next : map
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
    conf.hoverEffect = root.hoverEffect
    delete conf.magnification
    conf.launchBounce = root.launchBounce
    conf.advancedTooltips = root.advancedTooltips
    if (root.screenName) conf.screen = root.screenName
    if (root.configuredIconSize > 0) conf.iconSize = root.configuredIconSize
    else delete conf.iconSize
    conf.opacity = root.dockOpacity
    conf.shape = root.dockShape
    conf.bgColor = root.dockBgColor
    conf.itemSpacing = root.itemSpacing
    conf.minimizeMode = root.minimizeMode
    conf.clickToMinimize = root.minimizeMode !== "off"
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

    var windows = entry.windowList || []
    if (windows.length === 0) {
      root.launchApp(appId, entry)
      return
    }

    // If all windows of this app are currently minimized, clicking restores them
    var allMinimized = true
    for (var k = 0; k < windows.length; k++) {
      var whandle = root.hyprToplevelFor(windows[k].toplevel)
      var wws = whandle ? whandle.workspace : null
      if (!wws || wws.name !== root.minimizedWorkspace) {
        allMinimized = false
        break
      }
    }
    if (allMinimized) {
      for (var r = 0; r < windows.length; r++) {
        var rhandle = root.hyprToplevelFor(windows[r].toplevel)
        if (rhandle) root.restoreWindow(rhandle)
      }
      return
    }

    // Check if this app is currently active OR was active before cursor entered dock
    var isAppActive = (appId === root.activeId) ||
                      (root.lastPreDockActiveApp !== "" && DockModel.isAppMatch(appId, root.lastPreDockActiveApp))

    for (var w = 0; w < windows.length; w++) {
      if (windows[w] && windows[w].toplevel === ToplevelManager.activeToplevel) {
        isAppActive = true
        break
      }
    }

    // Clicking the app you are already in puts it away.
    if (root.minimizeMode !== "off" && isAppActive && root.minimizeApp(entry)) {
      root.lastPreDockActiveApp = ""
      return
    }

    // Otherwise the click brings something back: the window this app parked
    // last, so a second click undoes a minimize.
    var parkedAddress = root.appParkedWindow[appId]
    if (parkedAddress) {
      for (var m = 0; m < windows.length; m++) {
        var parkedHandle = root.hyprToplevelFor(windows[m].toplevel)
        var parkedWs = parkedHandle ? parkedHandle.workspace : null
        if (root.windowAddress(parkedHandle) === parkedAddress
            && parkedWs && parkedWs.name === root.minimizedWorkspace) {
          root.restoreWindow(parkedHandle)
          root.lastPreDockActiveApp = appId
          return
        }
      }
    }

    // Failing that, the window it was last focused in, else wherever the cycle
    // order lands.
    var target = root.recentWindow(appId, windows)
    root.focusToplevel(target ? target.toplevel : DockModel.pickAppWindow(
      ToplevelManager.toplevels.values, ToplevelManager.activeToplevel, appId, 1))
    root.lastPreDockActiveApp = appId
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
    implicitHeight: 650

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
        onHoveredChanged: {
          if (revealHover.hovered && ToplevelManager.activeToplevel)
            root.lastPreDockActiveApp = DockModel.normalizeId(ToplevelManager.activeToplevel.appId)
          root.syncVisibility()
        }
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

    Item {
      id: cardShadow
      visible: root.dockBgColor !== "none" && root.dockOpacity > 0.05
      // Follows the card out of view; a blur left behind would hang on screen
      // after the dock has gone.
      opacity: dockCard.opacity
      anchors.fill: dockCard
      anchors.margins: -Style.space(18)
      z: 0
      layer.enabled: true
      layer.effect: MultiEffect {
        blurEnabled: true
        blur: 1.0
        blurMax: 40
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(18)
        radius: dockCard.radius
        color: Qt.rgba(0, 0, 0, 0.4)
      }
    }

    BorderSurface {
      id: dockCard

      readonly property color effectiveBgColor: {
        if (root.dockBgColor === "none") return "transparent"
        if (root.dockBgColor === "theme" || !root.dockBgColor) return Color.bar.background
        return root.dockBgColor
      }

      color: Util.alpha(effectiveBgColor, root.dockOpacity)
      borderSpec: Border.flat(Util.alpha(root.dockForeground, Math.max(0.22, root.dockOpacity * 0.32)), 1)
      radius: root.cardRadius(height)
      padding: Style.space(5)
      z: 1

      HoverHandler {
        id: cardHover
        onHoveredChanged: {
          if (cardHover.hovered && ToplevelManager.activeToplevel)
            root.lastPreDockActiveApp = DockModel.normalizeId(ToplevelManager.activeToplevel.appId)
          root.syncVisibility()
        }
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
          homeCenter: root.slotHomeCenter(0, 0, false)
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
            homeCenter: root.slotHomeCenter(root.appsSlots + index, root.appsSlots + index, false)
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
            homeCenter: root.slotHomeCenter(
              root.appsSlots + root.pinnedSection.length + (root.hasSeparator ? 1 : 0) + index,
              root.appsSlots + root.pinnedSection.length + index,
              root.hasSeparator)
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

          // 1. Main Categories Page (Minimalist & Categorized)
          Column {
            spacing: Style.space(2)
            visible: root.settingsSubmenu === ""

            ContextRow {
              text: "Omadock Settings"
              isHeader: true
            }

            ContextRow {
              text: "Appearance ›"
              onTriggered: root.settingsSubmenu = "appearance"
            }

            ContextRow {
              text: "Behavior & Windows ›"
              onTriggered: root.settingsSubmenu = "behavior"
            }

            ContextRow {
              text: "Effects & Animations ›"
              onTriggered: root.settingsSubmenu = "effects"
            }

            ContextRow {
              text: "Size & Spacing ›"
              onTriggered: root.settingsSubmenu = "size_spacing"
            }
          }

          // 2. Appearance Category Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "appearance"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = ""
            }

            ContextRow {
              text: "Appearance"
              isHeader: true
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
          }

          // 3. Behavior & Windows Category Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "behavior"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = ""
            }

            ContextRow {
              text: "Behavior & Windows"
              isHeader: true
            }

            ContextRow {
              text: "Autohide: " + (root.autohide ? (root.intelligentAutohide ? "Intelligent" : "Auto Hide") : "Always Show") + " ›"
              onTriggered: root.settingsSubmenu = "autohide"
            }

            ContextRow {
              text: "Minimize On Click: " + (root.minimizeMode === "all" ? "All Windows" : (root.minimizeMode === "active" ? "Active Window" : "Disabled")) + " ›"
              onTriggered: root.settingsSubmenu = "minimize"
            }

            ContextRow {
              text: "Urgent Highlights"
              checked: root.showUrgentHint
              onTriggered: {
                root.showUrgentHint = !root.showUrgentHint
                root.saveConfig()
              }
            }
          }

          // 4. Effects & Animations Category Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "effects"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = ""
            }

            ContextRow {
              text: "Effects & Animations"
              isHeader: true
            }

            ContextRow {
              text: "Hover: " + (root.hoverEffect === "wave" ? "Wave" : (root.hoverEffect === "off" ? "None" : "Zoom")) + " ›"
              onTriggered: root.settingsSubmenu = "hover"
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
          }

          // Hover Effect Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "hover"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = "effects"
            }

            ContextRow {
              text: "Hover Effect"
              isHeader: true
            }

            ContextRow {
              text: "Zoom"
              checked: root.hoverEffect !== "wave" && root.hoverEffect !== "off"
              onTriggered: root.setHoverEffect("zoom")
            }

            ContextRow {
              text: "Wave"
              checked: root.hoverEffect === "wave"
              onTriggered: root.setHoverEffect("wave")
            }

            ContextRow {
              text: "None"
              checked: root.hoverEffect === "off"
              onTriggered: root.setHoverEffect("off")
            }
          }

          // 5. Size & Spacing Category Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "size_spacing"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = ""
            }

            ContextRow {
              text: "Size & Spacing"
              isHeader: true
            }

            ContextRow {
              text: "Icon Size: " + root.iconSize + "px ›"
              onTriggered: root.settingsSubmenu = "size"
            }

            ContextRow {
              text: "Spacing: " + (root.itemSpacing <= 2 ? "Compact" : (root.itemSpacing <= 5 ? "Normal" : "Relaxed")) + " ›"
              onTriggered: root.settingsSubmenu = "spacing"
            }
          }

          // 6. Autohide Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "autohide"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = "behavior"
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

          // 7. Minimize Mode Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "minimize"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = "behavior"
            }

            ContextRow {
              text: "Minimize On Click"
              isHeader: true
            }

            ContextRow {
              text: "Disabled"
              checked: root.minimizeMode === "off"
              onTriggered: {
                root.minimizeMode = "off"
                root.saveConfig()
              }
            }

            ContextRow {
              text: "Active Window (Most Recent)"
              checked: root.minimizeMode === "active"
              onTriggered: {
                root.minimizeMode = "active"
                root.saveConfig()
              }
            }

            ContextRow {
              text: "All Windows of App"
              checked: root.minimizeMode === "all"
              onTriggered: {
                root.minimizeMode = "all"
                root.saveConfig()
              }
            }
          }

          // 8. Shape Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "shape"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = "appearance"
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

          // 9. Background Color Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "color"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = "appearance"
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

          // 10. Background Opacity Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "opacity"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = "appearance"
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

          // 11. Icon Size Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "size"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = "size_spacing"
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

          // 12. Icon Spacing Submenu Page
          Column {
            spacing: Style.space(1)
            visible: root.settingsSubmenu === "spacing"

            ContextRow {
              text: "‹ Back"
              textColor: Color.bar.active
              onTriggered: root.settingsSubmenu = "size_spacing"
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

