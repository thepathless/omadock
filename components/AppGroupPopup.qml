import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

BorderSurface {
  id: appGroupPopup

  property var rootRef: null
  readonly property var root: rootRef
  property var targetCard: root ? (root.dockCardComp || root.dockCard) : null
  property var targetWindow: root ? root.contentItemRef : null

  readonly property var activeGroup: root ? root.activeAppGroupData : null
  readonly property var appList: (activeGroup && Array.isArray(activeGroup.apps)) ? activeGroup.apps : []

  visible: root ? (root.activeAppGroupId !== "" && root.dockVisible) : false
  opacity: (root && root.activeAppGroupId !== "" && root.dockVisible) ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 120 } }

  z: 100
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
  radius: Style.cornerRadius
  padding: Style.space(6)

  readonly property int cols: Math.min(4, Math.max(3, appList.length <= 4 ? 2 : (appList.length <= 9 ? 3 : 4)))
  readonly property real cellWidth: Style.space(72)
  readonly property real contentW: Math.max(Style.space(220), (cols * cellWidth) + ((cols - 1) * Style.space(4)) + contentLeftInset + contentRightInset + Style.space(12))
  readonly property real contentH: mainColumn.implicitHeight + contentTopInset + contentBottomInset

  width: (root && root.activeAppGroupId !== "") ? contentW : 0
  height: (root && root.activeAppGroupId !== "") ? contentH : 0

  anchors.bottom: targetCard ? targetCard.top : undefined
  anchors.bottomMargin: Style.space(6)
  x: Math.max(Style.gapsOut, Math.min((targetWindow ? targetWindow.width : 1920) - width - Style.gapsOut, (root ? root.activeAppGroupX : 0) - width / 2))

  Column {
    id: mainColumn
    spacing: Style.space(4)
    width: parent.width - appGroupPopup.contentLeftInset - appGroupPopup.contentRightInset
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: appGroupPopup.contentTopInset

    // Group Header
    Row {
      width: parent.width
      height: Style.space(24)
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: (appGroupPopup.activeGroup && appGroupPopup.activeGroup.name) ? appGroupPopup.activeGroup.name : "App Group"
        textFormat: Text.PlainText
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
        width: parent.width - countText.width - Style.space(8)
      }

      Text {
        id: countText
        anchors.verticalCenter: parent.verticalCenter
        text: String(appGroupPopup.appList.length)
        textFormat: Text.PlainText
        color: Util.alpha(Color.menu.text, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    MenuDivider {}

    // Empty state
    Text {
      visible: appGroupPopup.appList.length === 0
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "No apps in this group"
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      padding: Style.space(16)
    }

    // Grid of App Icons
    Grid {
      id: appsGrid
      visible: appGroupPopup.appList.length > 0
      columns: appGroupPopup.cols
      spacing: Style.space(4)
      anchors.horizontalCenter: parent.horizontalCenter

      Repeater {
        model: appGroupPopup.appList
        delegate: Rectangle {
          id: appCell
          width: appGroupPopup.cellWidth
          height: appGroupPopup.cellHeight
          radius: Style.radius(2)
          color: cellHover.hovered ? Util.alpha(Color.bar.active, 0.16) : "transparent"

          readonly property string appIdStr: String(modelData || "")
          readonly property var deskEntry: root ? DockModel.entryFor(root.appRows, appCell.appIdStr) : null
          readonly property string appName: (deskEntry && deskEntry.name) ? deskEntry.name : appCell.appIdStr
          readonly property string appIconName: (deskEntry && deskEntry.icon) ? deskEntry.icon : appCell.appIdStr

          readonly property string appIconSource: {
            var p = Quickshell.iconPath(appCell.appIconName, true)
            if (p && p !== "") return p
            return Quickshell.iconPath("application-x-executable", true)
          }

          readonly property bool isRunning: {
            if (!root || !root.runningSection) return false
            var running = root.runningSection || []
            for (var r = 0; r < running.length; r++) {
              if (running[r] && (running[r].appId === appCell.appIdStr || DockModel.isAppMatch(running[r].appId, appCell.appIdStr))) {
                if (running[r].running) return true
              }
            }
            return false
          }

          HoverHandler {
            id: cellHover
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton) {
                // Open standard context menu for this app
                if (root) {
                  var mapped = appCell.mapToItem(targetWindow, appCell.width / 2, 0)
                  root.openContext(appCell.appIdStr, mapped ? mapped.x : 0, mapped ? mapped.y : 0)
                  root.closeAppGroup()
                }
              } else {
                if (root) {
                  // If running, activate its window; otherwise launch it
                  root.activate(appCell.appIdStr)
                  root.closeAppGroup()
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(3)
            width: parent.width - Style.space(4)

            Item {
              width: Style.space(38)
              height: Style.space(38)
              anchors.horizontalCenter: parent.horizontalCenter

              Image {
                anchors.fill: parent
                source: appCell.appIconSource
                sourceSize: Qt.size(Style.space(76), Style.space(76))
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
              }

              // Running indicator dot
              Rectangle {
                visible: appCell.isRunning
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -Style.space(2)
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(4)
                height: Style.space(4)
                radius: width / 2
                color: Color.bar.active
              }
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: appCell.appName
              textFormat: Text.PlainText
              color: cellHover.hovered ? Color.menu.text : Util.alpha(Color.menu.text, 0.85)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              maximumLineCount: 1
            }
          }
        }
      }
    }
  }
}
