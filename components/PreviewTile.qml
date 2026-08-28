import QtQuick
import Quickshell
import Quickshell.Wayland._Screencopy
import qs.Commons
import qs.Ui

Item {
  id: tile

  property var rootRef: null
  readonly property var root: rootRef
  property var dockCard: root ? root.dockCard : null

  property var tileData: typeof modelData !== "undefined" ? modelData : null
  property int tileIndex: typeof index !== "undefined" ? index : 0

  readonly property bool isGroup: tileData ? tileData.type === "group" : false
  readonly property var win: tileData ? (isGroup ? tileData.windows[0] : tileData.win) : null
  readonly property var groupWins: tileData ? (isGroup ? tileData.windows : [tileData.win]) : []
  readonly property int groupCount: tileData ? (isGroup ? tileData.windows.length : 1) : 0
  readonly property string tileTitle: {
    if (isGroup) return groupCount + " windows — " + ((tileData && tileData.title) ? tileData.title : "")
    return (win && win.title !== undefined) ? String(win.title) : ""
  }
  readonly property bool tileHovered: tileArea.containsMouse
  readonly property bool tileMenuOpen: root ? root.contextAppId === "__tile_context__" : false

  // Same magnify contract as DockItem/DockFolderItem: wave grows the
  // layout slot; zoom scales the visual stack in place (tileVisual).
  readonly property real homeCenter: root ? root.slotHomeCenter(
    root.appsSlots + root.pinnedSection.length + (root.hasLeftTileSeparator ? 1 : 0) + tileIndex,
    root.appsSlots + root.pinnedSection.length,
    0,
    (root.hasLeftTileSeparator ? root.separatorWidth : 0) + tileIndex * root.tileWidth + (root.tileWidth - root.iconSlot) / 2) : 0
  property real magnifyScale: {
    if (!root) return 1
    if (root.waveHover) return root.magnifyScaleAt(tile.homeCenter)
    if (root.hoverEffect === "off") return 1
    return (tileArea.containsMouse && !tile.tileMenuOpen) ? root.zoomPeak : 1
  }
  Behavior on magnifyScale {
    NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
  }

  function doRestore() {
    if (root) root.restoreWindowBatch(groupWins)
  }

  function doClose() {
    if (!root) return
    for (var i = 0; i < groupWins.length; i++) {
      var w = groupWins[i]
      if (w && w.address) root.hyprDispatch(
        'hl.dsp.window.close({ window = "address:' + w.address + '" })',
        "closewindow address:" + w.address)
    }
  }

  width: root ? root.tileWidth * (root.waveHover ? tile.magnifyScale : 1) : 0
  height: root ? root.tileHeight : 0
  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  opacity: (root && root.dockVisible) ? 1 : 0

  // Zoom mode scales this visual stack in place (the preview overlaps
  // neighbors exactly like magnified app icons); wave mode grows the
  // tile itself, so the wrapper stays at scale 1 there.
  Item {
    id: tileVisual
    anchors.fill: parent
    scale: (root && root.waveHover) ? 1 : tile.magnifyScale

    // Stacked-card layers behind grouped tiles hint at the count.
    Rectangle {
      visible: tile.isGroup && tile.groupCount > 1
      anchors.fill: parent
      anchors.leftMargin: -Style.space(3)
      anchors.bottomMargin: -Style.space(2)
      radius: Math.max(3, Style.space(4))
      color: Util.alpha(root ? root.dockForeground : Color.bar.text, 0.16)
      border.width: 1
      border.color: Util.alpha(root ? root.dockForeground : Color.bar.text, 0.38)
    }
    Rectangle {
      visible: tile.isGroup && tile.groupCount > 2
      anchors.fill: parent
      anchors.leftMargin: -Style.space(6)
      anchors.bottomMargin: -Style.space(4)
      radius: Math.max(3, Style.space(4))
      color: Util.alpha(root ? root.dockForeground : Color.bar.text, 0.11)
      border.width: 1
      border.color: Util.alpha(root ? root.dockForeground : Color.bar.text, 0.28)
    }

    Rectangle {
      anchors.fill: parent
      radius: Math.max(3, Style.space(4))
      color: tileArea.containsMouse ? Color.menu.selectedBackground : Util.alpha(root ? root.dockForeground : Color.bar.text, 0.10)
      border.width: 1
      border.color: Util.alpha(root ? root.dockForeground : Color.bar.text, tileArea.containsMouse ? 0.55 : 0.22)
    }

    ScreencopyView {
      id: tilePreview
      anchors.fill: parent
      anchors.margins: 1
      visible: hasContent
      clip: true
      live: false
      captureSource: tile.win && tile.win.waylandToplevel ? tile.win.waylandToplevel : null

      // The capture context negotiates asynchronously over Wayland,
      // so an immediate captureFrame() warns "no recording context".
      // A short event-driven retry (never a polling loop) gets every
      // tile its frame exactly once, after the session is ready.
      function requestFrame() {
        if (hasContent || !captureSource) return
        captureRetry.attempts = 0
        captureRetry.restart()
      }
      onCaptureSourceChanged: {
        captureRetry.attempts = 0
        captureRetry.restart()
      }
      // Failed exports emit stopped, which destroys the Wayland
      // capture context. Null-then-restore forces createContext()
      // via setCaptureSource; Qt.callLater avoids double-triggering
      // onCaptureSourceChanged in the same event loop tick.
      onStopped: {
        var src = captureSource
        captureSource = null
        Qt.callLater(function() { captureSource = src })
      }

      Timer {
        id: captureRetry
        interval: 140
        property int attempts: 0
        repeat: attempts < 6
        onTriggered: {
          attempts++
          if (!tilePreview.hasContent && tilePreview.captureSource) tilePreview.captureFrame()
        }
      }
    }

    // App-icon badge: only shown when there's no preview yet (letter)
    // or when the group has 2+ windows (count). Single-window tiles
    // never show a "1" badge once the preview has loaded.
    Rectangle {
      visible: (!tilePreview.hasContent || tile.groupCount > 1) && tile.win && tile.win.appId !== ""
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 1
      width: Style.space(tile.groupCount > 1 ? 18 : 14)
      height: Style.space(tile.groupCount > 1 ? 18 : 14)
      radius: Style.space(3)
      color: Util.alpha(Color.bar.background, 0.85)

      Text {
        anchors.centerIn: parent
        text: {
          if (!tile.win || !tile.win.appId) return "?"
          return tile.groupCount > 1 ? String(tile.groupCount) : tile.win.appId.substring(0, 1).toUpperCase()
        }
        textFormat: Text.PlainText
        color: Color.bar.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  // Title bubble above the hovered tile (hidden while the menu is open).
  BorderSurface {
    id: tileTooltip
    visible: tile.tileHovered && !tile.tileMenuOpen && tile.tileTitle !== ""
    z: 300
    color: Color.tooltip.background
    borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
    padding: Style.space(4)
    x: (parent.width - width) / 2
    y: -height - Style.space(6)
    width: tileTooltipLabel.implicitWidth + contentLeftInset + contentRightInset
    height: tooltipImplicitHeight()

    function tooltipImplicitHeight() {
      return tileTooltipLabel.implicitHeight + contentTopInset + contentBottomInset
    }

    Text {
      id: tileTooltipLabel
      x: parent.contentLeftInset
      y: parent.contentTopInset
      text: {
        if (!tile.isGroup) return tile.tileTitle
        var lines = []
        var max = Math.min(tile.groupWins.length, 6)
        for (var i = 0; i < max; i++) lines.push("• " + (tile.groupWins[i] ? tile.groupWins[i].title : ""))
        if (tile.groupWins.length > 6) lines.push("+" + (tile.groupWins.length - 6) + " more")
        return lines.join("\n")
      }
      textFormat: Text.PlainText
      color: Color.tooltip.text
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      maximumLineCount: tile.isGroup ? 8 : 1
    }
  }

  MouseArea {
    id: tileArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (!tile.win || !tile.win.address) return
      if (mouse.button === Qt.RightButton) {
        var targetWin = root ? root.contentItemRef : null
        var pt = targetWin ? tile.mapToItem(targetWin, tile.width / 2, 0) : null
        var gx = pt ? pt.x : (tile.width / 2)
        if (root) root.openTileContext(tile.groupWins, tile.win.appId || "", gx)
      } else if (root && root.contextAppId === "__tile_context__") {
        root.closeContext()
      } else {
        tile.doRestore()
      }
    }
  }
}
