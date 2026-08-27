import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

Item {
  id: cardWrapper

  property var rootRef: null
  readonly property var root: rootRef

  property alias dockCard: dockCard
  property alias cardHover: cardHover
  property alias row: row
  property alias pinnedRepeater: pinnedRepeater
  property alias minimizedTilesRepeater: minimizedTilesRepeater
  property alias runningRepeater: runningRepeater
  property alias foldersRepeater: foldersRepeater

  // Dimensions driven by dockCard
  width: dockCard.width
  height: dockCard.height

  anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
  anchors.bottom: parent ? parent.bottom : undefined
  anchors.bottomMargin: (root && root.dockVisible) ? Style.gapsOut : -(dockCard.height + Style.gapsOut + 10)

  Behavior on anchors.bottomMargin {
    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
  }

  opacity: (root && root.dockVisible) ? 1 : 0
  Behavior on opacity {
    NumberAnimation { duration: 180 }
  }

  Item {
    id: cardShadow
    visible: true
    // Follows the card out of view; a blur left behind would hang on screen
    // after the dock has gone.
    opacity: cardWrapper.opacity
    anchors.fill: dockCard
    anchors.margins: -Style.space(16)
    z: 0
    layer.enabled: true
    layer.effect: MultiEffect {
      blurEnabled: true
      blur: 1.0
      blurMax: 36
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(16)
      radius: dockCard.radius
      color: Qt.rgba(0, 0, 0, (root && root.dockBgColor === "none") ? 0.52 : 0.40)
    }
  }

  BorderSurface {
    id: dockCard

    readonly property color effectiveBgColor: {
      if (!root) return Color.bar.background
      if (root.dockBgColor === "none") return Qt.rgba(0, 0, 0, 0.25)
      if (root.dockBgColor === "theme" || !root.dockBgColor) return Color.bar.background
      return root.dockBgColor
    }

    readonly property real effectiveBorderWidth: 1.5
    readonly property color effectiveBorderColor: {
      if (!root) return Color.bar.border
      // Specular Frosted Glass Rim: Crisp highlight with high alpha for contrast on dark and light surfaces
      if (root.effectiveDockOpacity < 0.25 || root.dockBgColor === "none") return Util.alpha(root.dockForeground, 0.48)
      return Util.alpha(root.dockForeground, Math.max(0.24, root.effectiveDockOpacity * 0.35))
    }

    color: (root && root.dockBgColor === "none") ? effectiveBgColor : Util.alpha(effectiveBgColor, root ? root.effectiveDockOpacity : 1.0)
    borderSpec: Border.flat(dockCard.effectiveBorderColor, dockCard.effectiveBorderWidth)
    radius: root ? root.cardRadius(height) : Style.cornerRadius
    padding: Style.space(5)
    z: 1

    HoverHandler {
      id: cardHover
      onHoveredChanged: if (root) root.syncVisibility()
    }

    width: row.implicitWidth + contentLeftInset + contentRightInset
    height: row.implicitHeight + contentTopInset + contentBottomInset

    // Click on card padding dismisses context menu
    MouseArea {
      id: cardArea
      anchors.fill: parent
      z: 0
      acceptedButtons: Qt.LeftButton
      onClicked: if (root && root.contextAppId !== "") root.closeContext()
      onReleased: {
        if (root && root.dragAppId !== "") {
          root.dragAppId = ""
          root.dropBeforeId = ""
          root.syncVisibility()
        }
      }
    }

    Row {
      id: row
      z: 1
      spacing: Style.space(root ? root.itemSpacing : 4)

      anchors.left: parent.left
      anchors.leftMargin: dockCard.contentLeftInset
      anchors.right: parent.right
      anchors.rightMargin: dockCard.contentRightInset
      anchors.top: parent.top
      anchors.topMargin: dockCard.contentTopInset
      anchors.bottom: parent.bottom
      anchors.bottomMargin: dockCard.contentBottomInset

      DockIconButton {
        rootRef: cardWrapper.rootRef
        visible: root ? root.showAppsButton : true
        homeCenter: root ? root.slotHomeCenter(0, 0, false) : 0
        glyph: "\ue900"
        glyphColor: root ? root.dockForeground : Color.bar.text
        tooltip: "Omarchy"
        onPressed: Quickshell.execDetached(["omarchy-menu", "toggle", "root"])
        onMiddleClicked: Quickshell.execDetached(["omarchy-launch-terminal"])
        onWheelScrolled: function(dir) { if (root) root.cycleWorkspace(dir) }
        onMenuRequested: function(cx, cy) {
          if (root) root.openDockSettingsMenu(cx, cy)
        }
      }

      Repeater {
        id: pinnedRepeater
        model: root ? root.pinnedSection : []
        delegate: DockItem {
          rootRef: cardWrapper.rootRef
          appId: modelData.appId
          name: modelData.name
          icon: modelData.icon
          running: modelData.running
          windows: modelData.windows
          windowList: modelData.windowList
          homeCenter: root ? root.slotHomeCenter(root.appsSlots + index, root.appsSlots + index, false) : 0
          pinned: true
          active: root ? (modelData.appId === root.activeId) : false
          onActivateRequested: function(aid) { if (root) root.activate(aid) }
          onNewWindowRequested: function(aid) { if (root) root.launchApp(aid, null) }
          onMenuRequested: function(aid, cx, cy) { if (root) root.openContext(aid, cx, cy) }
          onWheelScrolled: function(aid, dir) { if (root) root.cycleApp(aid, dir) }
          onDragStarted: function(aid) {
            if (root) {
              root.dragAppId = aid
              root.dropBeforeId = ""
            }
          }
          onDragMoved: function(aid, mx) {
            if (!root) return
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
            if (!root) return
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

      // Divider between pinned apps and the minimized-tile section.
      Rectangle {
        visible: root ? root.hasLeftTileSeparator : false
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(1)
        height: root ? (root.iconSize * 0.7) : 24
        color: Util.alpha(root ? root.dockForeground : Color.bar.text, 0.25)
      }

      // ------------------------------------------ minimized window tiles
      // macOS-style section: every parked window shows up as a small live
      // preview tile. Click a tile to bring that exact window back.
      Repeater {
        id: minimizedTilesRepeater
        model: root ? root.tileModel : []

        delegate: PreviewTile {
          rootRef: cardWrapper.rootRef
          tileData: modelData
          tileIndex: index
        }
      }

      Rectangle {
        id: separator
        visible: root ? root.hasSeparator : false
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(1)
        height: root ? (root.iconSize * 0.7) : 24
        color: Util.alpha(root ? root.dockForeground : Color.bar.text, 0.25)
      }

      Repeater {
        id: runningRepeater
        model: root ? root.runningSection : []
        delegate: DockItem {
          id: runningDockItem
          rootRef: cardWrapper.rootRef
          appId: modelData.appId
          name: modelData.name
          icon: modelData.icon
          running: modelData.running
          windows: modelData.windows
          windowList: modelData.windowList
          // Wave geometry must count only icons that actually render — a
          // hidden (fully-tiled) entry occupies zero width in the Row.
          readonly property int visibleIdx: root ? root.visibleRunningSlotBefore(index) : 0
          homeCenter: root ? root.slotHomeCenter(
            root.appsSlots + root.pinnedSection.length + (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + root.tileElements + visibleIdx,
            root.appsSlots + root.pinnedSection.length + visibleIdx,
            root.hasSeparator,
            root.tilesFixedWidth) : 0
          pinned: false
          active: root ? (modelData.appId === root.activeId) : false
          onActivateRequested: function(aid) { if (root) root.activate(aid) }
          onNewWindowRequested: function(aid) { if (root) root.launchApp(aid, null) }
          onMenuRequested: function(aid, cx, cy) { if (root) root.openContext(aid, cx, cy) }
          onWheelScrolled: function(aid, dir) { if (root) root.cycleApp(aid, dir) }

          // When an unpinned app has ALL its windows minimized and tiles are
          // showing, the tile section already represents it — hide the icon
          // slot entirely so only the tile (with hollow dot) is visible.
          // Live resolver: same source as the running-dot indicator, so the
          // icon can never outlive its own tile after a lagged park.
          readonly property bool isFullyTiled: (root && root.showMinimizedTiles)
            && DockModel.allWindowsMinimized(modelData.windowList, root ? root.liveWsNameOf : null, root ? root.minimizedWorkspace : "special:minimized")
          visible: !isFullyTiled

          // Row preserves space for invisible items that have explicit width.
          // Collapse to 0 when hidden so the dock card shrinks correctly.
          Binding {
            target: runningDockItem
            property: "width"
            when: runningDockItem.isFullyTiled
            value: 0
          }
        }
      }

      Rectangle {
        id: folderSeparator
        visible: root ? root.hasFolderSeparator : false
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(1)
        height: root ? (root.iconSize * 0.7) : 24
        color: Util.alpha(root ? root.dockForeground : Color.bar.text, 0.25)
      }

      Repeater {
        id: foldersRepeater
        model: root ? root.pinnedFolders : []
        delegate: DockFolderItem {
          rootRef: cardWrapper.rootRef
          folderPath: modelData.path
          name: modelData.name || "Folder"
          icon: modelData.icon || DockModel.folderIconFor(modelData.path, "")
          homeCenter: root ? root.slotHomeCenter(
            root.appsSlots + root.pinnedSection.length + (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + root.tileElements + root.visibleRunningCount + (root.hasFolderSeparator ? 1 : 0) + index,
            root.appsSlots + root.pinnedSection.length + root.visibleRunningCount + index,
            (root.hasSeparator ? 1 : 0) + (root.hasFolderSeparator ? 1 : 0),
            root.tilesFixedWidth) : 0
          onOpenStackRequested: function(fpath, fname, cx, cy) {
            if (root) root.openFolderStack(fpath, fname, cx)
          }
          onMenuRequested: function(fpath, fname, cx, cy) {
            if (root) root.openFolderContext(fpath, fname, cx, cy)
          }
        }
      }
    }

    // Drop indicator line
    Rectangle {
      visible: (root && root.dragAppId !== "") ? true : false
      x: root ? root.dropIndicatorX : 0
      anchors.verticalCenter: row.verticalCenter
      width: Style.space(2)
      height: root ? (root.iconSize + Style.space(4)) : 36
      radius: 1
      color: Color.bar.active
      z: 10
    }
  }
}
