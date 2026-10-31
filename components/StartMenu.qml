import QtQuick 6.11
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

// The apps button's anchored launcher ("appsButtonAction": "start"): a panel
// that stands above the button it was opened from, Windows-style, listing
// every installed app alphabetically in two columns.
//
// Chrome is the dock's own popup material (DockStyleLogic.popupSurface), not
// the theme's menu, so it reads as the same product as the folder and group
// popups. Deliberately only the app list: no search field, no pinned tiles,
// no settings rows - the content the button already produces, laid out.
BorderSurface {
  id: startMenu

  property var rootRef: null
  readonly property var root: rootRef
  // The DockPopupWindow hosting this panel, for its room above the dock.
  property var popupWindow: null

  visible: root ? (root.appsMenuHost.open && root.dockVisible) : false
  z: 100

  readonly property var material: root ? root.popupSurface() : null
  readonly property color ink: material ? material.ink : Color.menu.text
  readonly property color surfaceColor: material ? material.surface : Color.menu.background

  color: surfaceColor
  borderSpec: !root ? Border.surfaceSpec("menu", "border", Color.menu.border, 1)
    : !root.showBackground ? Border.flat(Util.alpha(ink, 0.45), 1)
    : root.showBorder ? Border.flat(Util.alpha(ink, 0.14), 1)
    : Border.none()
  radius: root ? root.effectiveCardRadius : Style.cornerRadius
  padding: Style.space(6)

  // Every installed app the dock already holds (root.appRows), by name, once.
  // Entries can be wrapped ({ entry }) by the host library, which is why they
  // are unwrapped the way DockModel.entryFor does.
  readonly property var apps: {
    var rows = root ? root.appRows : []
    var list = []
    for (var i = 0; i < (rows ? rows.length : 0); i++) {
      var e = rows[i] && rows[i].entry ? rows[i].entry : rows[i]
      if (e && e.id) list.push(e)
    }
    list.sort(function(a, b) {
      var an = String(a.name || a.id).toLowerCase()
      var bn = String(b.name || b.id).toLowerCase()
      return an < bn ? -1 : (an > bn ? 1 : 0)
    })
    return list
  }

  readonly property int columns: 2
  readonly property real rowHeight: Style.space(34)
  readonly property real rowWidth: Style.space(196)
  readonly property real innerWidth: startMenu.columns * startMenu.rowWidth + (startMenu.columns - 1) * Style.space(2)
  // The room above the dock, less a margin so the panel never touches the
  // surface's own top edge, and a deliberate ceiling: a list longer than a
  // Start menu's own panel scrolls rather than standing the height of the
  // screen.
  readonly property real maxHeight: startMenu.popupWindow
    ? Math.min(Style.space(560), Math.max(Style.space(160), startMenu.popupWindow.implicitHeight - Style.space(12)))
    : Style.space(520)

  width: visible ? startMenu.innerWidth + startMenu.contentLeftInset + startMenu.contentRightInset : 0
  height: visible
    ? Math.min(startMenu.maxHeight, appsGrid.implicitHeight + startMenu.contentTopInset + startMenu.contentBottomInset)
    : 0

  // Escape closes it. The window holds the keyboard while the panel is open,
  // so the key lands here rather than in whatever window had the focus.
  focus: true
  Keys.onEscapePressed: if (startMenu.root) startMenu.root.appsMenuHost.close()

  function activate(entry) {
    if (!startMenu.root || !entry) return
    startMenu.root.launchApp(entry.id, null)
    startMenu.root.appsMenuHost.close()
  }

  // Focus is taken after the surface is mapped, like the settings panel's
  // key catcher.
  onVisibleChanged: if (visible) Qt.callLater(function() { startMenu.forceActiveFocus() })

  Flickable {
    id: scroller
    x: startMenu.contentLeftInset
    y: startMenu.contentTopInset
    width: startMenu.innerWidth
    height: startMenu.height - startMenu.contentTopInset - startMenu.contentBottomInset
    contentWidth: width
    contentHeight: appsGrid.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height

    WheelHandler {
      target: scroller
      onWheel: function(event) {
        if (event.angleDelta.y === 0) return
        var step = Style.space(48)
        var dy = event.angleDelta.y > 0 ? -step : step
        scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, scroller.contentY + dy))
      }
    }

    Grid {
      id: appsGrid
      width: scroller.width
      columns: startMenu.columns
      spacing: Style.space(2)

      Repeater {
        model: startMenu.apps
        delegate: Item {
          id: appRow
          required property var modelData
          width: startMenu.rowWidth
          height: startMenu.rowHeight

          Rectangle {
            anchors.fill: parent
            anchors.margins: Style.space(1)
            radius: Style.cornerRadius > 0 ? Style.space(5) : 0
            color: rowArea.containsMouse ? Util.alpha(startMenu.ink, 0.10) : "transparent"
          }

          Image {
            id: appIcon
            x: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            height: width
            sourceSize: Qt.size(Math.round(width * (startMenu.root ? startMenu.root.outputScale : 1)),
                                Math.round(height * (startMenu.root ? startMenu.root.outputScale : 1)))
            source: DockModel.resolveAppIcon(startMenu.root ? startMenu.root.appLibrary : null,
                                             startMenu.root ? startMenu.root.appRows : [], appRow.modelData.id)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }

          Text {
            anchors.left: appIcon.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: String(appRow.modelData.name || appRow.modelData.id)
            textFormat: Text.PlainText
            color: startMenu.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: startMenu.activate(appRow.modelData)
          }
        }
      }
    }
  }
}
