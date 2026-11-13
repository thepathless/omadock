import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "../../DockModel.js" as DockModel
import "../../DockPins.js" as DockPins
import "../../DockIcons.js" as DockIcons

// Logic extracted from Dock.qml: stateless functions, the dock root
// is passed in and owns all state. Bodies are verbatim.

QtObject {
  // Called on drag enter: finds the first directory among the dragged URLs.
  function previewDraggedFolder(root, urls) {
    root.dropCandidatePath = ""
    root.dropPinArmed = false
    var paths = root.localPathsFromUrls(urls)
    if (paths.length === 0) return
    if (root.dropFolderProbeRef.running) root.dropFolderProbeRef.running = false
    root.dropFolderProbeRef.command = ["sh", "-c", 'for p; do [ -d "$p" ] && { printf "%s\\n" "$p"; exit 0; }; done', "sh"].concat(paths)
    root.dropFolderProbeRef.running = true
  }

  function insertFolderPin(root, path, name, icon, index) {
    if (root.isFolderPinned(path)) return
    var next = (root.pinnedFolders || []).slice()
    var at = (index >= 0 && index <= next.length) ? index : next.length
    next.splice(at, 0, { path: path, name: name || "Folder", icon: icon || DockIcons.folderIconFor(path, "") })
    root.pinnedFolders = next
    root.saveConfig()
  }

  function localPathsFromUrls(root, urls) {
    return DockModel.localPathsFromUrls(urls)
  }

  function pinDroppedFolders(root, urls) {
    var paths = root.localPathsFromUrls(urls)
    root.dropFolderCheckRef.insertAt = root.dropInsertIndex
    root.dropPinArmed = false
    root.dropCandidatePath = ""
    root.dropInsertIndex = -1
    if (paths.length === 0) return
    // Only directories are pinned; the check runs out of process.
    root.dropFolderCheckRef.command = ["sh", "-c", 'for p; do [ -d "$p" ] && printf "%s\\n" "$p"; done', "sh"].concat(paths)
    root.dropFolderCheckRef.running = true
  }

  function isBrowserAppId(root, id) {
    if (!id) return false
    var s = String(id).toLowerCase().replace(/\.desktop$/, "")
    return s === "helium"
        || s === "chromium"
        || s === "google-chrome"
        || s === "google-chrome-stable"
        || s === "chrome"
        || s === "brave"
        || s === "brave-browser"
        || s === "firefox"
        || s === "zen"
        || s === "zen-browser"
        || s === "microsoft-edge"
        || s === "microsoft-edge-stable"
        || s === "microsoft-edge-dev"
        || s === "edge"
        || s === "opera"
        || s === "vivaldi"
  }

  function isBrowserPlayer(root, p) {
    if (!p) return false
    var entry = String(p.desktopEntry || "").toLowerCase().replace(/\.desktop$/, "")
    var ident = String(p.identity || "").toLowerCase()
    return isBrowserAppId(root, entry) || isBrowserAppId(root, ident)
  }

  function webAppClaimingPlayer(root, p) {
    if (!root || !root.dockModel || !p) return null
    var track = String(p.trackTitle || (p.metadata && p.metadata["xesam:title"]) || "").toLowerCase().trim()
    var lists = [root.dockModel.pinned, root.dockModel.running, root.dockModel.grouped]
    var webAppFallback = null

    for (var l = 0; l < lists.length; l++) {
      var arr = lists[l] || []
      for (var i = 0; i < arr.length; i++) {
        var ent = arr[i]
        if (!ent) continue
        var entId = String(ent.appId || ent.id || "")
        if (isBrowserAppId(root, entId)) continue
        var wins = ent.windowList || []
        for (var w = 0; w < wins.length; w++) {
          var win = wins[w]
          if (!win) continue
          var wTitle = String(win.title || "").toLowerCase()
          if (track && track.length >= 2 && (wTitle.indexOf(track) >= 0 || track.indexOf(wTitle) >= 0)) {
            return ent
          }
          var wApp = String(win.appId || "").toLowerCase()
          if (wApp.indexOf("chrome-") === 0 || wApp.indexOf("chromium-") === 0) {
            if (!webAppFallback) webAppFallback = ent
          }
        }
      }
    }
    return !track ? webAppFallback : null
  }

  // ------------------------------------------------- media controls
  // The MPRIS player an app exposes, matched on the player's DesktopEntry
  // (or, failing that, its Identity) against the dock app id. When an app is
  // a WebApp (e.g. YouTube, WhatsApp) running inside a browser host, the track
  // title and window ownership attribute the player to the dedicated WebApp tile,
  // and the generic host browser yields.
  function mediaPlayerFor(root, appId) {
    if (!appId || appId.indexOf("__") === 0) return null
    var list = (Mpris.players && Mpris.players.values) ? Mpris.players.values : []
    var fallback = null
    var isBrowser = isBrowserAppId(root, appId)

    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p) continue

      var browserPl = isBrowserPlayer(root, p)
      var matches = false

      if (browserPl) {
        var claimant = webAppClaimingPlayer(root, p)
        if (claimant) {
          var cId = claimant.appId || claimant.id || ""
          matches = (cId === appId || DockModel.isAppMatch(appId, cId))
        } else if (isBrowser) {
          var entry = String(p.desktopEntry || "").replace(/\.desktop$/, "")
          var ident = String(p.identity || "")
          matches = (entry !== "" && DockModel.isAppMatch(appId, entry))
            || (entry === "" && ident !== "" && DockModel.isAppMatch(appId, ident))
        }
      } else {
        var entry = String(p.desktopEntry || "").replace(/\.desktop$/, "")
        var ident = String(p.identity || "")
        matches = (entry !== "" && DockModel.isAppMatch(appId, entry))
          || (entry === "" && ident !== "" && DockModel.isAppMatch(appId, ident))
      }

      if (!matches) continue
      if (p.isPlaying) return p
      if (!fallback) fallback = p
    }
    return fallback
  }

  // ------------------------------------------------- privacy / audio capture
  // Returns true when an app is actively recording audio from a PipeWire source
  // (e.g. Discord, Meet, OBS, Audacity).
  function isMicActiveFor(root, appId) {
    if (!appId || appId.indexOf("__") === 0) return false
    if (typeof Pipewire === "undefined" || !Pipewire || !Pipewire.nodes) return false
    var list = (Pipewire.nodes && Pipewire.nodes.values) ? Pipewire.nodes.values : []
    for (var i = 0; i < list.length; i++) {
      var node = list[i]
      if (!node || !node.isStream || node.isSink || (node.audio && node.audio.muted)) continue
      var props = node.properties || {}
      var appIdProp = props["application.id"] || ""
      var binProp = props["application.process.binary"] || ""
      var nameProp = node.name || ""
      var descProp = node.description || ""
      if (appIdProp && DockModel.isAppMatch(appId, appIdProp)) return true
      if (binProp && DockModel.isAppMatch(appId, binProp)) return true
      if (nameProp && DockModel.isAppMatch(appId, nameProp)) return true
      if (descProp && DockModel.isAppMatch(appId, descProp)) return true
    }
    return false
  }

  // The desktop entry id an app launches through (same lookup as launchApp).
  function desktopIdFor(root, appId) {
    var deskEntry = DockModel.entryFor(root.appRows, appId)
    if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries)
      deskEntry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    return (deskEntry && deskEntry.id) ? deskEntry.id : appId
  }

  function beginAppDrop(root, appId, urls) {
    root.appDropTargetId = appId
    root._appDropOpenId = ""
    root.appDropPaths = root.localPathsFromUrls(urls)
    if (root.appDropPaths.length === 0) {
      root.appDropState = "no"
      return
    }
    root.appDropState = "pending"
    if (root.appDropCheckRef.running) root.appDropCheckRef.running = false
    root.appDropCheckRef.command = ["python3",
      root.scriptPath("drop-check.py"),
      root.desktopIdFor(appId)].concat(root.appDropPaths)
    root.appDropCheckRef.running = true
  }

  function endAppDrop(root, appId) {
    if (root.appDropTargetId !== appId) return
    root.appDropTargetId = ""
    // A drop still waiting on the check keeps its state until it answers.
    if (root._appDropOpenId === "") root.appDropState = ""
  }

  // Returns false when the app cannot take the files (the drop is refused).
  function dropOnApp(root, appId) {
    root.appDropTargetId = ""
    if (root.appDropState === "yes") {
      root.openFilesWith(appId, root.appDropPaths)
      root.appDropState = ""
      return true
    }
    if (root.appDropState === "pending") {
      root._appDropOpenId = appId
      return true
    }
    root.appDropState = ""
    return false
  }

  function openFilesWith(root, appId, paths) {
    if (!paths || paths.length === 0) return
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", "--", root.desktopIdFor(appId) + ".desktop"].concat(paths))
  }

  function entryForId(root, appId) {
    var i
    for (i = 0; i < root.pinnedSection.length; i++) {
      if (root.pinnedSection[i].appId === appId || DockModel.isAppMatch(root.pinnedSection[i].appId, appId))
        return root.pinnedSection[i]
    }
    for (i = 0; i < root.runningSection.length; i++) {
      if (root.runningSection[i].appId === appId || DockModel.isAppMatch(root.runningSection[i].appId, appId))
        return root.runningSection[i]
    }
    var grouped = root.groupedSection || []
    for (i = 0; i < grouped.length; i++) {
      if (grouped[i].appId === appId || DockModel.isAppMatch(grouped[i].appId, appId))
        return grouped[i]
    }
    return null
  }

  function setPinned(root, next) {
    // A group standing before an app that is no longer pinned moves before
    // the next one that is, instead of dropping to the end.
    var groups = DockModel.reanchorGroups(root.appGroups, root.pinnedIds, next)
    root.pinnedIds = next
    root.dockFileRef.setText(DockModel.serializePinned(next))
    if (groups !== root.appGroups) {
      root.appGroups = groups
      root.saveConfig()
    }
  }

  // Puts pinned apps and app groups in the order of a pinnedRow.
  function applyPinnedRow(root, row) {
    var state = DockModel.rowState(row, root.pinnedIds)
    root.appGroups = state.groups
    root.setPinned(state.pins)
    root.saveConfig()
  }

  function togglePin(root, appId) {
    var id = DockModel.stripDesktop(appId)
    if (!id) return
    // Pin-time validation: never pin an id that no longer resolves to an
    // installed desktop entry — the pin could only ever bounce silently.
    // Unpinning bypasses the check so stale pins can always be removed.
    if (!DockPins.isPinned(root.pinnedIds, id) && !root.resolveDesktopEntry(id)) {
      root.notifyAppMissing(id, "pin")
      return
    }
    root.setPinned(DockPins.togglePinned(root.pinnedIds, id, DockModel.isAppMatch))
  }

  function resolveDesktopEntry(root, appId) {
    var entry = DockModel.entryFor(root.appRows, appId)
    if (!entry && typeof DesktopEntries !== "undefined" && DesktopEntries)
      entry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    return entry || null
  }
}
