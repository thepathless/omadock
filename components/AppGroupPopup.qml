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
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
  radius: Style.cornerRadius
  padding: Style.space(6)

  property bool isEditingName: false

  onActiveGroupChanged: {
    isEditingName = false
  }

  readonly property int cols: Math.min(4, Math.max(2, appList.length <= 4 ? 2 : (appList.length <= 9 ? 3 : 4)))
  readonly property real cellWidth: Style.space(64)
  readonly property real cellHeight: Style.space(70)
  readonly property real gridContentWidth: (cols * cellWidth) + ((cols - 1) * Style.space(6))
  readonly property real headerWidth: Style.space(160)
  readonly property real contentW: Math.max(headerWidth, gridContentWidth) + contentLeftInset + contentRightInset + Style.space(12)
  readonly property real contentH: mainColumn.implicitHeight + contentTopInset + contentBottomInset + Style.space(8)

  width: (root && root.activeAppGroupId !== "") ? contentW : 0
  height: (root && root.activeAppGroupId !== "") ? contentH : 0

  anchors.bottom: targetCard ? targetCard.top : undefined
  anchors.bottomMargin: Style.space(6)
  x: Math.max(Style.gapsOut, Math.min((targetWindow ? targetWindow.width : 1920) - width - Style.gapsOut, (root ? root.activeAppGroupX : 0) - width / 2))

  Column {
    id: mainColumn
    spacing: Style.space(6)
    anchors.left: parent.left
    anchors.leftMargin: appGroupPopup.contentLeftInset + Style.space(6)
    anchors.right: parent.right
    anchors.rightMargin: appGroupPopup.contentRightInset + Style.space(6)
    anchors.top: parent.top
    anchors.topMargin: appGroupPopup.contentTopInset + Style.space(4)

    // Header: Title with inline rename and count badge
    Item {
      width: parent.width
      height: Style.space(26)

      Row {
        id: titleRow
        visible: !appGroupPopup.isEditingName
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          id: titleLabel
          text: (appGroupPopup.activeGroup && appGroupPopup.activeGroup.name) ? appGroupPopup.activeGroup.name : "Folder"
          textFormat: Text.PlainText
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
          maximumLineCount: 1
        }

        Text {
          text: "(" + appGroupPopup.appList.length + ")"
          textFormat: Text.PlainText
          color: Util.alpha(Color.menu.text, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      MouseArea {
        anchors.fill: titleRow
        visible: !appGroupPopup.isEditingName
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          appGroupPopup.isEditingName = true
          nameInput.text = titleLabel.text
          Qt.callLater(function() {
            nameInput.forceActiveFocus()
            nameInput.selectAll()
          })
        }
      }

      // Inline Name Input
      Rectangle {
        visible: appGroupPopup.isEditingName
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(24)
        radius: Style.cornerRadius
        color: Util.alpha(Color.menu.background, 0.5)
        border.color: Color.bar.active
        border.width: 1

        TextInput {
          id: nameInput
          anchors.fill: parent
          anchors.margins: Style.space(4)
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          verticalAlignment: TextInput.AlignVCenter
          selectByMouse: true
          onAccepted: {
            if (root && appGroupPopup.activeGroup && text.trim() !== "") {
              root.renameAppGroup(appGroupPopup.activeGroup.id, text.trim())
            }
            appGroupPopup.isEditingName = false
          }
          Keys.onEscapePressed: {
            appGroupPopup.isEditingName = false
          }
        }
      }
    }

    // Grid of Contained Applications
    Grid {
      id: appGrid
      columns: appGroupPopup.cols
      spacing: Style.space(6)
      anchors.horizontalCenter: parent.horizontalCenter

      Repeater {
        model: appGroupPopup.appList
        delegate: Item {
          id: cellItem
          width: appGroupPopup.cellWidth
          height: appGroupPopup.cellHeight

          readonly property string appId: String(modelData || "")
          readonly property string appName: root ? DockModel.resolveAppName(root.appLibrary, root.appRows, cellItem.appId) : cellItem.appId
          readonly property string appIconSrc: {
            if (root && root.appLibrary) {
              var s = DockModel.resolveAppIcon(root.appLibrary, root.appRows, cellItem.appId)
              if (s) return s
            }
            return Quickshell.iconPath("application-x-executable", true)
          }

          Rectangle {
            id: cellBg
            anchors.fill: parent
            radius: Style.cornerRadius
            color: cellHover.hovered ? Util.alpha(Color.menu.text, 0.08) : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }

            Column {
              anchors.centerIn: parent
              spacing: Style.space(4)
              width: parent.width - Style.space(8)

              Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(36)
                height: Style.space(36)
                source: cellItem.appIconSrc
                sourceSize: Qt.size(width * 2, height * 2)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
              }

              Text {
                width: parent.width
                text: cellItem.appName
                textFormat: Text.PlainText
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Math.max(9, Style.font.caption - 1)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
              }
            }

            HoverHandler { id: cellHover }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  // Right click: ungroup this app from the folder
                  if (root && appGroupPopup.activeGroup) {
                    root.removeAppFromGroup(appGroupPopup.activeGroup.id, cellItem.appId)
                  }
                } else {
                  // Left click: launch or focus app
                  if (root) {
                    root.activate(cellItem.appId)
                    root.closeAppGroup()
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
