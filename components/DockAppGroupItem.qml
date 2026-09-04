import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

Item {
  id: gitem

  property var rootRef: null
  readonly property var root: rootRef

  property var groupData: null
  property real homeCenter: 0

  readonly property string groupId: (groupData && groupData.id) ? groupData.id : ""
  readonly property string groupName: (groupData && groupData.name) ? groupData.name : "Folder"
  readonly property var groupApps: (groupData && DockModel.isList(groupData.apps)) ? DockModel.toArray(groupData.apps) : []

  signal openGroupRequested(var gdata, real cx, real cy)
  signal menuRequested(var gdata, real cx, real cy)

  width: {
    if (!root) return 0
    if (root.waveHover) return Math.round(root.iconSlot * (1 + (gitem.magnifyScale - 1) * 0.70))
    return root.iconSlot
  }
  height: root ? root.iconSlot : 0
  z: Math.round(gitem.magnifyScale * 100)

  readonly property bool isOpen: root ? root.activeAppGroupId === gitem.groupId : false
  readonly property bool isDropTarget: (root && (root.dropTargetGroupId === gitem.groupId || root.dropTargetAppId === gitem.groupId))

  // Check if any app in this group is currently running
  readonly property bool hasRunningApps: {
    if (!root || !root.runningSection) return false
    var running = root.runningSection || []
    for (var a = 0; a < gitem.groupApps.length; a++) {
      var aid = gitem.groupApps[a]
      for (var r = 0; r < running.length; r++) {
        if (running[r] && (running[r].appId === aid || DockModel.isAppMatch(running[r].appId, aid))) {
          if (running[r].running) return true
        }
      }
    }
    return false
  }

  property real magnifyScale: {
    if (!root) return 1
    if (root.waveHover) return root.magnifyScaleAt(gitem.homeCenter)
    if (root.hoverEffect === "off") return 1
    return groupArea.containsMouse ? root.zoomPeak : 1
  }

  readonly property real waveNudgeX: 0

  Behavior on magnifyScale {
    NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
  }

  Item {
    id: iconSlot
    width: root ? root.iconSlot : 0
    height: root ? root.iconSlot : 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter

    Item {
      id: iconContainer
      width: root ? root.iconSize : 0
      height: root ? root.iconSize : 0
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: gitem.hasRunningApps ? Style.space(5) : Math.round((iconSlot.height - height) / 2)
      scale: gitem.magnifyScale
      transformOrigin: Item.Bottom

      // Drop target halo
      Rectangle {
        visible: gitem.isDropTarget
        anchors.centerIn: parent
        width: parent.width + Style.space(8)
        height: width
        radius: Style.space(6)
        color: Util.alpha(Color.bar.active, 0.22)
        border.color: Color.bar.active
        border.width: 1.5
        z: -1
        SequentialAnimation on opacity {
          running: gitem.isDropTarget
          loops: Animation.Infinite
          NumberAnimation { from: 0.5; to: 1.0; duration: 350; easing.type: Easing.InOutQuad }
          NumberAnimation { from: 1.0; to: 0.5; duration: 350; easing.type: Easing.InOutQuad }
        }
      }

      // Frosted Folder Tile Container (macOS / iOS Launchpad Folder style)
      Rectangle {
        id: folderTile
        anchors.fill: parent
        radius: Math.round(width * 0.26)
        color: Util.alpha(Color.bar.background, 0.65)
        border.width: 1
        border.color: Util.alpha(root ? root.dockForeground : Color.bar.border, 0.28)

        // Empty folder fallback icon
        Image {
          visible: gitem.groupApps.length === 0
          anchors.centerIn: parent
          width: Math.round(parent.width * 0.55)
          height: width
          source: Quickshell.iconPath("folder", true)
          fillMode: Image.PreserveAspectFit
          smooth: true
        }

        // 2x2 Mini Icons Grid Preview
        Grid {
          visible: gitem.groupApps.length > 0
          anchors.centerIn: parent
          columns: 2
          rows: 2
          spacing: Style.space(2)

          Repeater {
            model: gitem.groupApps.slice(0, 4)
            delegate: Item {
              id: miniCell
              readonly property real miniSize: Math.round(iconContainer.width * 0.36)
              width: miniSize
              height: miniSize

              readonly property string appIconName: {
                var dEntry = root ? DockModel.entryFor(root.appRows, modelData) : null
                if (dEntry && dEntry.icon) return dEntry.icon
                return String(modelData || "")
              }

              readonly property string miniSource: {
                if (root && root.appLibrary) {
                  var src = DockModel.resolveAppIcon(root.appLibrary, root.appRows, modelData)
                  if (src) return src
                }
                var p = Quickshell.iconPath(miniCell.appIconName, true)
                if (p && p !== "") return p
                return Quickshell.iconPath("application-x-executable", true)
              }

              Image {
                anchors.fill: parent
                source: miniCell.miniSource
                sourceSize: Qt.size(miniCell.miniSize * 2, miniCell.miniSize * 2)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
              }
            }
          }
        }
      }
    }
  }

  // Running indicator dot underneath the folder if any child app is running
  Rectangle {
    visible: gitem.hasRunningApps
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(1)
    anchors.horizontalCenter: parent.horizontalCenter
    width: Style.space(4)
    height: Style.space(4)
    radius: width / 2
    color: gitem.isOpen ? Color.bar.active : Util.alpha(root ? root.dockForeground : Color.bar.text, 0.75)
  }

  MouseArea {
    id: groupArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      var targetWin = root ? root.contentItemRef : null
      if (mouse.button === Qt.RightButton) {
        var mappedPos = targetWin ? gitem.mapToItem(targetWin, gitem.width / 2, 0) : null
        if (!mappedPos) return
        gitem.menuRequested(gitem.groupData, mappedPos.x, 0)
      } else {
        var centerPos = targetWin ? gitem.mapToItem(targetWin, gitem.width / 2, 0) : null
        if (!centerPos) return
        gitem.openGroupRequested(gitem.groupData, centerPos.x, centerPos.y)
      }
    }
  }

  // Hover tooltip
  HoverTooltip {
    text: gitem.groupName + " (" + gitem.groupApps.length + (gitem.groupApps.length === 1 ? " app)" : " apps)")
    hovered: groupArea.containsMouse
    blocked: (!root || !root.showTooltips || root.activeAppGroupId !== "")
    showTooltips: root ? root.showTooltips : true
    tooltipDelay: root ? root.tooltipDelay : 450
    contextAppId: root ? root.contextAppId : ""
    x: (gitem.width - width) / 2
    y: -height - Style.space(8)
  }
}
