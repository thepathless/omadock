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

  // Badge counts are filed under whichever id the matching entry carries.
  // DockModel owns the id spellings, so this only sums the aliases it is told.
  readonly property int notificationCount: {
    if (!root || !root.showNotificationBadges || !item.pinned) return 0
    var ids = DockModel.notificationAliasIds(item.appId)
    var seen = ({})
    var count = 0
    for (var i = 0; i < ids.length; i++) {
      if (seen[ids[i]]) continue
      seen[ids[i]] = true
      count += root.notificationBadges[ids[i]] || 0
    }
    return count
  }

  signal activateRequested(string appId)
  signal newWindowRequested(string appId)
  signal menuRequested(string appId, real cx, real cy)
  signal dragStarted(string appId)
  signal dragMoved(string appId, real x, real y)
  signal dragDropped(string appId)

  // Only the wave lets a slot grow; zoom keeps the layout still and simply
  // draws its icon larger.
  width: root ? (root.iconSlot * (root.waveHover ? item.magnifyScale : 1)) : 0
  height: root ? root.iconSlot : 0
  z: Math.round(item.magnifyScale * 100)

  property bool isDragging: false
  property bool _dragJustEnded: false
  property real dragStartX: 0
  property real dragStartY: 0
  property real bounceY: 0
  property real homeCenter: 0

  Connections {
    target: root
    function onDragAppIdChanged() {
      if ((!root || !root.dragAppId) && item.isDragging) {
        item.isDragging = false
        item._dragJustEnded = true
      }
    }
  }

  readonly property bool isDropTarget: (root && root.dropTargetAppId === item.appId && root.dragAppId !== item.appId)
  // Files from outside hover this icon and the app can open them.
  readonly property bool isFileDropTarget: root ? (root.appDropTargetId === item.appId && root.appDropState === "yes") : false
  property real magnifyScale: {
    if (!root) return 1
    if (root.waveHover) return root.magnifyScaleAt(item.homeCenter)
    if (root.hoverEffect !== "zoom") return 1
    return ((area.containsMouse && !item.isDragging) || item.isFileDropTarget) ? root.zoomPeak : 1
  }

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
  // Urgency animates for URGENT_ANIMATION_MS, then only the indicator's
  // urgent colour remains: an unattended urgent window must not keep the
  // dock (and the compositor) redrawing forever. A new urgent event starts
  // it again.
  readonly property int urgentAnimationMs: 10000
  property bool urgentFresh: false
  function restartUrgentAnimation() {
    if (!item.urgent) return
    item.urgentFresh = true
    if (root && root.dockVisible) urgentCalm.restart()
    else urgentCalm.stop()
  }
  onUrgentChanged: {
    if (item.urgent) item.restartUrgentAnimation()
    else { item.urgentFresh = false; urgentCalm.stop() }
  }
  Component.onCompleted: item.restartUrgentAnimation()
  // Whether the latest urgency event names this app or one of its windows.
  function isUrgentEventForMe() {
    var keys = root ? (root.urgentEventKeys || []) : []
    if (keys.indexOf(item.appId) >= 0) return true
    var list = item.windowList || []
    for (var i = 0; i < list.length; i++)
      if (list[i] && keys.indexOf(list[i].address) >= 0) return true
    return false
  }
  Connections {
    target: root
    // A new urgency event for this app while it is still marked urgent.
    function onUrgentEventsChanged() {
      if (item.isUrgentEventForMe()) Qt.callLater(item.restartUrgentAnimation)
    }
  }
  // Counts only while the dock is shown, so an autohidden dock still
  // bounces when it is revealed.
  Timer {
    id: urgentCalm
    interval: item.urgentAnimationMs
    running: false
    onTriggered: item.urgentFresh = false
  }
  Connections {
    target: root
    function onDockVisibleChanged() {
      if (!item.urgentFresh) return
      if (root.dockVisible) urgentCalm.restart()
      else urgentCalm.stop()
    }
  }

  readonly property bool pulsing: item.starting || (item.urgent && item.urgentFresh)
  onPulsingChanged: if (!item.pulsing) item.pulse = 1.0

  SequentialAnimation on pulse {
    running: item.pulsing && (root ? root.dockVisible : false)
    loops: Animation.Infinite
    NumberAnimation { from: 1.0; to: 0.35; duration: 650; easing.type: Easing.InOutQuad }
    NumberAnimation { from: 0.35; to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
  }

  // Fainter still once pulled off the dock, where letting go unpins it.
  opacity: item.isDragging ? ((root && root.dragRemoveArmed) ? 0.12 : 0.35) : 1.0
  Behavior on opacity {
    NumberAnimation { duration: 120 }
  }

  readonly property bool bouncing: root ? ((item.starting && root.launchBounce) || (item.urgent && item.urgentFresh && root.showUrgentHint)) : false
  onBouncingChanged: if (!item.bouncing) item.bounceY = 0

  SequentialAnimation on bounceY {
    running: item.bouncing && (root ? root.dockVisible : false)
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

    scale: area.pressed ? 0.92 : 1.0
    transformOrigin: Item.Bottom
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

    transform: Translate {
      y: item.bounceY
    }

    // Drop target halo: creating an App Folder, or files the app can open
    Rectangle {
      visible: item.isDropTarget || item.isFileDropTarget
      anchors.centerIn: iconImg
      width: (root ? root.baseIconArt : 32) * item.magnifyScale + Style.space(8)
      height: width
      radius: root ? root.effectiveCardRadius : Style.cornerRadius
      color: Util.alpha(Color.accent, 0.22)
      border.color: Color.accent
      border.width: 1.5
      z: -1
      SequentialAnimation on opacity {
        running: item.isDropTarget || item.isFileDropTarget
        loops: Animation.Infinite
        NumberAnimation { from: 0.5; to: 1.0; duration: 350; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 1.0; to: 0.5; duration: 350; easing.type: Easing.InOutQuad }
      }
    }

    // Sits on the dock floor and grows upward, so a magnified icon never
    // reaches down over the running dot beneath it.
    DockIconArt {
      id: iconImg
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root ? root.iconArtBottom : 0
      width: (root ? root.baseIconArt : 32) * item.magnifyScale
      height: width
      source: {
        var _tv = root ? root.themeVersion : 0
        if (item.icon !== "") return item.icon
        return Quickshell.iconPath("application-x-executable", true)
      }
      visible: String(source) !== ""
      renderSize: root ? root.maxIconArt : 64
      opacity: item.starting ? (0.4 + 0.6 * item.pulse) : 1.0
      iconStyle: root ? root.iconStyle : "original"
      tint: root ? root.iconTintColor : Color.bar.text
      grid: root ? root.iconGrid : 16
      contrast: root ? root.iconContrast : 0
      strength: root ? root.iconStrength : 1
      dropShadow: root ? root.iconShadow : false
      shadowStrength: root ? root.shadowStrength : 0.4
      showOriginal: root ? (root.iconHoverOriginal && area.containsMouse) : false
      hovered: area.containsMouse && !item.isDragging
      hoverFx: root ? root.hoverFx : null

      // The badge rides on the icon, so hover effects move it too.
      overlay: [
        Rectangle {
          visible: item.notificationCount > 0
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: -Style.space(3)
          anchors.topMargin: -Style.space(3)
          width: Math.max(Style.space(17), badgeText.implicitWidth + Style.space(8))
          height: Style.space(17)
          radius: height / 2
          color: Color.accent
          border.width: 1
          border.color: Color.bar.background
          Text {
            id: badgeText
            anchors.centerIn: parent
            text: item.notificationCount > 99 ? "99+" : String(item.notificationCount)
            textFormat: Text.PlainText
            color: root && root.isLight(Color.accent) ? "#12100f" : "#f2efec"
            font.family: Style.font.family
            font.pixelSize: Style.space(10)
            font.bold: true
          }
        }
      ]
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

  // An app with no window whose media player is still up (closed to the
  // tray, playing in the background): a faint dot instead of none.
  readonly property bool backgroundMedia: !item.running && root ? root.mediaPlayerFor(item.appId) !== null : false

  DockIndicator {
    rootRef: item.rootRef
    visible: item.backgroundMedia
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(1)
    kind: "background"
  }

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
      // Active window: accent bar; open window: dot; minimized: hollow dot.
      delegate: DockIndicator {
        readonly property var winObj: (item.windowList && item.windowList.length > index) ? item.windowList[index] : null
        readonly property bool winMinimized: winObj ? item.isWinMinimized(winObj) : item.minimized
        readonly property bool winActive: !winMinimized && ((winObj && winObj.address) ? item.isWinActive(winObj) : (index === 0 && item.isFocused))

        rootRef: item.rootRef
        anchors.verticalCenter: parent.verticalCenter
        kind: winActive ? "active" : (winMinimized ? "minimized" : "window")
        dense: item.totalWindowCount >= 5
        urgent: item.urgent
        pulse: item.pulse
      }
    }

    // Compact overflow pill when 6+ windows are open
    Rectangle {
      visible: item.totalWindowCount > 5
      width: overflowText.implicitWidth + Style.space(4)
      height: Style.space(5)
      radius: (root && root.indicatorSquare) ? 0 : height / 2
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

  // Files dragged in from outside: opened with this app when it declares
  // their types (see Dock.beginAppDrop). Refusing the drag lets a folder
  // fall through to the dock's own drop area, which pins it.
  DropArea {
    anchors.fill: parent
    keys: ["text/uri-list"]
    onEntered: function(drag) {
      if (root) root.beginAppDrop(item.appId, drag.urls)
      drag.accept(Qt.CopyAction)
    }
    onPositionChanged: function(drag) {
      drag.accepted = !root || root.appDropState !== "no"
    }
    onExited: if (root) root.endAppDrop(item.appId)
    onDropped: function(drop) {
      if (root && root.dropOnApp(item.appId)) drop.accept(Qt.CopyAction)
      else drop.accepted = false
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: item.isDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    // The wheel only flips through the app's windows in the tooltip (or the
    // open menu); a click brings the chosen one up.
    onWheel: function(wheel) {
      var dir = root ? root.wheelStep("app:" + item.appId, wheel.angleDelta.y) : 0
      if (dir !== 0) {
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

          // If context menu is open for this app, synchronize its selection.
          // The menu's rows index item.windowList (parked windows included),
          // while this selection was computed over tooltipWindows (visible
          // only) — translate it by address or the highlight and the click
          // land on the wrong window.
          if (root && root.contextAppId === item.appId) {
            if (typeof appContextMenuColumn !== "undefined" && appContextMenuColumn) {
              var selAddr = wins[item.selectedWindowIdx] ? wins[item.selectedWindowIdx].address : ""
              var menuIdx = -1
              for (var mi = 0; item.windowList && mi < item.windowList.length; mi++) {
                if (item.windowList[mi] && item.windowList[mi].address === selAddr) { menuIdx = mi; break }
              }
              appContextMenuColumn.selectedWindowIdx = menuIdx
            }
            return
          }

          itemTooltip.tipShown = true
        }
      }
    }

    onPressed: function(mouse) {
      if (mouse.button === Qt.LeftButton && (item.pinned || item.running)) {
        item.dragStartX = mouse.x
        item.dragStartY = mouse.y
        item.isDragging = false
        item._dragJustEnded = false
      }
    }

    onPositionChanged: function(mouse) {
      if (area.pressed && mouse.buttons & Qt.LeftButton && (item.pinned || item.running)) {
        // Either direction: pulling an icon straight up takes it off the dock.
        var dist = Math.abs(mouse.x - item.dragStartX) + Math.abs(mouse.y - item.dragStartY)
        if (!item.isDragging && dist > 8) {
          item.isDragging = true
          item.dragStarted(item.appId)
        }
        if (item.isDragging) {
          var pt = dockCard ? item.mapToItem(dockCard, mouse.x, mouse.y) : null
          item.dragMoved(item.appId, pt ? pt.x : mouse.x, pt ? pt.y : mouse.y)
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
          // Two index spaces meet here: the menu column indexes the full
          // windowList (set by the menu's own wheel or the translated sync
          // above), while item.selectedWindowIdx indexes tooltipWindows
          // (visible only). Resolve each in its own space, or a click picks
          // a different window than the one highlighted.
          var chosenWin = null
          var menuIdx = -1
          if (typeof appContextMenuColumn !== "undefined" && appContextMenuColumn)
            menuIdx = appContextMenuColumn.selectedWindowIdx
          if (menuIdx >= 0 && item.windowList && menuIdx < item.windowList.length) {
            chosenWin = item.windowList[menuIdx]
          } else if (item.selectedWindowIdx >= 0 && item.tooltipWindows && item.selectedWindowIdx < item.tooltipWindows.length) {
            chosenWin = item.tooltipWindows[item.selectedWindowIdx]
          }

          if (chosenWin && chosenWin.address) {
            root.focusWindowByAddress(chosenWin.address, item.appId)
          }
          item.selectedWindowIdx = -1
          if (typeof appContextMenuColumn !== "undefined" && appContextMenuColumn)
            appContextMenuColumn.selectedWindowIdx = -1
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

  // The item's tooltip: tipShown is the dwell, wanted the hover condition.
  // The popup window that shows it exists only while it is shown.
  Item {
    id: itemTooltip
    width: 0
    height: 0
    property bool tipShown: false
    readonly property bool wanted: area.containsMouse && !item.isDragging
      && item.name !== "" && (root ? (root.showTooltips && root.contextAppId === "") : true)
    readonly property bool showing: itemTooltip.tipShown && itemTooltip.wanted

    TooltipLife {
      id: itemTooltipLife
      dockRoot: root
      // A menu or a drag hides it at once.
      hideDelay: (item.isDragging || (root && root.contextAppId !== "")) ? 0 : 200
      want: itemTooltip.showing
    }

    onWantedChanged: {
      if (itemTooltip.wanted) tooltipDwell.restart()
      else {
        tooltipDwell.stop()
        itemTooltip.tipShown = false
        if (root && root.contextAppId !== item.appId) {
          item.selectedWindowIdx = -1
        }
      }
    }

    // No wait while another tooltip is still up (see TooltipLife).
    Timer {
      id: tooltipDwell
      interval: (root && root.tooltipsAlive > 0) ? 1 : (root ? root.tooltipDelay : 450)
      onTriggered: itemTooltip.tipShown = true
    }

    LazyLoader {
      active: itemTooltipLife.alive

      TooltipWindow {
        target: item
        gap: Style.space(10)
        shown: true
        level: itemTooltipLife.level
        body: itemTooltipSurface

        BorderSurface {
          id: itemTooltipSurface
          color: Color.tooltip.background
          borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
          padding: Style.space(6)
          width: tooltipContent.implicitWidth + contentLeftInset + contentRightInset
          height: tooltipContent.implicitHeight + contentTopInset + contentBottomInset

          Column {
            id: tooltipContent
            x: itemTooltipSurface.contentLeftInset
            y: itemTooltipSurface.contentTopInset
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

            // Window previews: a card stack the wheel rotates; a click on the icon
            // focuses the front card's window.
            WindowCardStack {
              id: cardStack
              readonly property bool wanted: root ? (root.advancedTooltips && item.tooltipWindows.length > 0) : false
              visible: wanted
              width: wanted ? implicitWidth : 0
              height: wanted ? implicitHeight : 0
              anchors.horizontalCenter: parent.horizontalCenter
              rootRef: item.rootRef
              windows: item.tooltipWindows
              active: wanted && itemTooltipLife.alive
              fallbackIcon: iconImg.source
              frontIndex: {
                var wins = item.tooltipWindows
                if (item.selectedWindowIdx >= 0 && item.selectedWindowIdx < wins.length) return item.selectedWindowIdx
                for (var i = 0; i < wins.length; i++)
                  if (item.isWinActive(wins[i])) return i
                return 0
              }
            }

            Text {
              visible: cardStack.wanted
              width: Math.min(implicitWidth, cardStack.width)
              anchors.horizontalCenter: parent.horizontalCenter
              horizontalAlignment: Text.AlignHCenter
              text: (cardStack.wanted && root) ? root.windowRowLabel(item.tooltipWindows[cardStack.frontIndex]) : ""
              textFormat: Text.PlainText
              color: Util.alpha(Color.tooltip.text, 0.80)
              font.family: Style.font.family
              font.pixelSize: Math.max(10, Style.font.caption - 1)
              elide: Text.ElideRight
              maximumLineCount: 1
            }

            Repeater {
              model: (root && !root.advancedTooltips && item.tooltipWindows.length > 0)
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
                  color: isSelected ? Color.accent : (isWinFocused ? Color.accent : Util.alpha(Color.tooltip.text, 0.5))
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
              visible: root ? (!root.advancedTooltips && item.tooltipWindows.length > 8) : false
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
    }
  }
}
