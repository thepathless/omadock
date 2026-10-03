import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "DockModel.js" as DockModel
import "components"

// Entry point. Runs one Dock per monitor when "multiMonitor" is on, else a
// single Dock on the configured "screen" exactly as before. Each per-monitor
// dock lists only the windows on its own monitor ("perMonitorApps"), the way
// a taskbar does on every display in Windows.
Item {
  id: host

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/omadock.json"

  property bool multiMonitor: false
  property string screenName: ""

  // The dock on the configured screen (else the first one) plays alert sounds.
  readonly property string primaryScreenName: {
    var list = host.realScreens
    for (var i = 0; i < list.length; i++)
      if (list[i].name === host.screenName) return host.screenName
    return list.length > 0 ? String(list[0].name) : ""
  }

  // Connected outputs only, as in Dock.pickScreen(): placeholder screens
  // (empty name) and dangling "{ NULL SCREEN }" entries linger around
  // suspend/resume and must not get a dock of their own.
  readonly property var realScreens: {
    var out = []
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) {
      var s = list[i]
      if (s && s.name && s.name !== "{ NULL SCREEN }") out.push(s)
    }
    return out
  }

  function loadConfig() {
    var raw = DockModel.readCapped(configFile.text, DockModel.MAX_CONFIG_BYTES).trim()
    var parsed = {}
    if (raw) {
      try { parsed = JSON.parse(raw) || {} } catch (e) { console.warn("[omadock] Failed parsing omadock.json in host:", e); parsed = {} }
    }
    host.multiMonitor = parsed.multiMonitor === true
    host.screenName = typeof parsed.screen === "string" ? parsed.screen : ""
  }

  // CappedFileView gates the read (regular file + byte ceiling) before any
  // content enters QML — the host shares the mutable config with the dock, so
  // the same pre-load cap applies here.
  CappedFileView {
    id: configFile
    path: host.configPath
    maxBytes: DockModel.MAX_CONFIG_BYTES
    watchChanges: true
    atomicWrites: false
    onLoaded: host.loadConfig()
    onFileChanged: configReloadDebounce.restart()
  }

  Timer {
    id: configReloadDebounce
    interval: 120
    // The read is asynchronous; onLoaded applies it once it lands.
    onTriggered: configFile.reload()
  }

  // Parked-window bookkeeping, shared so any dock can restore a window that
  // another dock minimized, and tiles follow the window's origin monitor.
  QtObject {
    id: sharedStore
    property var minimizedOrigins: ({})
    property var parkedAt: ({})
  }

  Variants {
    id: docks
    model: host.multiMonitor ? host.realScreens : ["single"]

    delegate: Dock {
      required property var modelData
      readonly property bool perScreen: typeof modelData !== "string"

      shell: host.shell
      omarchyPath: host.omarchyPath
      manifest: host.manifest
      forcedScreenName: perScreen && modelData ? String(modelData.name) : ""
      isPrimary: !perScreen || forcedScreenName === host.primaryScreenName
      ipcEnabled: false
      sharedState: sharedStore
    }
  }

  // Focused monitor's dock first, so keybinds act where the user is looking.
  function orderedDocks() {
    var list = docks.instances || []
    var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    var first = []
    var rest = []
    for (var i = 0; i < list.length; i++) {
      if (!list[i]) continue
      if (list[i].forcedScreenName !== "" && list[i].forcedScreenName === focused) first.push(list[i])
      else rest.push(list[i])
    }
    return first.concat(rest)
  }

  IpcHandler {
    target: "omadock"

    // Read-only diagnostics for bug reports and live verification.
    function status(): string {
      return JSON.stringify({
        version: host.manifest ? host.manifest.version : "unknown",
        docks: host.orderedDocks().map(function(d) {
          return {
            screen: d.dockScreen ? d.dockScreen.name : "",
            visible: d.dockVisible,
            dividerGeometry: d.dividerGeometry,
            dividerStyle: d.dividerStyle,
            hoverEffect: d.hoverEffect,
            activePresetId: d.activePresetId,
            terminalHosts: d.terminalHosts,
            terminalApps: d.terminalApps,
            notificationBadges: d.notificationBadges,
            model: d.dockModel
          }
        })
      })
    }

    function minimizeActive(): void {
      var d = host.orderedDocks()
      if (d.length > 0) d[0].minimizeActive()
    }

    function restoreLast(): void {
      var d = host.orderedDocks()
      for (var i = 0; i < d.length; i++)
        if (d[i].restoreLast()) return
    }

    function toggleVisibility(): void {
      var d = host.orderedDocks()
      if (d.length === 0) return
      var next = !d[0].dockVisible
      for (var i = 0; i < d.length; i++) d[i].dockVisible = next
    }

    function reveal(): void {
      var d = host.orderedDocks()
      for (var i = 0; i < d.length; i++) d[i].dockVisible = true
    }

    function hide(): void {
      var d = host.orderedDocks()
      for (var i = 0; i < d.length; i++) d[i].dockVisible = false
    }

    // The settings panel opens on the focused monitor's dock.
    function openSettings(): void {
      var d = host.orderedDocks()
      if (d.length > 0) d[0].openSettingsPanel()
    }

    function openSettingsPage(page: string): void {
      var d = host.orderedDocks()
      if (d.length === 0) return
      d[0].settingsPanelPage = page
      d[0].openSettingsPanel()
    }

    function closeSettings(): void {
      var d = host.orderedDocks()
      for (var i = 0; i < d.length; i++) d[i].closeSettingsPanel()
    }

    // Alignment is a config key; the other docks pick it up from the file.
    function setAlignment(align: string): void {
      var d = host.orderedDocks()
      if (d.length > 0) d[0].setDockAlignment(align)
    }

    function setPosition(pos: string): void {
      var d = host.orderedDocks()
      if (d.length > 0) d[0].setDockPosition(pos)
    }

    // Applies a saved appearance preset by name, ignoring case.
    function applyPreset(name: string): string {
      var d = host.orderedDocks()
      if (d.length === 0) return "not found"
      var id = d[0].presetIdByName(String(name))
      return (id !== "" && d[0].applyPreset(id)) ? "ok" : "not found"
    }

    // Read-only: item rectangles of the focused monitor's dock (window
    // coordinates), used by tests/bench/bench.py and the live tests.
    function itemGeometry(): string {
      var d = host.orderedDocks()
      return d.length > 0 ? d[0].itemGeometry() : "[]"
    }

    // Read-only summary for the live tests.
    function state(): string {
      var d = host.orderedDocks()
      if (d.length === 0) return "{}"
      return JSON.stringify({
        visible: d[0].dockVisible,
        settingsOpen: d[0].settingsPanelOpen,
        settingsPage: d[0].settingsPanelPage,
        activePreset: d[0].activePresetId || "",
        items: JSON.parse(d[0].itemGeometry()).length,
        docks: d.length
      })
    }
  }
}
