import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

BorderSurface {
  id: appGroupPopup

  property var rootRef: null
  readonly property var root: rootRef
  // The DockPopupWindow hosting this popup; maps drag positions to the dock.
  property var popupWindow: null

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
        border.color: Color.accent
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

          readonly property var root: appGroupPopup.root
          readonly property string appId: String(modelData || "")
          readonly property string appName: root ? DockModel.resolveAppName(root.appLibrary, root.appRows, cellItem.appId) : cellItem.appId
          // Cell badges sum the id spellings of this one app.
          readonly property int notificationCount: {
            if (!root || !root.showNotificationBadges) return 0
            return DockModel.groupBadgeTotal([cellItem.appId], root.notificationBadges)
          }
          readonly property string appIconSrc: {
            if (root && root.appLibrary) {
              var s = DockModel.resolveAppIcon(root.appLibrary, root.appRows, cellItem.appId)
              if (s) return s
            }
            return Quickshell.iconPath("application-x-executable", true)
          }

          property real dragStartX: 0
          property real dragStartY: 0
          property bool isDragging: false
          property bool _dragJustEnded: false

          // Per-window state, same reading as the dock's own indicator row.
          readonly property var appEntry: root ? root.entryForId(cellItem.appId) : null
          readonly property var appWindows: appEntry ? (appEntry.windowList || []) : []
          function isWinMinimized(w) {
            return !!w && ((w.isMinimized === true) || (root && root.liveWsNameOf(w) === root.minimizedWorkspace))
          }
          function isWinActive(w) {
            return !!w && !!w.address && !!root && w.address === root.activeWindowAddress
          }

          Rectangle {
            id: cellBg
            anchors.fill: parent
            radius: Style.cornerRadius
            color: cellHover.hovered ? Util.alpha(Color.menu.text, 0.08) : "transparent"
            opacity: cellItem.isDragging ? 0.35 : 1.0
            Behavior on color { ColorAnimation { duration: 100 } }
            Behavior on opacity { NumberAnimation { duration: 100 } }

            Column {
              anchors.centerIn: parent
              spacing: Style.space(4)
              width: parent.width - Style.space(8)

              // groupIconEffects decides whether the dock's icon style reaches
              // the opened group ("theme") or its icons stay original ("none").
              Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(36)
                height: Style.space(36)

                DockIconArt {
                  anchors.fill: parent
                  source: cellItem.appIconSrc
                  renderSize: Style.space(36)
                  iconStyle: root && root.groupIconEffects !== "none" ? root.iconStyle : "original"
                  // The popup sits on the menu surface, not the dock card.
                  tint: root ? root.tintFor(root.iconTint, Color.menu.text, Color.menu.background) : Color.menu.text
                  grid: root ? root.iconGrid : 16
                  contrast: root ? root.iconContrast : 0
                  strength: root ? root.iconStrength : 1
                  showOriginal: root ? (root.iconHoverOriginal && cellMouseArea.containsMouse) : false
                  hoverFx: root ? root.hoverFx : null
                }

                // Same mark as a dock badge, sitting on the menu surface.
                Rectangle {
                  visible: cellItem.notificationCount > 0
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.rightMargin: -Style.space(3)
                  anchors.topMargin: -Style.space(3)
                  width: Math.max(Style.space(17), cellBadgeText.implicitWidth + Style.space(8))
                  height: Style.space(17)
                  radius: height / 2
                  color: Color.accent
                  border.width: 1
                  border.color: Color.menu.background
                  z: 2
                  Text {
                    id: cellBadgeText
                    anchors.centerIn: parent
                    text: cellItem.notificationCount > 99 ? "99+" : String(cellItem.notificationCount)
                    textFormat: Text.PlainText
                    color: root && root.isLight(Color.accent) ? "#12100f" : "#f2efec"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(10)
                    font.bold: true
                  }
                }
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

              // Running/minimized state, one mark per window like the dock:
              // active bar, open dot, parked hollow dot.
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(2)
                visible: cellItem.appWindows.length > 0
                Repeater {
                  model: Math.min(3, cellItem.appWindows.length)
                  delegate: DockIndicator {
                    readonly property var winObj: cellItem.appWindows[index]
                    readonly property bool winMin: cellItem.isWinMinimized(winObj)
                    readonly property bool winActive: !winMin && cellItem.isWinActive(winObj)
                    rootRef: root
                    anchors.verticalCenter: parent.verticalCenter
                    dense: true
                    kind: winActive ? "active" : (winMin ? "minimized" : "window")
                  }
                }
              }
            }

            HoverHandler { id: cellHover }

            MouseArea {
              id: cellMouseArea
              anchors.fill: parent
              // Hover feeds "show original on hover" for the icon above.
              hoverEnabled: true
              cursorShape: cellItem.isDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton

              onPressed: function(mouse) {
                if (mouse.button === Qt.LeftButton) {
                  cellItem.dragStartX = mouse.x
                  cellItem.dragStartY = mouse.y
                  cellItem.isDragging = false
                  cellItem._dragJustEnded = false
                }
              }

              onPositionChanged: function(mouse) {
                if (cellMouseArea.pressed && (mouse.buttons & Qt.LeftButton)) {
                  var dx = mouse.x - cellItem.dragStartX
                  var dy = mouse.y - cellItem.dragStartY
                  var dist = Math.sqrt(dx * dx + dy * dy)
                  if (!cellItem.isDragging && dist > 10) {
                    cellItem.isDragging = true
                    if (root && appGroupPopup.activeGroup) {
                      root.dragAppId = cellItem.appId
                      root.dragSourceGroupId = appGroupPopup.activeGroup.id
                      root.dropBeforeId = ""
                      root.dropTargetAppId = ""
                      root.dropTargetGroupId = ""
                    }
                  }
                  if (cellItem.isDragging && root && root.dockCardComp && appGroupPopup.popupWindow) {
                    // The popup is its own surface: go through dock-window
                    // coordinates to reach the card.
                    var winPt = appGroupPopup.popupWindow.toDockWindow(cellItem, mouse.x, mouse.y)
                    var cardPt = root.dockCardComp.mapFromItem(root.contentItemRef, winPt.x, winPt.y)
                    root.dockCardComp.handleDragMoved(cellItem.appId, cardPt.x, cardPt.y)
                  }
                }
              }

              onReleased: function(mouse) {
                if (cellItem.isDragging) {
                  cellItem.isDragging = false
                  cellItem._dragJustEnded = true
                  if (root && root.dockCardComp) {
                    root.dockCardComp.handleDragDropped(cellItem.appId)
                  }
                  if (root) {
                    root.closeAppGroup()
                  }
                }
              }

              onCanceled: {
                if (cellItem.isDragging) {
                  cellItem.isDragging = false
                  cellItem._dragJustEnded = true
                  if (root && root.dockCardComp) {
                    root.dockCardComp.handleDragDropped(cellItem.appId)
                  }
                  if (root) {
                    root.closeAppGroup()
                  }
                }
              }

              onClicked: function(mouse) {
                if (cellItem._dragJustEnded) {
                  cellItem._dragJustEnded = false
                  return
                }
                if (mouse.button === Qt.RightButton) {
                  // Right click: ungroup this app from the folder
                  if (root && appGroupPopup.activeGroup) {
                    root.removeAppFromGroup(appGroupPopup.activeGroup.id, cellItem.appId)
                  }
                } else if (mouse.button === Qt.LeftButton) {
                  // Launch, focus, or park the app. The popup stays open so
                  // foldered apps can be switched and toggled repeatedly
                  // without reopening the folder each time.
                  if (root) root.activate(cellItem.appId)
                }
              }
            }
          }
        }
      }
    }
  }
}
