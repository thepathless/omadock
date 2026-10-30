import QtQuick 6.11
import Quickshell
import qs.Commons
import qs.Ui
import "../DockIcons.js" as DockIcons
import "../DockLabels.js" as DockLabels
import "../DockModel.js" as DockModel
import "strings"

// The items the dock's fit moved out of the row (DockFit.js, DockFitHost),
// in dock order, as an opened group shows its apps: icon, name, window
// marks. A click acts as on the dock, a right click opens the item's own
// menu over its cell. No drag: the order is the dock's.
BorderSurface {
  id: pop
  property var rootRef: null
  readonly property var root: rootRef
  readonly property var motion: pop.root ? pop.root.motion : null
  property var hostRef: null
  property var popupWindow: null

  // { id, kind, title, icon, data } per hidden item.
  readonly property var cells: {
    var out = []
    var dock = pop.root
    if (!dock || !pop.hostRef) return out
    var card = dock.dockCardComp
    var right = card ? card.rightRowRef : null
    var ids = pop.hostRef.hiddenItems
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      var sep = id.indexOf(":")
      var kind = sep < 0 ? id : id.slice(0, sep)
      var key = sep < 0 ? "" : id.slice(sep + 1)
      if (kind === "pin") {
        var p = dock.pinnedRowByKey[key]
        if (!p) continue
        if (p.group) out.push({ id: id, kind: "group", title: p.group.name || Tr.t("groups.defaultName", "Group"), icon: pop.folderIcon(p.group.icon || "folder"), data: p.group })
        else if (p.entry) out.push({ id: id, kind: "app", title: dock.labelName(p.entry.appId, p.entry.name), icon: pop.appIcon(p.entry), data: p.entry })
      } else if (kind === "run") {
        var r = dock.runningByKey[key]
        if (r) out.push({ id: id, kind: "app", title: dock.labelName(r.appId, r.name), icon: pop.appIcon(r), data: r })
      } else if (kind === "tile") {
        var t = card ? card.tileByKey[key] : null
        var wins = t ? (t.windows ? t.windows : [t.win]) : []
        if (wins.length > 0 && wins[0]) out.push({ id: id, kind: "tile", title: wins[0].title || wins[0].appId || Tr.t("common.window", "Window"), icon: pop.appIcon(pop.root.entryForId(wins[0].appId || "") || { appId: wins[0].appId || "" }), data: { wins: wins, appId: wins[0].appId || "" } })
      } else if (kind === "folder") {
        var f = right ? right.folderByKey[key] : null
        if (f) out.push({ id: id, kind: "folder", title: f.name || DockLabels.folderBaseName(f.path || ""),
          icon: f.command ? pop.folderIcon(f.icon || "application-x-executable") : pop.folderIcon(DockIcons.folderIconFor(f.path, f.icon || "")), data: f })
      } else if (kind === "drive") {
        var d = right ? right.driveByKey[key] : null
        if (d) out.push({ id: id, kind: "drive", title: d.name || Tr.t("common.usbDrive", "USB Drive"), icon: pop.folderIcon(d.icon || "drive-removable-media"), data: d })
      } else if (kind === "button") {
        out.push({ id: id, kind: "omarchy", title: "Omarchy", icon: Quickshell.iconPath("view-app-grid", true), data: null })
      }
    }
    return out
  }

  // The icon the dock draws for this entry (DockItem: entry.icon), else the
  // app library's.
  function appIcon(entry) {
    if (entry && entry.icon) return entry.icon
    var appId = entry ? entry.appId : ""
    if (pop.root && pop.root.appLibrary) {
      var s = DockModel.resolveAppIcon(pop.root.appLibrary, pop.root.appRows, appId)
      if (s) return s
    }
    return Quickshell.iconPath("application-x-executable", true)
  }
  function folderIcon(name) {
    var dock = pop.root
    return dock ? DockIcons.resolveThemedFolderIcon(name, dock.iconThemeRef.iconTheme, dock.folderColor, dock.appLibrary) : ""
  }

  // Everything a call needs is read before it runs: opening another popup
  // or a menu closes this one, which destroys the cell that asked.
  function activate(cell, item) {
    var dock = pop.root
    var at = pop.popupWindow.toDockWindow(item, item.width / 2, 0)
    if (cell.kind === "app") dock.activate(cell.data.appId)
    else if (cell.kind === "group") dock.openAppGroup(cell.data, at.x, 0)
    else if (cell.kind === "folder") {
      if (cell.data.command) Quickshell.execDetached(["sh", "-c", cell.data.command])
      else dock.openFolderStack(cell.data.path, cell.title, at.x)
    }
    else if (cell.kind === "drive") dock.openFolderStack(cell.data.mountpoint, cell.title, at.x)
    else if (cell.kind === "tile") dock.restoreWindowBatch(cell.data.wins)
    else if (cell.kind === "omarchy") {
      if (dock.sharedState) dock.sharedState.appGrid.openLauncher()
      else Quickshell.execDetached(["omarchy-menu", "toggle", "root"])
    }
  }
  function menu(cell, item) {
    var dock = pop.root
    var at = pop.popupWindow.toDockWindow(item, item.width / 2, 0)
    if (cell.kind === "app") dock.openContext(cell.data.appId, at.x, at.y)
    else if (cell.kind === "group") dock.openAppGroupContext(cell.data, at.x, at.y)
    else if (cell.kind === "folder") dock.openFolderContext(cell.data.path || "", cell.title, at.x, at.y, cell.data.command || "")
    else if (cell.kind === "drive") dock.openDriveContext(cell.data.dev || "", cell.data.mountpoint || "", cell.title, cell.data.space || "", at.x, at.y)
    else if (cell.kind === "tile") dock.openTileContext(cell.data.wins, cell.data.appId, at.x)
    else if (cell.kind === "omarchy") dock.openDockSettingsMenu(at.x, at.y)
  }

  z: 100
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
  radius: Style.cornerRadius
  padding: Style.space(6)

  readonly property int cols: Math.min(5, Math.max(2, Math.ceil(Math.sqrt(pop.cells.length))))
  readonly property real cellWidth: Style.space(64)
  readonly property real cellHeight: Style.space(70)
  width: pop.cells.length > 0 ? grid.width + pop.contentLeftInset + pop.contentRightInset + Style.space(12) : 0
  height: pop.cells.length > 0 ? grid.height + pop.contentTopInset + pop.contentBottomInset + Style.space(12) : 0

  Grid {
    id: grid
    columns: pop.cols
    spacing: Style.space(6)
    x: pop.contentLeftInset + Style.space(6)
    y: pop.contentTopInset + Style.space(6)

    Repeater {
      model: pop.cells
      delegate: Item {
        id: cellItem
        required property var modelData
        width: pop.cellWidth
        height: pop.cellHeight
        readonly property var appEntry: (cellItem.modelData.kind === "app" && pop.root) ? pop.root.entryForId(cellItem.modelData.data.appId) : null
        readonly property var wins: cellItem.appEntry ? (cellItem.appEntry.windowList || []) : []

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: cellArea.containsMouse ? Util.alpha(Color.menu.text, 0.08) : "transparent"
          Behavior on color { ColorAnimation { duration: pop.motion ? pop.motion.fast : 0 } }
        }
        Column {
          anchors.centerIn: parent
          spacing: Style.space(4)
          width: parent.width - Style.space(8)
          DockIconArt {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.space(36)
            height: Style.space(36)
            source: cellItem.modelData.icon
            renderSize: Style.space(36)
            iconStyle: pop.root ? pop.root.iconStyle : "original"
            // The popup sits on the menu surface, not the dock card.
            tint: pop.root ? pop.root.tintFor(pop.root.iconTint, Color.menu.text, Color.menu.background) : Color.menu.text
            grid: pop.root ? pop.root.iconGrid : 16
            outputScale: pop.root ? pop.root.outputScale : 1
            contrast: pop.root ? pop.root.iconContrast : 0
            strength: pop.root ? pop.root.iconStrength : 1
            hovered: cellArea.containsMouse
            hoverFx: pop.root ? pop.root.hoverFx : null
          }
          Text {
            width: parent.width
            text: cellItem.modelData.title
            textFormat: Text.PlainText
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Math.max(9, Style.font.caption - 1)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
          }
          // Its windows, as the dock's marks would show them.
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(3)
            visible: cellItem.wins.length > 0
            Repeater {
              model: Math.min(3, cellItem.wins.length)
              delegate: DockIndicator {
                required property int index
                rootRef: pop.root
                anchors.verticalCenter: parent.verticalCenter
                kind: (pop.root && cellItem.wins[index] && cellItem.wins[index].address === pop.root.activeWindowAddress) ? "active" : "window"
              }
            }
          }
        }
        MouseArea {
          id: cellArea
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            if (!pop.root || !pop.popupWindow) return
            var cell = cellItem.modelData
            if (mouse.button === Qt.RightButton) pop.menu(cell, cellItem)
            else pop.activate(cell, cellItem)
          }
        }
      }
    }
  }
}
