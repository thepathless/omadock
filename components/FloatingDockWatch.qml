import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../DockFloating.js" as DockFloating

// Which dock a floating workspace gets (DockFloating.js), on Omarchy 4.5+
// where omarchy.dock exists. With "hide-omadock" each dock reads the layout
// mode of its monitor's workspace from the files the layout commands write
// and yields while it is floating; the primary dock also switches
// omarchy.dock on or off to match the choice, at start and when it changes.
Item {
  id: watch

  property var dockRoot: null
  // Set from omadock.json ("floatingDock") by DockConfigLogic.
  property string choice: "hide-omarchy"

  readonly property bool available: manifestFile.found
  readonly property bool yieldDock: watch.watching && DockFloating.isFloating(watch.workspaceId, watch.workspaceText, watch.defaultText)

  readonly property bool watching: watch.available && watch.choice === "hide-omadock"
  readonly property string modesDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/workspace-layouts"
  // A file watch set up before its directory exists never fires, so the
  // paths wait until mkdir has made sure it does.
  property bool dirReady: false
  property string workspaceText: ""
  property string defaultText: ""

  readonly property int workspaceId: {
    var name = watch.dockRoot && watch.dockRoot.dockScreen ? String(watch.dockRoot.dockScreen.name || "") : ""
    var monitor = Hyprland.monitors.values.find(function(m) { return m && m.name === name })
    return monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
  }

  readonly property var monitor: watch.dockRoot && watch.dockRoot.dockScreen
    ? Hyprland.monitorFor(watch.dockRoot.dockScreen) : null
  property var scratchpadByMonitor: ({})
  readonly property bool scratchpadOpen: {
    if (!watch.monitor) return false
    var name = watch.monitor.name
    if (Object.prototype.hasOwnProperty.call(watch.scratchpadByMonitor, name)) return watch.scratchpadByMonitor[name]
    var ipc = watch.monitor.lastIpcObject
    return !!(ipc && ipc.specialWorkspace && ipc.specialWorkspace.name === "special:scratchpad")
  }
  onScratchpadOpenChanged: if (watch.dockRoot) watch.dockRoot.syncVisibility()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "activespecial" || !watch.monitor) return
      var fields = String(event.data || "").split(",")
      if (fields.length !== 2 || fields[1] !== watch.monitor.name) return
      var next = Object.assign({}, watch.scratchpadByMonitor)
      next[watch.monitor.name] = fields[0] === "special:scratchpad" || fields[0] === "scratchpad"
      watch.scratchpadByMonitor = next
    }
  }

  onYieldDockChanged: if (watch.dockRoot) watch.dockRoot.syncVisibility()
  onWatchingChanged: if (watch.watching && !watch.dirReady) mkdirProc.running = true
  onChoiceChanged: watch.scheduleReconcile()
  onAvailableChanged: watch.scheduleReconcile()

  function scheduleReconcile() {
    if (watch.available && watch.dockRoot && watch.dockRoot.isPrimary) reconcileTimer.restart()
  }

  CappedFileView {
    id: manifestFile
    property bool found: false
    path: watch.dockRoot && watch.dockRoot.omarchyPath ? watch.dockRoot.omarchyPath + "/shell/plugins/dock/manifest.json" : ""
    maxBytes: 65536
    watchChanges: false
    atomicWrites: false
    // Deferred: the read's command binds to path and may not have caught up yet.
    onPathChanged: Qt.callLater(manifestFile.reload)
    onLoaded: found = true
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", "--", watch.modesDir]
    onExited: watch.dirReady = true
  }

  // Kept while the next workspace's file is read: clearing on a switch
  // would show the dock for a moment between two floating workspaces.
  CappedFileView {
    id: workspaceFile
    path: watch.watching && watch.dirReady && watch.workspaceId >= 1 ? watch.modesDir + "/" + watch.workspaceId + ".lua" : ""
    maxBytes: 4096
    atomicWrites: false
    onPathChanged: Qt.callLater(workspaceFile.reload)
    onFileChanged: reload()
    onLoaded: watch.workspaceText = text
    // The toggle removes the file when it cycles onto the default mode.
    onMissing: watch.workspaceText = ""
  }

  CappedFileView {
    id: defaultFile
    path: watch.watching && watch.dirReady ? watch.modesDir + "/default.lua" : ""
    maxBytes: 4096
    atomicWrites: false
    onPathChanged: Qt.callLater(defaultFile.reload)
    onFileChanged: reload()
    onLoaded: watch.defaultText = text
    onMissing: watch.defaultText = ""
  }

  // Waits for omadock.json to land, so a start does not switch omarchy.dock
  // to the default choice and back to the saved one a moment later.
  Timer {
    id: reconcileTimer
    interval: 1500
    onTriggered: {
      shellFile.path = Quickshell.env("HOME") + "/.config/omarchy/shell.json"
      Qt.callLater(shellFile.reload)
    }
  }

  CappedFileView {
    id: shellFile
    maxBytes: 262144
    watchChanges: false
    atomicWrites: false
    onLoaded: {
      var action = DockFloating.omarchyDockAction(watch.choice, text)
      if (action === "" || pluginProc.running) return
      pluginProc.command = ["omarchy", "plugin", action, "omarchy.dock"]
      pluginProc.running = true
    }
  }

  Process {
    id: pluginProc
    onExited: (exitCode) => {
      if (exitCode !== 0) console.warn("[omadock] omarchy plugin", pluginProc.command[2], "omarchy.dock failed:", exitCode)
    }
  }
}
