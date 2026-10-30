import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../../DockModel.js" as DockModel
import "../strings"

// Logic extracted from Dock.qml: stateless functions, the dock root
// is passed in and owns all state. Bodies are verbatim.

QtObject {
  function rescanApps(root) {
    root.terminalHostDebounceRef.restart()
    root.appRows = root.appLibrary ? root.appLibrary.sortedEntries("") : []
    root.refreshDock()
  }

  function handleThemeChanged(root) {
    if (!root._themeApplied) {
      root._themeApplied = true
      root.applyThemeChange()
      return
    }
    root.themeChangeTimerRef.restart()
  }

  // The icon theme is the desktop's (gsettings), so a theme switch re-reads
  // it instead of trusting the theme's icons.theme metadata - the probe falls
  // back to that file only when gsettings cannot answer.
  function applyThemeChange(root) {
    if (root.iconThemeRef) root.iconThemeRef.probeTheme()
    root.themeVersion++
    if (root.appLibrary) {
      try {
        root.appLibrary.refreshIcons()
      } catch (e) {
        console.warn("[omadock] Failed refreshing appLibrary icons:", e)
      }
    }
    root.rescanApps()
  }

  function folderColorLabel(root, colorId) {
    if (!colorId || colorId === "theme" || colorId === "auto") return Tr.t("folderColor.auto", "Auto (Theme)")
    if (colorId === "white") return Tr.t("folderColor.white", "White")
    if (colorId === "black") return Tr.t("folderColor.black", "Black")
    if (colorId === "bw") return Tr.t("folderColor.bw", "Black or white")
    var map = {
      "Yaru-sage": "Sage Green",
      "Yaru-olive": "Olive",
      "Yaru-blue": "Blue",
      "Yaru-purple": "Purple",
      "Yaru-magenta": "Magenta",
      "Yaru-red": "Red",
      "Yaru-yellow": "Yellow",
      "Yaru-wartybrown": "Brown",
      "Yaru-prussiangreen": "Teal",
      "Yaru-dark": "Charcoal"
    }
    return map[colorId] ? Tr.t("folderColor." + colorId, map[colorId]) : colorId
  }

  function setFolderColor(root, color) {
    root.folderColor = color
    root.themeVersion++
    root.saveConfig()
  }

  function openDockSettingsMenu(root, x, y) {
    root.contextName = "Dock Settings"
    root.contextWindows = 0
    root.contextWindowList = []
    root.contextPinned = false
    root.contextX = x
    root.contextY = y
    root.contextAppId = "__dock_settings__"
  }

  function launchApp(root, appId, entry) {
    if (!root.appLibrary) return
    var target = entry || root.entryForId(appId)
    var deskEntry = DockModel.entryFor(root.appRows, appId)
    if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries) {
      deskEntry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    }
    var targetId = (deskEntry && deskEntry.id) ? deskEntry.id : appId
    var targetName = (deskEntry && deskEntry.name) ? deskEntry.name : (target && target.name ? target.name : appId)
    if (deskEntry && deskEntry.id && DockModel.isKnownCli(deskEntry.id) && deskEntry.runInTerminal && deskEntry.command && deskEntry.command.length > 0) {
      var command = ["omarchy-launch-tui", "--app-id=org.omarchy." + deskEntry.id]
        .concat(DockModel.toArray(deskEntry.command))
      Quickshell.execDetached(["bash", "-c", 'cd -- "$1" || exit; shift; exec "$@"',
        "_", deskEntry.workingDirectory || Quickshell.env("HOME")].concat(command))
    } else if (deskEntry && deskEntry.id) {
      root.appLibrary.launch(deskEntry.id, targetName)
    } else {
      var webAppMatch = String(appId).match(/^(?:google-chrome|google-chrome-stable|chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(.*?)__?-(?:default|profile.*)$/i)
                     || String(appId).match(/^(?:google-chrome|google-chrome-stable|chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(.*?)$/i)
      if (webAppMatch) {
        var webDomain = webAppMatch[1].replace(/^https?___?/i, "").replace(/__.*$/, "")
        Quickshell.execDetached(["omarchy-launch-webapp", "https://" + webDomain])
      } else {
        root.appLibrary.launch(targetId, targetName)
      }
    }
    root.markLaunching(appId, target ? target.windows : 0)
  }

  function markLaunching(root, appId, windowsBefore) {
    var pending = DockModel.copyMap(root.launchPending)
    pending[appId] = { deadline: Date.now() + root.launchTimeout, windows: windowsBefore || 0 }
    root.launchPending = pending
    root.launchPruneTimerRef.start()
  }

  // A pending launch ends when the app gained a window, or when waiting stops
  // being informative.
  function pruneLaunching(root) {
    var now = Date.now()
    var next = {}
    var remaining = 0
    var changed = false

    for (var appId in root.launchPending) {
      var pending = root.launchPending[appId]
      var entry = root.entryForId(appId)
      if ((entry && entry.windows > pending.windows) || now >= pending.deadline) {
        changed = true
        continue
      }
      next[appId] = pending
      remaining++
    }

    if (changed) root.launchPending = next
    if (remaining === 0) root.launchPruneTimerRef.stop()
  }

  // Read-only snapshot of the dock items' rectangles in window coordinates,
  // for the benchmark and live tests (IPC itemGeometry). Changes nothing.
  function itemGeometry(root) {
    var out = []
    function add(it, kind, id, windows, urgent) {
      if (!it || !it.visible || it.width <= 0 || it.height <= 0) return
      var p = it.mapToItem(null, 0, 0)
      out.push({ id: String(id || ""), kind: kind,
                 x: Math.round(p.x), y: Math.round(p.y),
                 w: Math.round(it.width), h: Math.round(it.height),
                 windows: windows || 0, urgent: urgent === true,
                 animating: it.urgentFresh === true || it.pulsing === true })
    }
    var card = root.dockCardComp
    // A hidden dock only slides off screen, so its items still look visible.
    if (!card || !root.dockVisible) return "[]"
    var i, it
    var pins = card.liveSlots(card.pinnedRowRepeater)
    for (i = 0; i < pins.length; i++) {
      it = pins[i].child.item
      if (!it) continue
      if (it.groupData !== undefined) add(it, "group", (it.groupData || {}).id, 0, false)
      else if (it.appId !== undefined) add(it, "app", it.appId, it.windows, it.urgent)
    }
    var runs = card.liveSlots(card.runningRepeater)
    for (i = 0; i < runs.length; i++) {
      it = runs[i].child
      add(it, "app", it.appId, it.windows, it.urgent)
    }
    var tiles = card.liveSlots(card.minimizedTilesRepeater)
    for (i = 0; i < tiles.length; i++) add(tiles[i].child, "tile", "", 1, false)
    var folders = card.liveSlots(card.foldersRepeater)
    for (i = 0; i < folders.length; i++) add(folders[i].child, "folder", folders[i].child.folderPath, 0, false)
    var drives = card.liveSlots(card.drivesRepeater)
    for (i = 0; i < drives.length; i++) add(drives[i].child, "drive", drives[i].child.mountpoint, 0, false)
    return JSON.stringify(out)
  }

  // Shared feedback for the "app is gone" classes (launching a stale pin,
  // pinning an unresolvable id) that used to fail silently. The label is
  // markup-escaped: notification bodies are rendered as markup.
  // A drive pulled out while mounted (scripts/drive-removal-watch.py).
  // The label comes from list-drives.py, already cleaned; it is escaped
  // again because notification bodies render markup.
  function notifyUnsafeRemoval(root, name) {
    var label = String(name || Tr.t("notify.aDrive", "A drive")).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    Quickshell.execDetached([
      "bash", root.scriptPath("notify.sh"), "drive-removable-media",
      Tr.t("notify.unsafeRemovalTitle", "Drive removed without ejecting"),
      Tr.t("notify.unsafeRemovalBody", "%1 was removed while still mounted. Recent changes may not have been written; eject it from the dock next time.").arg(label)
    ])
  }

  // reason: what failed, "launch" or "pin"; anything else gets the general advice.
  function notifyAppMissing(root, name, reason) {
    var label = String(name || Tr.t("notify.thisApp", "This app")).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    var advice = reason === "launch" ? Tr.t("notify.missingLaunch", "It cannot be launched — reinstall the app or unpin it from the dock.")
      : reason === "pin" ? Tr.t("notify.missingPin", "It cannot be pinned to the dock — reinstall the app first.")
      : Tr.t("notify.missingAdvice", "Reinstall the app or unpin it from the dock.")
    Quickshell.execDetached([
      "bash", root.scriptPath("notify.sh"), "dialog-error",
      Tr.t("notify.missingTitle", "App no longer installed"),
      Tr.t("notify.missingBody", "%1 is no longer installed. %2").arg(label).arg(advice)
    ])
  }

  function launchDesktopAction(root, action, appName) {
    if (!action) return
    root.markLaunching(root.contextAppId || "", 0)
    try {
      if (typeof action.execute === "function") {
        action.execute()
        return
      }
    } catch (e) {
      console.warn("[omadock] Failed executing desktop action:", e)
    }

    try {
      if (action.command && action.command.length > 0) {
        Quickshell.execDetached(action.command)
      }
    } catch (e2) {
      console.warn("[omadock] Failed launching desktop action command:", e2)
    }
  }

  function syncContextWindows(root) {
    if (!root.contextAppId || root.contextAppId === "__dock_settings__" || root.contextAppId === "__folder_context__" || root.contextAppId === "__tile_context__") return
    var entry = root.entryForId(root.contextAppId)
    var wins = entry && entry.windowList ? entry.windowList : []
    if (wins.length === 0) {
      var allTops = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
      for (var w = 0; w < allTops.length; w++) {
        var top = allTops[w]
        if (top && (top.appId === root.contextAppId || DockModel.isAppMatch(top.appId, root.contextAppId))) {
          var h = root.hyprToplevelFor ? root.hyprToplevelFor(top) : null
          var addr = root.windowAddress(h)
          var ws = h ? h.workspace : null
          var wsName = ws ? String(ws.name || ws.id || "") : (addr && root.minimizedOrigins && root.minimizedOrigins[addr] ? root.minimizedWorkspace : "")
          var isParked = (wsName === root.minimizedWorkspace) || Boolean(addr && root.minimizedOrigins && root.minimizedOrigins[addr])
          wins.push({
            title: String(top.title || "Window"),
            address: addr,
            appId: root.contextAppId,
            workspaceName: isParked ? root.minimizedWorkspace : wsName,
            isMinimized: isParked
          })
        }
      }
    }
    root.contextWindowList = wins
    root.contextWindows = wins.length
    if (root.appContextMenuColumnRef && root.appContextMenuColumnRef.selectedWindowIdx >= wins.length) {
      root.appContextMenuColumnRef.selectedWindowIdx = -1
    }
  }

  // group: the app group the menu was opened from (a cell of the opened
  // group), whose menu offers Remove from Group instead of Pin; null on
  // the dock.
  function openContext(root, appId, x, y, group) {
    root.contextAppGroupData = group || null
    root.contextAppId = appId
    var entry = root.entryForId(appId)
    root.contextName = entry ? entry.name : appId
    root.syncContextWindows()

    var deskEntry = DockModel.entryFor(root.appRows, appId)
    if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries) {
      deskEntry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    }
    var canonicalId = (deskEntry && deskEntry.id) ? deskEntry.id : appId
    root.contextPinned = DockModel.isPinned(root.pinnedIds, appId) || (canonicalId !== appId && DockModel.isPinned(root.pinnedIds, canonicalId))
    root.contextDesktopActions = (deskEntry && deskEntry.actions) ? deskEntry.actions : []
    if (root.appContextMenuColumnRef) root.appContextMenuColumnRef.selectedWindowIdx = -1
    root.contextX = x
    root.contextY = y
  }

  function closeContext(root) {
    root.contextAppId = ""
  }

  function openTileContext(root, wins, appId, cx) {
    root.contextTileWins = wins || []
    root.contextTileAppId = appId || ""
    // Resolve display name from desktop entries
    var deskEntry = DockModel.entryFor(root.appRows, appId)
    if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries)
      deskEntry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    root.contextTileName = root.labelName(appId, (deskEntry && deskEntry.name) ? deskEntry.name : appId)
    var canonicalId = (deskEntry && deskEntry.id) ? deskEntry.id : appId
    root.contextTilePinned = DockModel.isPinned(root.pinnedIds, appId)
      || (canonicalId !== appId && DockModel.isPinned(root.pinnedIds, canonicalId))
    root.contextX = cx
    root.contextY = 0
    root.contextAppId = "__tile_context__"
    root.syncVisibility()
  }

  function restoreContextTile(root) {
    // "Restore here" means the workspace you are on, whatever the config says.
    root.restoreWindowBatch(root.contextTileWins || [], null, false)
  }

  function restoreContextTileOriginal(root) {
    root.restoreWindowBatch(root.contextTileWins || [], null, true)
  }

  function closeContextTile(root) {
    var wins = root.contextTileWins
    for (var i = 0; i < wins.length; i++) {
      var w = wins[i]
      if (w && w.address) root.hyprDispatch(
        'hl.dsp.window.close({ window = "address:' + w.address + '" })',
        "closewindow address:" + w.address)
    }
  }

  // Widest piece of content in the open menu. Only implicit widths are read, so
  // feeding the result back into every row cannot loop.
  function menuContentWidth(root, item) {
    var widest = 0
    if (!item) return widest

    var kids = item.children
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i]
      if (!kid || !kid.visible) continue
      if (kid.isMenuContent === true && kid.implicitWidth > widest) widest = kid.implicitWidth
      var nested = root.menuContentWidth(kid)
      if (nested > widest) widest = nested
    }
    return Math.min(Math.max(widest, 220), Style.space(280))
  }

  function recoverDockSurface(root) {
    if (!root.dockSurfaceClosed || !root.dockScreen) return
    root.dockSurfaceClosed = false
    // Setting visible takes the supported recreate path: setVisibleDirect(true)
    // builds a new backing window and a fresh wlr-layer-shell surface on the
    // current screen. Screen reassignment alone cannot revive a deleted one.
    root.dockWindowRef.visible = true
  }
}
