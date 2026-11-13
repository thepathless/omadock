import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../../DockModel.js" as DockModel
import "../../DockPins.js" as DockPins
import "../../DockIcons.js" as DockIcons
import "../../DockLabels.js" as DockLabels

// Logic extracted from Dock.qml: stateless functions, the dock root
// is passed in and owns all state. Bodies are verbatim.

QtObject {
  // A chooser closed by the compositor rather than through its own Cancel may
  // never answer the portal, which would leave the picker process waiting and
  // swallow every later click. Asking again restarts it instead.
  function pickCustomFolder(root) {
    if (root.customFolderPickerProcRef.running) {
      root.customFolderPickerProcRef.running = false
      Qt.callLater(function() { root.customFolderPickerProcRef.running = true })
      return
    }
    root.customFolderPickerProcRef.running = true
  }

  function scanRemovableDrives(root) {
    if (!root.showRemovableDrives) {
      root.mountedDrives = []
      return
    }
    if (!root.removableDrivesScannerRef.running) root.removableDrivesScannerRef.running = true
  }

  function openDriveContext(root, dev, mp, name, space, cx, cy) {
    root.closeContext()
    root.closeFolderStack()
    root.closeAppGroup()
    root.contextAppId = "__drive_context__"
    root.contextDriveDev = dev || ""
    root.contextDriveMount = mp || ""
    root.contextDriveName = name || "Drive"
    root.contextDriveSpace = space || ""
    root.contextX = cx
    root.contextY = cy
  }

  function ejectDrive(root, dev, mountpoint, name) {
    root.ejectProcRef.dev = dev || ""
    root.ejectProcRef.mountpoint = mountpoint || ""
    root.ejectProcRef.driveName = name || "Drive"
    root.ejectProcRef.running = true
  }

  function openFolderStack(root, path, name, cx) {
    if (root.activeStackFolder === path) {
      root.closeFolderStack()
      return
    }
    root.closeContext()
    // Kill any in-flight scan first: assigning running = true while a process
    // is already running is a no-op in Quickshell, which used to let a slow
    // older scan race the new one.
    if (root.folderStackScannerRef.running) root.folderStackScannerRef.running = false
    root.activeStackFolder = path
    // The open stack moves over the new folder together with its content.
    root.pendingStackX = cx
    if (root.activeStackEntries.length === 0) root.activeStackX = cx
    root.activeStackTrail = []
    root.showStackDir((path || "").replace(/^~/, Quickshell.env("HOME")), name || "Folder")
    root.syncVisibility()
  }

  // Lists dir in the open stack. Kill any in-flight scan first: assigning
  // running = true while a process is already running is a no-op in
  // Quickshell, which used to let a slow older scan race the new one.
  // The scan for the pending folder landed: show it in one step.
  function applyStackScan(root, items, count, truncated, failed) {
    if (root.pendingStackPath === "") return
    root.activeStackPath = root.pendingStackPath
    root.activeStackName = root.pendingStackName
    root.activeStackX = root.pendingStackX
    root.activeStackTruncated = truncated === true
    root.activeStackFailed = failed === true
    root.activeStackTotalCount = count
    root.activeStackEntries = items
    root.activeStackLoading = false
  }

  function showStackDir(root, dir, name) {
    if (root.folderStackScannerRef.running) root.folderStackScannerRef.running = false
    root.pendingStackPath = dir
    root.pendingStackName = name
    root.activeStackLoading = true
    // First open: nothing to keep on screen, so show the header right away.
    if (root.activeStackEntries.length === 0) {
      root.activeStackPath = dir
      root.activeStackName = name
    }
    root.folderStackScannerRef.targetFolder = dir
    root.folderStackScannerRef.sortKey = root.folderSortFor(root.activeStackFolder)
    root.folderStackScannerRef.running = true
  }

  // Step into a subfolder of the open stack.
  function enterStackDir(root, dir, name) {
    var trail = root.activeStackTrail.slice()
    trail.push({ path: root.activeStackPath, name: root.activeStackName })
    root.activeStackTrail = trail
    root.showStackDir(dir, name || dir.split("/").pop() || "Folder")
  }

  function stackBack(root) {
    var trail = root.activeStackTrail.slice()
    if (trail.length === 0) return
    var prev = trail.pop()
    root.activeStackTrail = trail
    root.showStackDir(prev.path, prev.name)
  }

  function closeFolderStack(root) {
    if (root.folderStackScannerRef.running) root.folderStackScannerRef.running = false
    root.activeStackFolder = ""
    root.pendingStackName = ""
    root.pendingStackPath = ""
    root.activeStackLoading = false
    root.activeStackTrail = []
    root.fileDragOut = false
    // Cleared once the popup is gone, so its last frame keeps its content.
    Qt.callLater(function() {
      if (root.activeStackFolder !== "") return
      root.activeStackName = ""
      root.activeStackPath = ""
      root.activeStackEntries = []
    })
  }

  function openFolderContext(root, path, name, cx, cy, command) {
    root.closeFolderStack()
    root.contextFolderPath = path
    root.contextFolderName = name || "Folder"
    // A command button is not a folder: the rows below act on a path it does
    // not have, and unpinning it drops a pinnedButtons entry instead.
    root.contextIsButton = (command || "") !== ""
    root.contextButtonCommand = command || ""
    root.contextX = cx
    root.contextY = cy
    root.contextAppId = "__folder_context__"
    root.syncVisibility()
  }

  function folderSortFor(root, path) {
    var norm = (path || "").replace(/^~/, Quickshell.env("HOME"))
    var list = root.pinnedFolders || []
    for (var i = 0; i < list.length; i++) {
      if ((list[i].path || "").replace(/^~/, Quickshell.env("HOME")) === norm)
        return list[i].sort || "modified"
    }
    return "modified"
  }

  function folderViewFor(root, path) {
    var norm = (path || "").replace(/^~/, Quickshell.env("HOME"))
    var list = root.pinnedFolders || []
    for (var i = 0; i < list.length; i++) {
      if ((list[i].path || "").replace(/^~/, Quickshell.env("HOME")) === norm)
        return list[i].view === "grid" ? "grid" : "stack"
    }
    return "stack"
  }

  // Sets one field (sort, view) on a pinned folder's entry and saves.
  function setFolderOption(root, path, key, value) {
    var norm = (path || "").replace(/^~/, Quickshell.env("HOME"))
    var next = []
    var list = root.pinnedFolders || []
    for (var i = 0; i < list.length; i++) {
      var f = list[i]
      if ((f.path || "").replace(/^~/, Quickshell.env("HOME")) === norm) {
        var patch = {}
        patch[key] = value
        f = Object.assign({}, f, patch)
      }
      next.push(f)
    }
    root.pinnedFolders = next
    root.saveConfig()
  }

  function setFolderSort(root, path, sort) {
    root.setFolderOption(path, "sort", sort)
    // Re-list an open stack of this folder in its new order.
    var open = String(root.activeStackFolder || "").replace(/^~/, Quickshell.env("HOME"))
    if (open !== "" && open === (path || "").replace(/^~/, Quickshell.env("HOME")))
      root.showStackDir(root.activeStackPath, root.activeStackName)
  }

  function setFolderView(root, path, view) {
    root.setFolderOption(path, "view", view === "grid" ? "grid" : "stack")
  }

  function isFolderPinned(root, path) {
    var norm = (path || "").replace(/^~/, Quickshell.env("HOME"))
    var list = root.pinnedFolders || []
    for (var i = 0; i < list.length; i++) {
      var p = (list[i].path || "").replace(/^~/, Quickshell.env("HOME"))
      if (p === norm) return true
    }
    return false
  }

  function toggleFolderPin(root, path, name, icon) {
    var next = []
    var found = false
    var norm = (path || "").replace(/^~/, Quickshell.env("HOME"))
    var list = root.pinnedFolders || []
    for (var i = 0; i < list.length; i++) {
      var f = list[i]
      var p = (f.path || "").replace(/^~/, Quickshell.env("HOME"))
      if (p === norm) {
        found = true
      } else {
        next.push(f)
      }
    }
    if (!found) {
      next.push({ path: path, name: name || "Folder", icon: icon || DockIcons.folderIconFor(path, "") })
    } else {
      // The tile this stack was anchored to is gone; an open popup would
      // otherwise hover over nothing and keep the dock visible. Both sides
      // are normalised: `~/…` and its absolute form name the same folder.
      var open = String(root.activeStackFolder || "").replace(/^~/, Quickshell.env("HOME"))
      if (open !== "" && open === norm) root.closeFolderStack()
    }
    root.pinnedFolders = next
    root.saveConfig()
  }

  // A pinned folder's own name; blank restores the directory's name.
  function renamePinnedFolder(root, path, name) {
    var next = DockLabels.withFolderName(root.pinnedFolders, path, name)
    if (next === root.pinnedFolders) return
    root.pinnedFolders = next
    root.saveConfig()
  }

  // Unpinning a command button drops the pinnedButtons entry its tile was
  // drawn from: there is no folder path to unpin. Matched by the name and
  // command the menu was opened with; identical entries are one button.
  function unpinButton(root, name, command) {
    var list = root.pinnedButtons || []
    var next = []
    var removed = false
    for (var i = 0; i < list.length; i++) {
      var b = list[i]
      if (!removed && b && b.name === name && b.command === command) { removed = true; continue }
      next.push(b)
    }
    if (!removed) return false
    root.pinnedButtons = next
    root.saveConfig()
    return true
  }

  function moveFolder(root, path, insertIndex) {
    var list = root.pinnedFolders || []
    var from = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].path === path) { from = i; break }
    }
    var next = DockPins.moveBefore(list, from, insertIndex)
    if (next === list) return
    root.pinnedFolders = next
    root.saveConfig()
  }
}
