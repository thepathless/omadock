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
  readonly property var appList: (activeGroup && DockModel.isList(activeGroup.apps)) ? DockModel.toArray(activeGroup.apps) : []

  visible: root ? (root.activeAppGroupId !== "" && root.dockVisible) : false
  opacity: (root && root.activeAppGroupId !== "" && root.dockVisible) ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 120 } }

  z: 100
  color: Util.alpha(Color.menu.background, 0.94)
  borderSpec: Border.flat(Util.alpha(root ? root.dockForeground : Color.menu.border, 0.22), 1.5)
  radius: Style.space(20)
  padding: Style.space(12)

  property bool isEditingName: false
  property bool showSettings: false
  onActiveGroupChanged: {
    isEditingName = false
    showSettings = false
  }

  readonly property int cols: (activeGroup && activeGroup.cols) ? activeGroup.cols : Math.min(4, Math.max(2, appList.length <= 4 ? 2 : (appList.length <= 9 ? 3 : 4)))
  readonly property real cellWidth: Style.space(76)
  readonly property real cellHeight: Style.space(80)
  readonly property real contentW: Math.max(Style.space(260), (cols * cellWidth) + ((cols - 1) * Style.space(6)) + contentLeftInset + contentRightInset + Style.space(16))
  readonly property real contentH: mainColumn.implicitHeight + contentTopInset + contentBottomInset

  width: (root && root.activeAppGroupId !== "") ? contentW : 0
  height: (root && root.activeAppGroupId !== "") ? contentH : 0

  anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
  anchors.bottom: targetCard ? targetCard.top : undefined
  anchors.bottomMargin: Style.space(24)

  Column {
    id: mainColumn
    spacing: Style.space(6)
    width: parent.width - appGroupPopup.contentLeftInset - appGroupPopup.contentRightInset
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: appGroupPopup.contentTopInset

    // Symmetrical Android/iOS Folder Header
    Item {
      width: parent.width
      height: Style.space(32)

      // App Count Badge (left-aligned)
      Text {
        id: countBadge
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: String(appGroupPopup.appList.length) + (appGroupPopup.appList.length === 1 ? " app" : " apps")
        textFormat: Text.PlainText
        color: Util.alpha(Color.menu.text, 0.45)
        font.family: Style.font.family
        font.pixelSize: Math.max(10, Style.font.caption - 1)
      }

      // Folder Settings Toggle Button (right-aligned)
      Rectangle {
        id: settingsBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(24)
        height: Style.space(24)
        radius: Style.space(6)
        color: appGroupPopup.showSettings ? Util.alpha(Color.bar.active, 0.22) : (settingsHover.hovered ? Util.alpha(Color.menu.text, 0.12) : "transparent")

        HoverHandler { id: settingsHover }

        Text {
          anchors.centerIn: parent
          text: "⚙"
          textFormat: Text.PlainText
          color: appGroupPopup.showSettings ? Color.accent : (settingsHover.hovered ? Color.menu.text : Util.alpha(Color.menu.text, 0.6))
          font.pixelSize: Style.font.caption
          rotation: appGroupPopup.showSettings ? 45 : 0
          Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            appGroupPopup.showSettings = !appGroupPopup.showSettings
            if (appGroupPopup.isEditingName) appGroupPopup.isEditingName = false
          }
        }
      }

      // Centered Title & Inline Rename Container
      Item {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(110), Math.max(Style.space(120), titleRow.implicitWidth + Style.space(16)))
        height: parent.height

        HoverHandler { id: titleHover }

        MouseArea {
          anchors.fill: parent
          enabled: !appGroupPopup.isEditingName
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            appGroupPopup.isEditingName = true
            nameInput.text = (appGroupPopup.activeGroup && appGroupPopup.activeGroup.name) ? appGroupPopup.activeGroup.name : "Folder"
            Qt.callLater(function() {
              nameInput.forceActiveFocus()
              nameInput.selectAll()
            })
          }
        }

        // View Mode: Centered title with hover edit pencil
        Row {
          id: titleRow
          visible: !appGroupPopup.isEditingName
          anchors.centerIn: parent
          spacing: Style.space(5)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (appGroupPopup.activeGroup && appGroupPopup.activeGroup.name) ? appGroupPopup.activeGroup.name : "Folder"
            textFormat: Text.PlainText
            color: titleHover.hovered ? Color.accent : Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body + 2
            font.bold: true
            elide: Text.ElideRight
            maximumLineCount: 1
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: titleHover.hovered
            text: "✎"
            textFormat: Text.PlainText
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // Inline Name Input Field with reliable focus & commit
        Rectangle {
          visible: appGroupPopup.isEditingName
          anchors.fill: parent
          radius: Style.space(6)
          color: Util.alpha(Color.bar.background, 0.65)
          border.color: Color.accent
          border.width: 1.5

          FocusScope {
            anchors.fill: parent
            focus: appGroupPopup.isEditingName

            TextInput {
              id: nameInput
              anchors.left: parent.left
              anchors.right: commitBtn.left
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              selectByMouse: true
              activeFocusOnPress: true
              focus: true
              cursorVisible: activeFocus

              onActiveFocusChanged: {
                if (!activeFocus && appGroupPopup.isEditingName) {
                  if (root && appGroupPopup.activeGroup && text.trim() !== "") {
                    root.updateAppGroupName(appGroupPopup.activeGroup.id, text.trim())
                  }
                  appGroupPopup.isEditingName = false
                }
              }

              Keys.onReturnPressed: {
                if (root && appGroupPopup.activeGroup && text.trim() !== "") {
                  root.updateAppGroupName(appGroupPopup.activeGroup.id, text.trim())
                }
                appGroupPopup.isEditingName = false
              }
              Keys.onEscapePressed: {
                appGroupPopup.isEditingName = false
              }
              onAccepted: {
                if (root && appGroupPopup.activeGroup && text.trim() !== "") {
                  root.updateAppGroupName(appGroupPopup.activeGroup.id, text.trim())
                }
                appGroupPopup.isEditingName = false
              }
            }

            Rectangle {
              id: commitBtn
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(22)
              height: Style.space(22)
              radius: Style.space(4)
              color: commitHover.hovered ? Color.accent : Util.alpha(Color.accent, 0.22)

              HoverHandler { id: commitHover }

              Text {
                anchors.centerIn: parent
                text: "✓"
                textFormat: Text.PlainText
                color: commitHover.hovered ? "#ffffff" : Color.accent
                font.bold: true
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root && appGroupPopup.activeGroup && nameInput.text.trim() !== "") {
                    root.updateAppGroupName(appGroupPopup.activeGroup.id, nameInput.text.trim())
                  }
                  appGroupPopup.isEditingName = false
                }
              }
            }
          }
        }
      }
    }

    // Expandable Folder Settings Panel
    Column {
      visible: appGroupPopup.showSettings
      width: parent.width
      spacing: Style.space(6)
      padding: Style.space(2)

      MenuDivider {}

      // Columns Selection Row
      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Columns:"
          textFormat: Text.PlainText
          color: Util.alpha(Color.menu.text, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: [2, 3, 4]
          delegate: Rectangle {
            width: Style.space(24)
            height: Style.space(20)
            radius: Style.space(3)
            readonly property bool isSelected: appGroupPopup.cols === modelData
            color: isSelected ? Color.accent : (colHover.hovered ? Util.alpha(Color.menu.text, 0.12) : Util.alpha(Color.menu.text, 0.06))

            HoverHandler { id: colHover }

            Text {
              anchors.centerIn: parent
              text: String(modelData)
              textFormat: Text.PlainText
              color: isSelected ? (Color.accent.hslLightness < 0.5 ? "#ffffff" : "#000000") : Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: isSelected
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root && appGroupPopup.activeGroup) {
                  root.updateAppGroupColumns(appGroupPopup.activeGroup.id, modelData)
                }
              }
            }
          }
        }
      }

      // Ungroup / Delete Folder Action
      Rectangle {
        width: parent.width
        height: Style.space(24)
        radius: Style.space(4)
        color: ungroupHover.hovered ? Util.alpha(Color.urgent || Color.bar.active, 0.18) : "transparent"
        border.color: Util.alpha(Color.urgent || Color.bar.active, 0.35)
        border.width: 1

        HoverHandler { id: ungroupHover }

        Row {
          anchors.centerIn: parent
          spacing: Style.space(4)

          Text {
            text: "Ungroup Folder"
            textFormat: Text.PlainText
            color: Color.urgent || Color.bar.active
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root && appGroupPopup.activeGroup) {
              root.ungroupAppGroup(appGroupPopup.activeGroup.id)
            }
          }
        }
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
      spacing: Style.space(6)
      anchors.horizontalCenter: parent.horizontalCenter

      Repeater {
        model: appGroupPopup.appList
        delegate: Rectangle {
          id: appCell
          width: appGroupPopup.cellWidth
          height: appGroupPopup.cellHeight
          radius: Style.space(12)
          color: cellHover.hovered ? Util.alpha(Color.bar.active, 0.20) : "transparent"
          Behavior on color { ColorAnimation { duration: 120 } }

          readonly property string appIdStr: String(modelData || "")
          readonly property var deskEntry: root ? DockModel.entryFor(root.appRows, appCell.appIdStr) : null
          readonly property string appName: (root && root.appLibrary) ? DockModel.resolveAppName(root.appLibrary, root.appRows, appCell.appIdStr) : ((deskEntry && deskEntry.name) ? deskEntry.name : appCell.appIdStr)
          readonly property string appIconName: (deskEntry && deskEntry.icon) ? deskEntry.icon : appCell.appIdStr

          readonly property string appIconSource: {
            if (root && root.appLibrary) {
              var src = DockModel.resolveAppIcon(root.appLibrary, root.appRows, appCell.appIdStr)
              if (src) return src
            }
            var p = Quickshell.iconPath(appCell.appIconName, true)
            if (p && p !== "") return p
            return Quickshell.iconPath("application-x-executable", true)
          }

          readonly property bool isRunning: {
            if (!root) return false
            var entry = root.entryForId(appCell.appIdStr)
            return entry ? entry.running === true : false
          }

          HoverHandler {
            id: cellHover
          }

          // Remove app from group button
          Rectangle {
            id: removeAppBtn
            visible: cellHover.hovered || removeHover.hovered
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.space(2)
            width: Style.space(16)
            height: Style.space(16)
            radius: width / 2
            color: removeHover.hovered ? (Color.urgent || "#e06c75") : Util.alpha(Color.bar.background, 0.75)
            border.color: Util.alpha(Color.menu.border, 0.5)
            border.width: 1
            z: 10

            HoverHandler { id: removeHover }

            Text {
              anchors.centerIn: parent
              text: "×"
              textFormat: Text.PlainText
              color: removeHover.hovered ? "#ffffff" : Util.alpha(Color.menu.text, 0.8)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                if (root && appGroupPopup.activeGroup) {
                  root.removeAppFromGroup(appGroupPopup.activeGroup.id, appCell.appIdStr)
                }
              }
            }
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
              width: Style.space(42)
              height: Style.space(42)
              anchors.horizontalCenter: parent.horizontalCenter

              Image {
                anchors.fill: parent
                source: appCell.appIconSource
                sourceSize: Qt.size(Style.space(84), Style.space(84))
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
