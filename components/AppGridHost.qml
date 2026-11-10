import QtQuick
import Quickshell
import Quickshell.Io
import "../DockModel.js" as DockModel
import "../DockGridDrop.js" as DockGridDrop

// The apps button's launcher: the Omarchy menu, on Omarchy 4.5+ the app grid
// of Omarchy's own dock ("appsButtonAction": "grid"), or the dock's own
// anchored Start panel over the button ("start", the Windows taskbar's). The grid and its
// app library are Omarchy's files, loaded on the first open rather than
// copied, so they keep Omarchy's look, search and menus. They ask the dock
// for six functions (gridDock below); an app dragged out of the grid lands
// in the pinned run of the dock under the pointer. One host for all docks,
// as the grid opens on the focused monitor.
Item {
  id: gridHost

  property string omarchyPath: ""
  // Returns the docks, the focused monitor's first (DockHost.orderedDocks).
  property var docks: null
  // Set from omadock.json (or a shipped preset's setup) by DockConfigLogic:
  // "menu" | "grid" | "start".
  property string mode: "menu"

  property bool available: false
  // A load that failed (Omarchy changed the files) falls back to the menu.
  property bool failed: false
  property bool wanted: false
  property bool pendingOpen: false
  // The monitor an app from the grid is dragged over a dock on, "" for none.
  property string dragScreen: ""

  readonly property string gridPath: gridHost.omarchyPath + "/shell/plugins/dock/AppGrid.qml"
  readonly property string libraryPath: gridHost.omarchyPath + "/shell/services/AppLibrary.qml"

  function openLauncher() {
    // The anchored Start panel is the dock's own window, so it needs no
    // Omarchy files; the button's second press closes it again.
    if (gridHost.mode === "start") {
      var d = gridHost.dockList()[0]
      if (d && d.appsMenuHost) { d.appsMenuHost.toggle(); return }
    }
    if (gridHost.mode !== "grid") {
      Quickshell.execDetached(["omarchy-menu", "toggle", "root"])
    } else {
      gridHost.openGrid()
    }
  }

  // The native Apps shortcut opens the grid independently of the dock
  // button's menu/start preference. Older Omarchy keeps the menu fallback.
  function openGrid() {
    if (!gridHost.available || gridHost.failed) {
      Quickshell.execDetached(["omarchy-menu", "toggle", "root"])
    } else if (gridLoader.item) {
      gridLoader.item.toggle()
    } else {
      gridHost.pendingOpen = true
      gridHost.wanted = true
    }
  }

  function loadFailed(what) {
    console.warn("[omadock] Omarchy's app grid did not load (" + what + "); the apps button opens the menu")
    gridHost.failed = true
    if (gridHost.pendingOpen) Quickshell.execDetached(["omarchy-menu", "toggle", "root"])
    gridHost.pendingOpen = false
  }

  function dockList() {
    return gridHost.docks ? gridHost.docks() : []
  }

  function dockOn(screen) {
    var name = screen ? String(screen.name || "") : ""
    var list = gridHost.dockList()
    for (var i = 0; i < list.length; i++)
      if (list[i].dockScreen && String(list[i].dockScreen.name || "") === name) return list[i]
    return null
  }

  // The pinned-run insert index for a grid point (screen-local, logical)
  // over dock d: -1 for an empty run, null when the point is above the
  // dock's layer.
  function rowIndexAt(d, x, y) {
    var win = d.dockWindowRef
    var card = d.dockCardComp
    if (!win || !card || !d.dockScreen) return null
    var wy = y - (d.dockScreen.height - win.height)
    if (wy < 0) return null
    return card.rowInsertIndex(card.row.mapFromItem(d.contentItemRef, x, wy).x)
  }

  function isOver(d) {
    return gridHost.dragScreen !== "" && !!d.dockScreen && String(d.dockScreen.name || "") === gridHost.dragScreen
  }

  function moveDrag(screen, x, y) {
    var target = gridHost.dockOn(screen)
    var idx = target ? gridHost.rowIndexAt(target, x, y) : null
    gridHost.dragScreen = idx !== null ? String(screen.name || "") : ""
    var list = gridHost.dockList()
    for (var i = 0; i < list.length; i++) {
      list[i].dropRowIndex = (list[i] === target && idx !== null) ? idx : -1
      list[i].syncVisibility()
    }
  }

  function endDrag() {
    gridHost.dragScreen = ""
    var list = gridHost.dockList()
    for (var i = 0; i < list.length; i++) {
      list[i].dropRowIndex = -1
      list[i].syncVisibility()
    }
  }

  // Pins the app where its gap stood, or moves it there when it is pinned
  // already (DockGridDrop.js).
  function dropDrag(screen, x, y, key) {
    var d = gridHost.dockOn(screen)
    var idx = d ? gridHost.rowIndexAt(d, x, y) : null
    gridHost.endDrag()
    var id = DockModel.stripDesktop(key)
    if (!d || idx === null || !id) return
    var pinned = DockModel.isPinned(d.pinnedIds, id)
    // togglePin refuses an app that is not installed, and says so.
    if (!pinned && !d.resolveDesktopEntry(id)) { d.togglePin(id); return }
    var landing = DockGridDrop.gridDrop(d.pinnedRow, id, pinned, idx, DockModel.stripDesktop)
    if (landing.pin) d.togglePin(id)
    else if (landing.row) d.applyPinnedRow(landing.row)
  }

  // What Omarchy's AppGrid calls on its dock.
  QtObject {
    id: gridDock

    function launchEntry(entry) {
      var d = gridHost.dockList()[0]
      if (d && entry) d.launchApp(DockModel.stripDesktop(entry.id), null)
    }
    function isPinned(key) {
      var d = gridHost.dockList()[0]
      return !!d && DockModel.isPinned(d.pinnedIds, key)
    }
    function setPinned(key, pinned) {
      var d = gridHost.dockList()[0]
      if (d && DockModel.isPinned(d.pinnedIds, key) !== pinned) d.togglePin(key)
    }
    function moveExternalDrag(screen, x, y) { gridHost.moveDrag(screen, x, y) }
    function dropExternalDrag(screen, x, y, key) { gridHost.dropDrag(screen, x, y, key) }
    function endExternalDrag() { gridHost.endDrag() }
  }

  // Both files ship with Omarchy 4.5; before it the choice is not offered.
  // Started a turn later: the command binds to omarchyPath and may not have
  // caught up with it yet.
  function checkFiles() {
    if (gridHost.omarchyPath !== "") Qt.callLater(function() { checkProc.running = true })
  }
  onOmarchyPathChanged: gridHost.checkFiles()
  Component.onCompleted: gridHost.checkFiles()
  Process {
    id: checkProc
    command: ["sh", "-c", '[ -f "$1" ] && [ -f "$2" ]', "omadock-grid-check", gridHost.gridPath, gridHost.libraryPath]
    onExited: (exitCode) => { gridHost.available = exitCode === 0 }
  }

  Loader {
    id: libraryLoader
    active: gridHost.wanted
    source: active ? "file://" + gridHost.libraryPath : ""
    onStatusChanged: if (status === Loader.Error) gridHost.loadFailed("AppLibrary.qml")
  }

  Loader {
    id: gridLoader
    active: gridHost.wanted && libraryLoader.status === Loader.Ready
    source: active ? "file://" + gridHost.gridPath : ""
    onStatusChanged: if (status === Loader.Error) gridHost.loadFailed("AppGrid.qml")
    onLoaded: {
      item.appLibrary = libraryLoader.item
      item.dock = gridDock
      if (gridHost.pendingOpen) item.open()
      gridHost.pendingOpen = false
    }
  }
}
