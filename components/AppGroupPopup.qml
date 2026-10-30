import QtQuick 6.11
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel
import "strings"

BorderSurface {
  id: appGroupPopup

  property var rootRef: null
  readonly property var root: rootRef
  readonly property var motion: appGroupPopup.root ? appGroupPopup.root.motion : null
  // The DockPopupWindow hosting this popup; maps drag positions to the dock.
  property var popupWindow: null

  readonly property var activeGroup: root ? root.activeAppGroupData : null
  readonly property var appList: (activeGroup && DockModel.isList(activeGroup.apps)) ? DockModel.toArray(activeGroup.apps) : []

  visible: root ? (root.activeAppGroupId !== "" && root.dockVisible) : false

  z: 100

  // The popup belongs to the dock it drops from, not to the theme's menu; the
  // rule (fill, ink, body) is DockStyleLogic.popupSurface. The card's own
  // corner radius (0 for a square look) is set below.
  readonly property var material: root ? root.popupSurface() : null
  readonly property color ink: material ? material.ink : Color.menu.text
  readonly property color surfaceColor: material ? material.surface : Color.menu.background

  color: surfaceColor
  borderSpec: root ? Border.flat(Util.alpha(ink, 0.14), 1)
                   : Border.surfaceSpec("menu", "border", Color.menu.border, 1)
  radius: root ? root.effectiveCardRadius : Style.cornerRadius
  padding: Style.space(6)

  property bool isEditingName: false

  // An app dragged out of the group: the popup gives way to the dock (it
  // stays open, invisible, as the drag's surface until the button is let
  // go), and the app's icon follows the pointer, drawn here and in the dock
  // at the same place (DockLift.beginIcon), each surface showing its part.
  property bool draggingOut: false
  opacity: appGroupPopup.draggingOut ? 0 : 1
  Behavior on opacity { NumberAnimation { duration: (appGroupPopup.motion ? appGroupPopup.motion.fast : 0) } }
  readonly property var lift: (root && root.dockCard) ? root.dockCard.liftRef : null
  Item {
    id: outCopy
    parent: appGroupPopup.popupWindow ? appGroupPopup.popupWindow.contentItem : appGroupPopup
    readonly property var lift: appGroupPopup.lift
    visible: appGroupPopup.draggingOut && !!lift && lift.iconCopy
    readonly property point at: {
      var l = outCopy.lift
      if (!l || !root || !appGroupPopup.popupWindow) return Qt.point(0, 0)
      var w = root.dockCard.mapToItem(root.contentItemRef, l._x + l._iconX, l._y + l._iconY)
      return appGroupPopup.popupWindow.fromDockWindow(w.x, w.y)
    }
    width: root ? root.baseIconArt : 0
    height: width
    x: Math.round(outCopy.at.x - width / 2)
    y: Math.round(outCopy.at.y - height / 2)
    z: 1000
    opacity: outCopy.lift ? outCopy.lift._shownOpacity : 1
    scale: outCopy.lift ? outCopy.lift.copyScale : 1
    LiftIcon {
      anchors.fill: parent
      dockRoot: root
      source: outCopy.lift ? outCopy.lift.iconSource : ""
    }
  }

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
          text: (appGroupPopup.activeGroup && appGroupPopup.activeGroup.name) ? appGroupPopup.activeGroup.name : Tr.t("common.folder", "Folder")
          textFormat: Text.PlainText
          color: appGroupPopup.ink
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
          maximumLineCount: 1
        }

        Text {
          text: "(" + appGroupPopup.appList.length + ")"
          textFormat: Text.PlainText
          color: Util.alpha(appGroupPopup.ink, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      MouseArea {
        anchors.fill: titleRow
        visible: !appGroupPopup.isEditingName
        cursorShape: Qt.PointingHandCursor
        onClicked: appGroupPopup.isEditingName = true
      }

      // Inline Name Input. The TextInput is built only while renaming: a field
      // that is merely displayed takes Qt's clipboard subscription (see
      // ContextRenameRow.qml), so an open group popup must not hold one.
      Rectangle {
        visible: appGroupPopup.isEditingName
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(24)
        radius: Style.cornerRadius
        color: Util.alpha(appGroupPopup.ink, 0.10)
        border.color: Color.accent
        border.width: 1

        Loader {
          anchors.fill: parent
          anchors.margins: Style.space(4)
          active: appGroupPopup.isEditingName
          onLoaded: {
            item.text = titleLabel.text
            Qt.callLater(function() {
              if (!item) return
              item.forceActiveFocus()
              item.selectAll()
            })
          }
          sourceComponent: Component {
            TextInput {
              color: appGroupPopup.ink
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
            color: cellHover.hovered ? Util.alpha(appGroupPopup.ink, 0.08) : "transparent"
            Behavior on color { ColorAnimation { duration: (appGroupPopup.motion ? appGroupPopup.motion.fast : 0) } }
            Behavior on opacity { NumberAnimation { duration: (appGroupPopup.motion ? appGroupPopup.motion.fast : 0) } }

            Column {
              anchors.centerIn: parent
              spacing: Style.space(4)
              width: parent.width - Style.space(8)

              // groupIconEffects decides whether the dock's icon style reaches
              // the opened group ("theme") or its icons stay original ("none").
              Item {
                id: cellIcon
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(36)
                height: Style.space(36)

                DockIconArt {
                  anchors.fill: parent
                  source: cellItem.appIconSrc
                  renderSize: Style.space(36)
                  iconStyle: root && root.groupIconEffects !== "none" ? root.iconStyle : "original"
                  // The popup sits on the dock's own surface, not the theme menu.
                  tint: root ? root.tintFor(root.iconTint, appGroupPopup.ink, appGroupPopup.surfaceColor) : Color.menu.text
                  grid: root ? root.iconGrid : 16
                  outputScale: root ? root.outputScale : 1
                  contrast: root ? root.iconContrast : 0
                  strength: root ? root.iconStrength : 1
                  showOriginal: root ? (root.iconHoverOriginal && cellMouseArea.containsMouse) : false
                  hovered: cellHover.hovered && !cellItem.isDragging
                  hoverFx: root ? root.hoverFx : null

                  // Same mark as a dock badge, on the menu surface; it rides
                  // the hover effect with the icon, like the dock's.
                  overlay: [
                    BadgeMark {
                      rootRef: cellItem.root
                      anchorRef: parent
                      count: cellItem.notificationCount
                      rim: appGroupPopup.surfaceColor
                    }
                  ]
                }
              }

              Text {
                width: parent.width
                text: cellItem.appName
                textFormat: Text.PlainText
                color: appGroupPopup.ink
                font.family: Style.font.family
                font.pixelSize: Math.max(9, Style.font.caption - 1)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
              }

              // Running/minimized state, one mark per window like the dock:
              // active bar, open dot, parked hollow dot, at the dock's own
              // size and spacing (DockMarkGeometry).
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(3)
                visible: cellItem.appWindows.length > 0
                Repeater {
                  model: Math.min(3, cellItem.appWindows.length)
                  delegate: DockIndicator {
                    readonly property var winObj: cellItem.appWindows[index]
                    readonly property bool winMin: cellItem.isWinMinimized(winObj)
                    readonly property bool winActive: !winMin && cellItem.isWinActive(winObj)
                    rootRef: cellItem.root
                    anchors.verticalCenter: parent.verticalCenter
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
                    if (root && appGroupPopup.activeGroup && appGroupPopup.lift) {
                      // The pointer keeps its place on the icon, at the dock's size.
                      var c = cellIcon.mapToItem(cellMouseArea, cellIcon.width / 2, cellIcon.height / 2)
                      var k = root.baseIconArt / Math.max(1, cellIcon.width)
                      appGroupPopup.lift.beginIcon("popup:" + appGroupPopup.activeGroup.id, cellItem.appIconSrc,
                        (mouse.x - c.x) * k, (mouse.y - c.y) * k)
                      appGroupPopup.draggingOut = true
                    }
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
                  // Right click: the app's own menu, as on the dock, over this
                  // cell. The group closes first: the menu's surface takes the
                  // focus grab and would dismiss it anyway. Closing destroys
                  // this cell, so everything the menu needs is read before.
                  if (root && appGroupPopup.activeGroup && appGroupPopup.popupWindow) {
                    var dock = root
                    var group = appGroupPopup.activeGroup
                    var app = cellItem.appId
                    var at = appGroupPopup.popupWindow.toDockWindow(cellItem, cellItem.width / 2, 0)
                    dock.closeAppGroup()
                    dock.openContext(app, at.x, at.y, group)
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
