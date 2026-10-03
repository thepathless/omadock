import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

// The open folder stack: a fixed header (Back, folder name, entry count), a
// scrolling body and a fixed footer. The body is a list ("stack" view) or a
// grid of larger icons and previews ("grid" view), chosen per pinned folder.
// Clicking a folder steps into it; Back returns the way it came.
BorderSurface {
  id: folderStackPopover

  property var rootRef: null
  readonly property var root: rootRef

  readonly property bool isOpen: root ? (root.activeStackFolder !== "" && root.dockVisible) : false
  readonly property bool gridView: root ? root.activeStackView === "grid" : false
  readonly property var entries: root ? root.activeStackEntries : []
  readonly property bool canGoBack: root ? root.activeStackTrail.length > 0 : false

  visible: isOpen
  opacity: isOpen ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 120 } }

  z: 100
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
  radius: Style.cornerRadius
  padding: Style.space(4)

  readonly property real maxAllowedHeight: root ? root.popupMaxHeight : 500

  // Grid geometry: up to five columns, never wider than the entries need.
  readonly property real tileWidth: Style.space(92)
  readonly property int gridColumns: Math.max(3, Math.min(5, entries.length))
  readonly property real gridWidth: gridColumns * (tileWidth + Style.space(4))

  // List rows size to their widest content; FileStackRow and ContextRow pick
  // this up through their parent chain.
  readonly property real rowWidth: !isOpen ? 0
    : gridView ? gridWidth
    : Math.max(root.menuContentWidth(list.contentItem), root.menuContentWidth(headerColumn))

  width: isOpen ? rowWidth + contentLeftInset + contentRightInset : 0
  height: isOpen
    ? Math.min(maxAllowedHeight, headerColumn.implicitHeight + bodyContentHeight + footerColumn.implicitHeight + contentTopInset + contentBottomInset + Style.space(4))
    : 0


  function homePath(p) {
    return String(p || "").replace(/^~/, Quickshell.env("HOME"))
  }

  function activate(entry) {
    if (!root || !entry) return
    if (entry.isDir) {
      root.enterStackDir(entry.path, entry.name)
      return
    }
    // xdg-open hands the file to its default application. argv form: names
    // are never re-parsed by a shell.
    Util.execArgv(["uwsm-app", "--", "xdg-open", entry.path])
    root.closeFolderStack()
  }

  function dragStart() {
    if (root) root.fileDragOut = true
  }

  function dragDone(action) {
    if (!root) return
    root.fileDragOut = false
    if (action !== Qt.IgnoreAction) root.closeFolderStack()
  }

  // A new directory starts at the top.
  Connections {
    target: root
    function onActiveStackPathChanged() {
      list.contentY = 0
      grid.contentY = 0
    }
  }

  // ---------------------------------------------------------------- header
  Column {
    id: headerColumn
    x: folderStackPopover.contentLeftInset
    y: folderStackPopover.contentTopInset
    width: folderStackPopover.rowWidth

    Item {
      readonly property bool isMenuContent: true
      implicitWidth: backButton.width + Style.space(8) + titleText.implicitWidth + Style.space(16)
      width: parent.width
      height: Math.max(Style.space(28), 28)

      Rectangle {
        id: backButton
        visible: folderStackPopover.canGoBack
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? height : 0
        height: parent.height - Style.space(4)
        radius: Style.cornerRadius
        color: backArea.containsMouse ? Color.menu.selectedBackground : "transparent"

        Text {
          anchors.centerIn: parent
          text: "‹"
          textFormat: Text.PlainText
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
        }

        MouseArea {
          id: backArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root) root.stackBack()
        }
      }

      Text {
        id: titleText
        anchors.left: backButton.right
        anchors.leftMargin: folderStackPopover.canGoBack ? Style.space(4) : Style.space(8)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: ((root ? root.activeStackName : "") || "Folder")
          + ((root && root.activeStackTotalCount > 0) ? "  (" + DockModel.stackCountLabel(root.activeStackTotalCount, root.activeStackTruncated) + ")" : "")
        textFormat: Text.PlainText
        color: Util.alpha(Color.menu.text, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideMiddle
      }
    }
  }

  // ------------------------------------------------------------------ body
  // ListView / GridView create delegates only for what is on screen (plus a
  // small cache), so a folder of hundreds of photos decodes a screenful of
  // previews instead of all of them up front.
  readonly property real listRowHeight: Math.max(28, Style.space(28)) + Style.space(2)
  readonly property real tileHeight: Style.space(100) + Style.space(4)
  readonly property var activeView: gridView ? grid : list
  readonly property real bodyContentHeight: entries.length === 0
    ? emptyText.implicitHeight
    : (gridView ? Math.ceil(entries.length / gridColumns) * tileHeight : entries.length * listRowHeight)

  Item {
    id: body
    anchors.left: parent.left
    anchors.leftMargin: folderStackPopover.contentLeftInset
    anchors.right: parent.right
    anchors.rightMargin: folderStackPopover.contentRightInset
    anchors.top: headerColumn.bottom
    anchors.topMargin: Style.space(2)
    anchors.bottom: footerColumn.top
    anchors.bottomMargin: Style.space(2)
    clip: true

    // Wheel only: the views do not flick, so pressing an entry can start a
    // drag out instead of scrolling. Handled here, outside the views, since a
    // non-interactive Flickable ignores wheel events.
    WheelHandler {
      target: null
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) {
        var view = folderStackPopover.activeView
        var dy = event.pixelDelta.y !== 0
          ? -event.pixelDelta.y
          : -event.angleDelta.y / 120 * Style.space(40)
        if (dy === 0 || !view) return
        var maxY = Math.max(0, view.contentHeight - view.height)
        view.contentY = Math.max(0, Math.min(maxY, view.contentY + dy))
      }
    }

    Text {
      id: emptyText
      visible: folderStackPopover.entries.length === 0 && !(root && root.activeStackLoading)
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: (root && root.activeStackFailed) ? "Folder could not be read" : "Folder is empty"
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      padding: Style.space(8)
    }

    ListView {
      id: list
      anchors.fill: parent
      visible: !folderStackPopover.gridView
      interactive: false
      boundsBehavior: Flickable.StopAtBounds
      spacing: Style.space(2)
      cacheBuffer: Math.max(0, Math.round(height))
      model: folderStackPopover.gridView ? [] : folderStackPopover.entries
      delegate: FileStackRow {
        name: modelData.name
        path: modelData.path
        icon: modelData.icon
        subtext: modelData.isDir ? "›" : modelData.size
        themeVersion: root ? root.themeVersion : 0
        currentIconThemeName: root ? root.currentIconThemeName : "Yaru"
        folderColor: root ? root.folderColor : "theme"
        symbolicColor: root ? root.symbolicColorOn(Color.menu.background) : "#ffffff"
        appLibrary: root ? root.appLibrary : null
        onTriggered: folderStackPopover.activate(modelData)
        onDragStarted: folderStackPopover.dragStart()
        onDragFinished: function(action) { folderStackPopover.dragDone(action) }
      }
    }

    GridView {
      id: grid
      anchors.fill: parent
      visible: folderStackPopover.gridView
      interactive: false
      boundsBehavior: Flickable.StopAtBounds
      cellWidth: folderStackPopover.tileWidth + Style.space(4)
      cellHeight: folderStackPopover.tileHeight
      cacheBuffer: Math.max(0, Math.round(height))
      model: folderStackPopover.gridView ? folderStackPopover.entries : []
      delegate: FileTile {
        width: folderStackPopover.tileWidth
        name: modelData.name
        path: modelData.path
        icon: modelData.icon
        thumb: modelData.thumb || ""
        isDir: modelData.isDir
        themeVersion: root ? root.themeVersion : 0
        currentIconThemeName: root ? root.currentIconThemeName : "Yaru"
        folderColor: root ? root.folderColor : "theme"
        symbolicColor: root ? root.symbolicColorOn(Color.menu.background) : "#ffffff"
        appLibrary: root ? root.appLibrary : null
        onTriggered: folderStackPopover.activate(modelData)
        onDragStarted: folderStackPopover.dragStart()
        onDragFinished: function(action) { folderStackPopover.dragDone(action) }
      }
    }
  }

  // ---------------------------------------------------------------- footer
  Column {
    id: footerColumn
    x: folderStackPopover.contentLeftInset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: folderStackPopover.contentBottomInset
    width: folderStackPopover.rowWidth
    spacing: Style.space(2)

    MenuDivider {}

    // The listing is capped (scripts/list-folder.py); say so instead of
    // silently truncating.
    ContextRow {
      readonly property string moreLabel: root ? DockModel.stackMoreLabel(root.activeStackTotalCount, root.activeStackEntries.length, root.activeStackTruncated) : ""
      visible: moreLabel !== ""
      text: moreLabel + " — open in File Manager"
      onTriggered: {
        if (!root) return
        Util.execArgv(["uwsm-app", "--", "xdg-open", root.activeStackPath])
        root.closeFolderStack()
      }
    }

    ContextRow {
      text: "Open in File Manager"
      onTriggered: {
        if (!root) return
        Util.execArgv(["uwsm-app", "--", "xdg-open", root.activeStackPath])
        root.closeFolderStack()
      }
    }
  }
}
