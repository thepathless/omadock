import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../../DockModel.js" as DockModel
import "../../DockLayout.js" as DockLayout

// Logic extracted from Dock.qml: stateless functions, the dock root
// is passed in and owns all state. Bodies are verbatim.

QtObject {
  function refreshDock(root) {
    var tops = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    if (root.filterByMonitor) tops = tops.filter(root.isToplevelOnThisMonitor)
    var next = root.appLibrary
      ? DockModel.buildEntries(root.pinnedIds, tops, root.appRows,
                               root.appLibrary, root.hyprToplevelFor, root.minimizedWorkspace, root.minimizedOrigins, root.appGroups, root.terminalHosts, root.terminalApps)
      : { pinned: [], running: [] }
    // An equal model would only re-run every delegate's bindings.
    if (!DockModel.sameModel(next, root.dockModel)) root.dockModel = next
    root.rescanMinimizedWindows()
    root.pruneLaunching()
    root.pruneWindowState()
    root.notificationBadgeTimerRef.restart()
  }

  // terminal-hosts.py reruns on every window title change, and an animated
  // title changes about once a second. Only a different answer is applied, so
  // only a different answer costs the caller a dock rebuild.
  function applyTerminalIdentities(root, text) {
    var identities = JSON.parse(text) || ({})
    var hosts = identities.terminals || ({}), apps = identities.apps || ({})
    if (JSON.stringify(hosts) === JSON.stringify(root.terminalHosts)
        && JSON.stringify(apps) === JSON.stringify(root.terminalApps)) return false
    root.terminalHosts = hosts
    root.terminalApps = apps
    return true
  }

  function rescanMinimizedWindows(root) {
    var mins = []
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < tops.length; i++) {
      var h = tops[i]
      if (!h) continue
      var addr = root.windowAddress(h)
      if (!addr) continue
      var isParked = (h.workspace && String(h.workspace.name || "") === root.minimizedWorkspace)
                  || (root.minimizedOrigins && root.minimizedOrigins[addr] !== undefined)
      if (!isParked) continue
      if (!root.isHyprOnThisMonitor(h)) continue
      var top = root.liveToplevelForAddress(addr)
      var title = String((top && top.title) || h.title || "Window")
      var appId = ""
      var hClass = (h && h.lastIpcObject) ? (h.lastIpcObject["class"] || h.lastIpcObject["initialClass"] || "") : ""
      appId = (top && top.appId) ? DockModel.normalizeId(top.appId)
        : (hClass ? DockModel.normalizeId(hClass) : "")
      mins.push({ address: addr, title: title, appId: appId, waylandToplevel: top })
    }
    // Oldest parked first, so the tiles read chronologically left to right.
    mins.sort(function (a, b) {
      var ta = root.parkedAt[a.address] !== undefined ? root.parkedAt[a.address] : 0
      var tb = root.parkedAt[b.address] !== undefined ? root.parkedAt[b.address] : 0
      return ta - tb
    })
    // Assign only on real change: a fresh array per rebuild would recreate
    // every tile delegate on unrelated events, eating clicks and forcing
    // pointless capture re-negotiations.
    var sig = ""
    for (var s = 0; s < mins.length; s++) sig += JSON.stringify([mins[s].address, mins[s].title, mins[s].appId]) + ","
    if (sig !== root._minimizedSig) {
      root._minimizedSig = sig
      root.minimizedWindows = mins
    }
  }

  function rememberFocus(root, addr) {
    if (!addr) return
    var out = [addr]
    for (var i = 0; i < root.focusOrder.length && out.length < 12; i++) {
      if (root.focusOrder[i] !== addr) out.push(root.focusOrder[i])
    }
    root.focusOrder = out
  }

  function setDockAlignment(root, align) {
    root.alignment = DockLayout.normalizeAlignment(align)
    root.saveConfig()
    if (root.intelligentAutohide) root.debounceOverlapTimerRef.restart()
    root.syncVisibility()
  }

  function setDockLayout(root, layout) {
    root.layout = DockLayout.normalizeLayout(layout)
    root.saveConfig()
    if (root.intelligentAutohide) root.debounceOverlapTimerRef.restart()
    root.syncVisibility()
  }

  function setDockPosition(root, pos) {
    root.setDockAlignment(pos)
  }

  function syncVisibility(root) {
    // Omarchy's own dock has this floating workspace (FloatingDockWatch).
    if (root.floatingWatch && root.floatingWatch.yieldDock) {
      root.hideTimerRef.stop()
      root.revealTimerRef.stop()
      root.dockVisible = false
      return
    }

    // Mode 1: Always Show
    if (!root.autohide) {
      root.hideTimerRef.stop()
      root.revealTimerRef.stop()
      root.dockVisible = true
      return
    }

    var isHovered = (root.cardHover && root.cardHover.hovered) || (root.hitboxHover && root.hitboxHover.hovered) || (root.revealHoverRef && root.revealHoverRef.hovered) || root.contextAppId !== "" || root.dockDragActive || root.activeStackFolder !== "" || root.activeAppGroupId !== "" || root.settingsPanelOpen || root.externalDragOver || root.appDropTargetId !== "" || (root.sharedState && root.sharedState.appGrid.isOver(root))

    // Hovered, Context Menu Open, or Dragging: keep visible
    if (isHovered) {
      root.hideTimerRef.stop()
      if (root.dockVisible) root.revealTimerRef.stop()
      else if (!root.revealTimerRef.running) root.revealTimerRef.restart()
      return
    }

    root.revealTimerRef.stop()

    // Mode 3: Intelligent Autohide without window overlap -> stay visible on empty desktop
    if (root.intelligentAutohide && !root.windowsOverlapDock) {
      root.hideTimerRef.stop()
      root.dockVisible = true
      return
    }

    // Standard Autohide OR Intelligent Autohide with overlapping window -> hide after delay
    if (root.dockVisible) {
      root.hideTimerRef.restart()
    }
  }

  // A theme switch replaces the whole current/theme directory, so the file
  // watches on colors.toml and icons.theme fire once and then follow the
  // deleted files: from the second switch on the dock kept the first
  // theme's palette and icon theme. The shell's own colour signals still
  // arrive on every switch, so they re-read both files (coalesced; their
  // onLoaded runs handleThemeChanged with the new text).
  function handleShellThemeChanged(root) {
    root.themeFileReloadRef.restart()
    root.handleThemeChanged()
  }

  function openSettingsPanel(root) {
    root.closeContext()
    root.closeFolderStack()
    root.closeAppGroup()
    root.settingsPanelOpen = true
  }

  function closeSettingsPanel(root) {
    root.settingsPanelOpen = false
    root.syncVisibility()
  }

  function withoutPointerWarp(root, action) {
    if (!root.keepPointer || !Hyprland.usingLua) {
      action()
      return
    }
    root.pendingNoWarpActions = root.pendingNoWarpActions.concat([action])
    if (!root.noWarpProcRef.running) root.noWarpProcRef.running = true
  }

  function applyPresetAfterMenu(root, id) {
    root.menuPresetTimerRef.presetId = id
    root.menuPresetTimerRef.restart()
  }
}
