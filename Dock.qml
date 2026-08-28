import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel
import "components"

Item {
  id: root

  // -------------------------------------------------- component references
  readonly property alias dockCardComp: dockCardComp
  readonly property alias dockCard: dockCardComp.dockCard
  readonly property alias cardHover: dockCardComp.cardHover
  readonly property alias pinnedRepeater: dockCardComp.pinnedRepeater
  readonly property alias minimizedTilesRepeater: dockCardComp.minimizedTilesRepeater
  readonly property alias runningRepeater: dockCardComp.runningRepeater
  readonly property alias foldersRepeater: dockCardComp.foldersRepeater
  readonly property alias contextMenu: contextMenuComp
  readonly property alias folderStackPopover: folderStackPopoverComp
  readonly property alias contentItemRef: dockWindow.contentItem
  readonly property alias appContextMenuColumnRef: contextMenuComp.appContextMenuColumn
  readonly property alias customFolderPickerProc: customFolderPickerProc
  readonly property alias folderStackScanner: folderStackScanner

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  readonly property string dockPath: Quickshell.env("HOME") + "/.config/omarchy/dock.json"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/omadock.json"

  property string screenName: ""
  readonly property var dockScreen: {
    var s = root.screenName ? root.screenForName(root.screenName) : null
    if (s) return s
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  function screenForName(name) {
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++)
      if (list[i].name === name) return list[i]
    return null
  }

  readonly property var appLibrary: shell ? shell.appLibrary : null

  // ------------------------------------------------- magnification

  // Raised cosine falloff, the curve Juan Pablo Zamora derived for this effect:
  //   size = min + ((1 - cos t) / 2) * (max - min)
  // over an effectWidth-wide window centred on the cursor, which is
  // 0.5 * (1 + cos(pi * d / R)) for a distance d and half-range R. Flat at the
  // peak and flat where the effect ends, so icons neither snap at the apex nor
  // pop into motion at the edge of the range.
  //
  // Slots grow, and the row grows with them. That is not a stylistic choice:
  // the displacement an icon needs is the accumulated growth between it and the
  // cursor, which integrates to (peak - 1) * R / 2 at the range edge — around
  // 30px per side here. A fixed-width card has nowhere to put that, so nudging
  // icons by a hand-picked amount instead leaves holes next to the pointer and
  // crowding further out. Letting the row carry the extra width is what keeps
  // every gap even.
  //
  // Distances are measured from each slot's *unmagnified* home centre, in
  // window coordinates. Nothing that magnification changes feeds back into
  // those numbers, so the wave cannot chase itself.
  readonly property real magnifyPeak: 1.4
  readonly property real zoomPeak: 1.22
  readonly property real magnifyRange: root.iconSlot * 2.2
  readonly property real baseIconArt: root.iconSize - Style.space(4)

  // The card's own handler, lifted into window coordinates. Both terms move
  // together as the card grows, so their sum stays the physical pointer.
  readonly property real pointerX: cardHover.hovered
    ? dockCardComp.x + cardHover.point.position.x
    : -1e6

  readonly property int appsSlots: root.showAppsButton ? 1 : 0
  // Running apps that actually render an icon. Fully-minimized unpinned apps
  // collapse to zero width (the tile section represents them), so they must
  // not keep dividers alive. When tiles are disabled the icons always show.
  readonly property int visibleRunningCount: {
    var n = 0
    for (var i = 0; i < root.runningSection.length; i++) {
      var item = root.runningSection[i]
      // Live resolver: the cached isMinimized flag can be stale right after a
      // park (Hyprland handle lag), which would keep a dead divider alive.
      if (root.showMinimizedTiles && item && DockModel.allWindowsMinimized(item.windowList, root.liveWsNameOf, root.minimizedWorkspace)) continue
      n++
    }
    return n
  }
  // Slot index of running entry idx among VISIBLE icons only. Fully-tiled
  // entries collapse to zero width, so they must not consume a slot in the
  // wave home-center arithmetic — every icon after one would drift by a
  // full slot. Same predicate as visibleRunningCount, so they never disagree.
  function visibleRunningSlotBefore(idx) {
    var n = 0
    for (var i = 0; i < idx && i < root.runningSection.length; i++) {
      var e = root.runningSection[i]
      if (!(root.showMinimizedTiles && e && DockModel.allWindowsMinimized(e.windowList, root.liveWsNameOf, root.minimizedWorkspace))) n++
    }
    return n
  }
  // Pinned-group | running divider. Sits after the tile section when tiles
  // exist, so it doubles as the right tile divider.
  readonly property bool hasSeparator: (root.pinnedSection.length > 0 || root.hasTiles) && root.visibleRunningCount > 0
  readonly property real gapWidth: Style.space(root.itemSpacing)
  readonly property real separatorWidth: Style.space(1)
  readonly property int folderSlots: root.pinnedFolders ? root.pinnedFolders.length : 0
  readonly property bool hasFolderSeparator: root.folderSlots > 0 && (root.pinnedSection.length > 0 || root.hasTiles || root.visibleRunningCount > 0)

  // Minimized-window preview tiles (macOS-style section on the dock's right).
  // In minimizeMode "all", a parked app's windows compress into ONE stacked
  // group tile; in "active" mode every window keeps its own tile.
  readonly property var tileModel: {
    if (!root.showMinimizedTiles) return []
    var list = root.minimizedWindows
    if (root.minimizeMode !== "all") {
      var singles = []
      for (var s = 0; s < list.length; s++) singles.push({ type: "single", win: list[s] })
      return singles
    }
    var groups = {}
    var order = []
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      var key = w.appId || w.address
      if (!groups[key]) {
        groups[key] = { type: "group", appId: key, title: w.title, windows: [] }
        order.push(key)
      }
      groups[key].windows.push(w)
    }
    // Oldest member parks the group's slot in line.
    order.sort(function (a, b) {
      var ta = root.parkedAt[groups[a].windows[0].address] !== undefined ? root.parkedAt[groups[a].windows[0].address] : 0
      var tb = root.parkedAt[groups[b].windows[0].address] !== undefined ? root.parkedAt[groups[b].windows[0].address] : 0
      return ta - tb
    })
    var out = []
    for (var g = 0; g < order.length; g++) out.push(groups[order[g]])
    return out
  }
  readonly property int tileCount: root.tileModel.length
  readonly property real tileWidth: Math.round(root.iconSlot * 1.5)
  readonly property real tileHeight: Math.round(root.iconSlot * 0.95)
  readonly property bool hasTiles: root.tileCount > 0
  // Left tile divider (pinned|tiles) renders only when pins precede the tiles.
  readonly property bool hasLeftTileSeparator: root.hasTiles && root.pinnedSection.length > 0

  // Width arithmetic total: hidden (fully-tiled) entries occupy zero width,
  // so the row-width and gap math must count only visible icons.
  readonly property int visibleSlotTotal: root.appsSlots + root.pinnedSection.length + root.visibleRunningCount + root.folderSlots
  readonly property int elementTotal: root.visibleSlotTotal
    + (root.hasSeparator ? 1 : 0)
    + (root.hasFolderSeparator ? 1 : 0)
    + (root.hasLeftTileSeparator ? 1 : 0)
    + (root.hasTiles ? root.tileCount : 0)

  readonly property real baseRowWidth: root.visibleSlotTotal * root.iconSlot
    + (root.hasSeparator ? root.separatorWidth : 0)
    + (root.hasFolderSeparator ? root.separatorWidth : 0)
    + (root.hasLeftTileSeparator ? root.separatorWidth : 0)
    + (root.hasTiles ? root.tileCount * root.tileWidth : 0)
    + Math.max(0, root.elementTotal - 1) * root.gapWidth

  // Where the row would start if nothing were magnified. The card is centred,
  // so this only moves when the dock's contents change.
  readonly property real baseRowLeft: (dockWindow.width
    - (root.baseRowWidth + (dockCard ? dockCard.contentLeftInset : 0) + (dockCard ? dockCard.contentRightInset : 0))) / 2
    + (dockCard ? dockCard.contentLeftInset : 0)

  function slotHomeCenter(elementIndex, slotsBefore, sepCount, extraLeftWidth) {
    var seps = (typeof sepCount === "number") ? sepCount : (sepCount ? 1 : 0)
    return root.baseRowLeft
      + elementIndex * root.gapWidth
      + slotsBefore * root.iconSlot
      + seps * root.separatorWidth
      + (extraLeftWidth || 0)
      + root.iconSlot / 2
  }

  // Width the tile section consumes ahead of elements that follow it,
  // including its left divider.
  readonly property real tilesFixedWidth: root.hasTiles
    ? (root.hasLeftTileSeparator ? root.separatorWidth : 0) + root.tileCount * root.tileWidth
    : 0
  readonly property int tileElements: root.hasTiles ? root.tileCount : 0

  function magnifyAt(homeCenter) {
    if (!root.waveHover) return 0
    var distance = root.pointerX - homeCenter
    if (Math.abs(distance) >= root.magnifyRange) return 0
    return 0.5 * (1 + Math.cos(Math.PI * distance / root.magnifyRange))
  }

  function magnifyScaleAt(homeCenter) {
    return 1 + (root.magnifyPeak - 1) * root.magnifyAt(homeCenter)
  }

  // ------------------------------------------------- contrast

  // The bar foreground is tuned for the bar's own background. A custom dock
  // colour can land on the same side of the scale — a light theme's dark text
  // on a dark card, or the reverse — so flip only when the two collide.
  function isLight(value) {
    return (0.2126 * value.r + 0.7152 * value.g + 0.0722 * value.b) > 0.5
  }

  // Corner radius for the dock card. "rounded" tracks the card's own height, so
  // the panel keeps the same visual softness at any icon size.
  readonly property int effectiveCardRadius: {
    var h = dockCard.height > 0 ? dockCard.height : (root.iconSlot + Style.space(10))
    if (root.dockShape === "round" || root.dockShape === "pill") return Math.round(h / 2)
    if (root.dockShape === "square") return 0
    if (root.dockShape === "theme" || root.dockShape === "auto") {
      var n = Style.cornerRadius
      return (typeof n === "number" && isFinite(n) && n >= 0) ? n : Math.max(14, Style.space(14))
    }
    return Math.max(Style.space(14), Math.min(Style.space(28), Math.round(h * 0.26)))
  }

  function cardRadius(height) {
    return root.effectiveCardRadius
  }

  readonly property color dockForeground: {
    var custom = String(root.dockBgColor || "")
    if (custom.charAt(0) !== "#") return Color.bar.text

    // A hand-edited config can hold an invalid hex string; Qt.color() throws
    // on those, which would break this binding and take the whole dock's
    // foreground with it. Fall back to the theme color instead.
    var customColor
    try {
      customColor = Qt.color(custom)
    } catch (e) {
      return Color.bar.text
    }
    var cardIsLight = root.isLight(customColor)
    if (cardIsLight !== root.isLight(Color.bar.text)) return Color.bar.text
    return cardIsLight ? "#12100f" : "#f2efec"
  }

  // ------------------------------------------------- sizing

  property int configuredIconSize: 0
  readonly property int iconSize: root.configuredIconSize > 0
    ? root.configuredIconSize
    : Math.max(28, Math.round(Style.bar.sizeHorizontal * 0.9))
  readonly property int iconSlot: root.iconSize + Style.space(10)

  // ------------------------------------------------- model

  property var pinnedIds: []
  property var appRows: []
  property var dockModel: ({ pinned: [], running: [] })
  // Live scan of parked windows for the preview-tile section. Built straight
  // off Hyprland's own toplevel list, so it cannot go stale the way cached
  // model primitives can.
  property var minimizedWindows: []
  property string _minimizedSig: ""
  readonly property var pinnedSection: root.dockModel.pinned || []
  readonly property var runningSection: root.dockModel.running || []

  function refreshDock() {
    root.dockModel = root.shell && root.shell.appLibrary
      ? DockModel.buildEntries(root.pinnedIds, (ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []), root.appRows,
                               root.shell.appLibrary, root.hyprToplevelFor, root.minimizedWorkspace, root.minimizedOrigins)
      : { pinned: [], running: [] }
    root.rescanMinimizedWindows()
    root.pruneLaunching()
    root.pruneWindowState()
  }

  function rescanMinimizedWindows() {
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
      var top = root.liveToplevelForAddress(addr)
      var title = String((top && top.title) || h.title || "Window")
      var appId = ""
      try {
        appId = h.appId ? DockModel.normalizeId(h.appId)
          : (top && top.appId ? DockModel.normalizeId(top.appId) : "")
      } catch (e) {}
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
    for (var s = 0; s < mins.length; s++) sig += mins[s].address + ","
    if (sig !== root._minimizedSig) {
      root._minimizedSig = sig
      root.minimizedWindows = mins
    }
  }

  readonly property string activeId: {
    try {
      var top = ToplevelManager.activeToplevel
      return top && top.appId ? DockModel.normalizeId(top.appId) : ""
    } catch (e) {
      return ""
    }
  }

  readonly property string activeWindowAddress: {
    try {
      var top = ToplevelManager.activeToplevel
      if (!top) return ""
      var h = root.hyprToplevelFor(top)
      return h ? root.windowAddress(h) : ""
    } catch (e) {
      return ""
    }
  }
  onActiveIdChanged: if (root.activeId) root.clearUrgentApp(root.activeId, root.activeWindowAddress)
  onActiveWindowAddressChanged: if (root.activeWindowAddress) root.clearUrgentApp(root.activeId, root.activeWindowAddress)

  readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace
    ? Hyprland.focusedWorkspace.id
    : -99999

  readonly property string focusedWorkspaceName: Hyprland.focusedWorkspace
    ? String(Hyprland.focusedWorkspace.name || Hyprland.focusedWorkspace.id || "")
    : ""

  // Hyprland has no minimize, so a window is parked on its own hidden special
  // workspace. The workspace name is the state, which means it survives a shell
  // restart; only the origin workspace is remembered here, and losing it just
  // means the window comes back to wherever you are.
  readonly property string minimizedWorkspace: "special:minimized"
  property var minimizedOrigins: ({})
  property var parkedAt: ({})
  property var urgentMap: ({})
  property var recentOpenedWindowAddrs: ({})

  // Per app: the window it parked last, and the window it was in last. Both
  // hold addresses rather than live handles — a closed window then leaves a
  // stale string that the next prune drops, instead of a dangling object.
  // Hyprland's own focusHistoryID would save the bookkeeping, but Quickshell
  // only refreshes lastIpcObject on window open/close, so it goes stale the
  // moment focus moves.
  property var appRecentWindow: ({})

  // Apps whose launch has been asked for but whose window has not shown up yet.
  property var launchPending: ({})
  readonly property int launchTimeout: 12000

  // ------------------------------------------------- drag reorder state

  property string dragAppId: ""
  property string dropBeforeId: ""
  property real dropIndicatorX: 0

  // ------------------------------------------------- context menu

  property string contextAppId: ""
  property string contextName: ""
  property bool contextPinned: false
  property int contextWindows: 0
  property var contextWindowList: []
  property var contextDesktopActions: []
  property real contextX: 0
  property real contextY: 0

  // ------------------------------------------------- folder stacks state

  property var pinnedFolders: []
  property string activeStackFolder: ""
  property string activeStackName: ""
  property var activeStackEntries: []
  property int activeStackTotalCount: 0
  property real activeStackX: 0
  property string contextFolderPath: ""
  property string contextFolderName: ""

  // ------------------------------------------------- configuration options

  property bool autohide: true
  property bool intelligentAutohide: true
  property bool showAppsButton: true
  property bool showTooltips: true
  property bool showMinimizedTiles: true
  // "zoom" grows only the icon under the pointer and leaves the layout alone —
  // the behaviour this dock shipped with, and the default. "wave" is the
  // falloff: neighbours respond and the row carries the extra width. "off" is
  // no hover growth at all.
  property string hoverEffect: "zoom"
  readonly property bool waveHover: root.hoverEffect === "wave"
  property bool launchBounce: true
  property bool advancedTooltips: true
  property real dockOpacity: 1.0
  readonly property real effectiveDockOpacity: {
    if (root.dockOpacity < 0) {
      var a = (Color.bar && Color.bar.background && typeof Color.bar.background.a === "number") ? Color.bar.background.a : 1.0
      return (isFinite(a) && a >= 0) ? a : 1.0
    }
    return Math.max(0.0, Math.min(1.0, root.dockOpacity))
  }
  property string dockShape: "rounded"
  property string dockBgColor: "theme"
  property int themeVersion: 0
  property string currentIconThemeName: "Yaru"
  property string folderColor: "theme"
  property int itemSpacing: 4
  property string minimizeMode: "active"
  readonly property bool clickToMinimize: root.minimizeMode !== "off"
  property bool showUrgentHint: true
  property bool urgentOnNotification: true
  property bool urgentSound: true
  property string urgentSoundName: "bell"
  property var notifService: null
  property var _lastProcessedNotifTimestamp: 0
  property int revealDelay: 160
  property int tooltipDelay: 450
  property string settingsSubmenu: ""

  // ------------------------------------------------- autohide state

  property bool dockVisible: false
  readonly property int revealHeight: 6

  property bool windowsOverlapDock: false

  Timer {
    id: hideTimer
    interval: 350
    onTriggered: root.dockVisible = false
  }

  // Dwell on the screen edge before revealing, so a pointer travelling to the
  // bottom of a window does not summon the dock on its way past.
  Timer {
    id: revealTimer
    interval: root.revealDelay
    onTriggered: root.dockVisible = true
  }

  // Coalesces model rebuilds: several signals can describe one window change.
  Timer {
    id: modelTimer
    interval: 40
    onTriggered: root.refreshDock()
  }

  // One-shot deferred rebuild after park/restore moves and configreloaded events,
  // so model state is re-frozen once Hyprland handles settle.
  Timer {
    id: modelSettleTimer
    interval: 300
    onTriggered: root.refreshDock()
  }

  Timer {
    id: launchPruneTimer
    interval: 500
    repeat: true
    onTriggered: root.pruneLaunching()
  }

  // Reactive, debounced overlap check — zero CPU polling loops
  Timer {
    id: debounceOverlapTimer
    interval: 60
    repeat: false
    onTriggered: {
      if (root.autohide && root.intelligentAutohide) {
        overlapProc.running = true
      }
    }
  }

  // Periodic fallback overlap check — deliberate exception to the zero-CPU-polling invariant.
  // Hyprland does not emit IPC events for in-progress window drags, so there is no event-driven
  // way to detect a window being dragged over the dock. This timer fires at 350ms while the dock
  // is visible and uncovered, catching that case. It is fully gated: stops when hidden, when the
  // user hovers the dock card, and during menus / drag reorder — so CPU cost is zero at rest.
  Timer {
    id: intelligentOverlapCheckTimer
    interval: 350
    repeat: true
    running: root.autohide && root.intelligentAutohide && root.dockVisible && !(root.cardHover && root.cardHover.hovered) && !(revealHover && revealHover.hovered) && root.contextAppId === "" && root.dragAppId === ""
    onTriggered: {
      if (!overlapProc.running) overlapProc.running = true
    }
  }

  Process {
    id: overlapProc
    command: ["hyprctl", "-j", "clients"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var clients = []
        try {
          clients = JSON.parse(this.text) || []
        } catch (e) {
          return
        }

        // Logical monitor dimensions accounting for fractional scaling.
        // Resolve the monitor this dock actually lives on — the globally
        // focused monitor is the wrong coordinate frame on multi-monitor
        // setups whenever focus sits on another output.
        var mon = null
        var dockName = dockScreen ? String(dockScreen.name || "") : ""
        if (dockName !== "" && Hyprland.monitors) {
          var monitors = Hyprland.monitors.values || []
          for (var m = 0; m < monitors.length; m++) {
            if (monitors[m] && String(monitors[m].name || "") === dockName) {
              mon = monitors[m]
              break
            }
          }
        }
        if (!mon) mon = Hyprland.focusedMonitor
        var scale = (mon && mon.scale > 0)
          ? mon.scale
          : (dockScreen && dockScreen.devicePixelRatio ? dockScreen.devicePixelRatio : 1.0)
        var screenLogicalW = (mon && mon.width > 0)
          ? (mon.width / scale)
          : (dockScreen ? dockScreen.width : 1920)
        var screenLogicalH = (mon && mon.height > 0)
          ? (mon.height / scale)
          : (dockScreen ? dockScreen.height : 1080)

        var cardW = (dockCard && dockCard.width > 0) ? (dockCard.width + Style.gapsOut * 2) : 320
        var cardH = (dockCard && dockCard.height > 0) ? (dockCard.height + Style.gapsOut * 2) : 60
        var monX = (mon && typeof mon.x === "number") ? mon.x : 0
        var monY = (mon && typeof mon.y === "number") ? mon.y : 0
        var dockLeft = monX + (screenLogicalW - cardW) / 2
        var dockRight = monX + (screenLogicalW + cardW) / 2
        var dockTop = monY + screenLogicalH - cardH - 12
        var dockBottom = monY + screenLogicalH

        var overlap = false
        // Compare against the dock monitor's own active workspace, not the
        // global focus — windows visible next to the dock on its output are
        // the ones that can overlap it.
        var dockWsId = (mon && mon.activeWorkspace) ? mon.activeWorkspace.id : -1

        for (var i = 0; i < clients.length; i++) {
          var c = clients[i]
          if (!c.mapped || c.hidden) continue
          if (!c.pinned && (!c.workspace || c.workspace.id !== dockWsId)) continue

          var at = c.at
          var sz = c.size
          if (!at || !sz || at.length < 2 || sz.length < 2) continue

          var winLeft = at[0]
          var winTop = at[1]
          var winRight = at[0] + sz[0]
          var winBottom = at[1] + sz[1]

          // 2D Axis-Aligned Bounding Box (AABB) intersection check with dock area
          var intersectsX = (winRight > dockLeft) && (winLeft < dockRight)
          var intersectsY = (winBottom > dockTop) && (winTop < dockBottom)

          if (intersectsX && intersectsY) {
            overlap = true
            break
          }
        }

        root.windowsOverlapDock = overlap
      }
    }
  }

  Process {
    id: folderStackScanner
    property string targetFolder: ""
    command: ["python3", "-c", "import os, json, time, sys\nfolder = os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else ''\nif not folder or not os.path.exists(folder):\n    print(json.dumps({'count':0,'items':[],'folder':folder}))\n    sys.exit(0)\nentries = []\ntry:\n    for entry in os.scandir(folder):\n        try:\n            if entry.name.startswith('.'):\n                continue\n            stat = entry.stat()\n            is_dir = entry.is_dir()\n            size_bytes = stat.st_size if not is_dir else 0\n            if size_bytes < 1024:\n                size_str = f'{size_bytes} B'\n            elif size_bytes < 1024 * 1024:\n                size_str = f'{size_bytes / 1024:.1f} KB'\n            elif size_bytes < 1024 * 1024 * 1024:\n                size_str = f'{size_bytes / (1024 * 1024):.1f} MB'\n            else:\n                size_str = f'{size_bytes / (1024 * 1024 * 1024):.1f} GB'\n            diff = time.time() - stat.st_mtime\n            if diff < 60:\n                time_str = 'Just now'\n            elif diff < 3600:\n                time_str = f'{int(diff // 60)}m ago'\n            elif diff < 86400:\n                time_str = f'{int(diff // 3600)}h ago'\n            else:\n                time_str = f'{int(diff // 86400)}d ago'\n            ext = os.path.splitext(entry.name)[1].lower()\n            is_img = ext in ['.png', '.jpg', '.jpeg', '.webp', '.svg', '.gif']\n            if is_dir:\n                icon = 'folder'\n            elif is_img:\n                icon = 'image-x-generic'\n            elif ext in ['.mp4', '.mkv', '.webm', '.mov', '.avi']:\n                icon = 'video-x-generic'\n            elif ext in ['.mp3', '.flac', '.wav', '.ogg', '.m4a']:\n                icon = 'audio-x-generic'\n            elif ext in ['.zip', '.tar', '.gz', '.xz', '.7z', '.rar']:\n                icon = 'package-x-generic'\n            elif ext in ['.pdf']:\n                icon = 'application-pdf'\n            elif ext in ['.txt', '.md', '.json', '.qml', '.py', '.cpp', '.js', '.lua', '.rs', '.go', '.html', '.css']:\n                icon = 'text-x-generic'\n            else:\n                icon = 'application-x-executable'\n            entries.append({'name': entry.name, 'path': entry.path, 'isDir': is_dir, 'isImage': is_img, 'size': size_str, 'time': time_str, 'mtime': stat.st_mtime, 'icon': icon})\n        except Exception:\n            pass\nexcept Exception:\n    pass\nentries.sort(key=lambda x: x['mtime'], reverse=True)\nprint(json.dumps({'count': len(entries), 'items': entries[:16], 'folder': folder}))\n", folderStackScanner.targetFolder]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(this.text) || { count: 0, items: [] }
          // Stale-result guard: only apply if this scan is still for the
          // folder the user currently has open (or any at all). Prevents a
          // slow older scan from painting one folder's files under another's
          // header, or repopulating after the stack was closed.
          var wanted = String(root.activeStackFolder || "").replace(/^~/, Quickshell.env("HOME"))
          if (parsed.folder !== wanted) return
          root.activeStackTotalCount = parsed.count || 0
          root.activeStackEntries = parsed.items || []
        } catch (e) {
          root.activeStackTotalCount = 0
          root.activeStackEntries = []
        }
      }
    }
  }

  Process {
    id: customFolderPickerProc
    command: ["python3", "-c", "import sys, subprocess, shutil\ntry:\n    import gi\n    gi.require_version('Gtk', '3.0')\n    from gi.repository import Gtk\n    dialog = Gtk.FileChooserDialog(title='Select Folder to Pin to Dock', action=Gtk.FileChooserAction.SELECT_FOLDER)\n    dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OPEN, Gtk.ResponseType.OK)\n    res = dialog.run()\n    if res == Gtk.ResponseType.OK:\n        print(dialog.get_filename())\n    dialog.destroy()\nexcept Exception:\n    if shutil.which('zenity'):\n        res = subprocess.run(['zenity', '--file-selection', '--directory', '--title=Select Folder to Pin to Dock'], capture_output=True, text=True)\n        if res.returncode == 0 and res.stdout.strip():\n            print(res.stdout.strip())\n    elif shutil.which('kdialog'):\n        res = subprocess.run(['kdialog', '--getexistingdirectory', '--title', 'Select Folder to Pin to Dock'], capture_output=True, text=True)\n        if res.returncode == 0 and res.stdout.strip():\n            print(res.stdout.strip())\n"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var chosen = String(this.text || "").trim()
        if (chosen.length > 0) {
          var baseName = chosen.split("/").pop() || "Folder"
          var home = Quickshell.env("HOME")
          var relPath = (chosen.indexOf(home) === 0) ? chosen.replace(home, "~") : chosen
          root.toggleFolderPin(relPath, baseName, DockModel.folderIconFor(relPath, ""))
        }
      }
    }
  }

  function syncVisibility() {
    // Mode 1: Always Show
    if (!root.autohide) {
      hideTimer.stop()
      revealTimer.stop()
      root.dockVisible = true
      return
    }

    var isHovered = (root.cardHover && root.cardHover.hovered) || (revealHover && revealHover.hovered) || root.contextAppId !== "" || root.dragAppId !== "" || root.activeStackFolder !== ""

    // Hovered, Context Menu Open, or Dragging: keep visible
    if (isHovered) {
      hideTimer.stop()
      if (root.dockVisible) revealTimer.stop()
      else if (!revealTimer.running) revealTimer.restart()
      return
    }

    revealTimer.stop()

    // Mode 3: Intelligent Autohide without window overlap -> stay visible on empty desktop
    if (root.intelligentAutohide && !root.windowsOverlapDock) {
      hideTimer.stop()
      root.dockVisible = true
      return
    }

    // Standard Autohide OR Intelligent Autohide with overlapping window -> hide after delay
    if (root.dockVisible) {
      hideTimer.restart()
    }
  }

  onContextAppIdChanged: root.syncVisibility()
  onActiveStackFolderChanged: root.syncVisibility()
  onDragAppIdChanged: root.syncVisibility()
  onAutohideChanged: root.syncVisibility()
  onIntelligentAutohideChanged: {
    if (root.intelligentAutohide) debounceOverlapTimer.restart()
    root.syncVisibility()
  }
  onWindowsOverlapDockChanged: root.syncVisibility()
  onDockVisibleChanged: {
    if (!root.dockVisible) {
      root.closeContext()
      root.closeFolderStack()
    }
  }

  // ------------------------------------------------- file views

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    onLoaded: root.loadConfig()
    onFileChanged: configFile.reload()
  }

  FileView {
    id: dockFile
    path: root.dockPath
    watchChanges: true
    atomicWrites: true
    onLoaded: root.loadPinned()
    onFileChanged: dockFile.reload()
  }

  FileView {
    id: themeIconsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/icons.theme"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var t = String(themeIconsFile.text() || "").trim()
        if (t) root.currentIconThemeName = t
      } catch (e) {}
      root.handleThemeChanged()
    }
    onFileChanged: {
      themeIconsFile.reload()
      try {
        var t = String(themeIconsFile.text() || "").trim()
        if (t) root.currentIconThemeName = t
      } catch (e) {}
      root.handleThemeChanged()
    }
  }

  FileView {
    id: themeColorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    onLoaded: root.handleThemeChanged()
    onFileChanged: {
      themeColorsFile.reload()
      root.handleThemeChanged()
    }
  }

  FileView {
    id: dndConfigFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/notifications.json"
    watchChanges: true
    printErrors: false
    onFileChanged: dndConfigFile.reload()
  }

  readonly property bool isDndActive: {
    if (root.notifService && typeof root.notifService.doNotDisturb === "boolean") {
      return root.notifService.doNotDisturb
    }
    try {
      var txt = String(dndConfigFile.text() || "").trim()
      if (txt) {
        var parsed = JSON.parse(txt)
        if (parsed && typeof parsed.dnd === "boolean") return parsed.dnd
      }
    } catch (e) {}
    return false
  }

  // ------------------------------------------------- reactive event connections

  Connections {
    target: Color
    function onShellValuesChanged() { root.handleThemeChanged() }
    function onForegroundChanged() { root.handleThemeChanged() }
    function onAccentChanged() { root.handleThemeChanged() }
  }

  Connections {
    target: Style
    function onFontFamilyChanged() { root.handleThemeChanged() }
  }

  Connections {
    target: root.appLibrary
    enabled: target !== null
    function onAppsChanged() { root.rescanApps() }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() {
      modelTimer.restart()
      debounceOverlapTimer.restart()
      root.syncContextWindows()
    }
  }

  // Hyprland resolves its own handle for a window slightly apart from the
  // Wayland announcement; rebuilding on both is what keeps the handles attached.
  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      modelTimer.restart()
    }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      try {
        var top = ToplevelManager.activeToplevel
        if (top && top.appId) {
          var aid = DockModel.normalizeId(top.appId)
          var address = root.windowAddress(root.hyprToplevelFor(top))
          if (aid && address) {
            var recent = DockModel.copyMap(root.appRecentWindow)
            recent[aid] = address
            root.appRecentWindow = recent
          }
          root.clearUrgentApp(aid, address)
        } else if (top) {
          var addressOnly = root.windowAddress(root.hyprToplevelFor(top))
          if (addressOnly) root.clearUrgentApp("", addressOnly)
        }
      } catch (e) {}
      debounceOverlapTimer.restart()
      root.syncContextWindows()
    }
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      debounceOverlapTimer.restart()
    }
    function onRawEvent(event) {
      var n = String((event && event.name) || "")
      if (n === "openwindow") {
        var rawAddr = String(event.data || "").split(",")[0].trim()
        if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
        var fullAddr = "0x" + rawAddr
        var rec = DockModel.copyMap(root.recentOpenedWindowAddrs)
        rec[fullAddr] = Date.now() + 3000
        root.recentOpenedWindowAddrs = rec
      }
      if (n === "urgent") {
        var rawAddr = String(event.data || "").trim()
        if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
        var fullAddr = "0x" + rawAddr

        // Foreground Suppression Rule: If the window is ALREADY active and focused, suppress urgency
        var activeAddr = root.windowAddress(root.hyprToplevelFor(ToplevelManager.activeToplevel))
        if (activeAddr && activeAddr === fullAddr) {
          return
        }

        // Suppress initial window startup / opening urgency
        if (root.recentOpenedWindowAddrs && root.recentOpenedWindowAddrs[fullAddr] && Date.now() < root.recentOpenedWindowAddrs[fullAddr]) {
          return
        }

        // Suppress if the app was recently launched by user
        var allEntries = root.pinnedSection.concat(root.runningSection)
        for (var e = 0; e < allEntries.length; e++) {
          var entry = allEntries[e]
          if (!entry) continue
          if (root.launchPending && root.launchPending[entry.id]) {
            var wins = entry.windowList || []
            for (var w = 0; w < wins.length; w++) {
              var wa = wins[w] ? wins[w].address : ""
              if (wa && wa === fullAddr) {
                return
              }
            }
          }
        }

        var map = DockModel.copyMap(root.urgentMap)
        map[fullAddr] = true
        root.urgentMap = map
        modelTimer.restart()
      }
      if (n === "activewindow" || n === "activewindowv2") {
        var eventData = String(event.data || "").trim()
        if (n === "activewindowv2") {
          var rawAddr = eventData.split(",")[0].trim()
          if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
          var fullAddr = "0x" + rawAddr
          root.clearUrgentApp("", fullAddr)
        } else {
          var winClass = eventData.split(",")[0].trim()
          if (winClass) root.clearUrgentApp(winClass, "")
        }
      }
      if (n === "closewindow") {
        var rawAddr = String(event.data || "").trim()
        if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
        var fullAddr = "0x" + rawAddr
        if (root.recentOpenedWindowAddrs && root.recentOpenedWindowAddrs[fullAddr]) {
          var rec = DockModel.copyMap(root.recentOpenedWindowAddrs)
          delete rec[fullAddr]
          root.recentOpenedWindowAddrs = rec
        }
        if (root.urgentMap && root.urgentMap[fullAddr]) {
          var map = DockModel.copyMap(root.urgentMap)
          delete map[fullAddr]
          root.urgentMap = map
        }
        if (root.minimizedOrigins && root.minimizedOrigins[fullAddr]) {
          var mo = DockModel.copyMap(root.minimizedOrigins)
          delete mo[fullAddr]
          root.minimizedOrigins = mo
        }
        root.refreshDock()
      }
      if (n === "workspace" || n === "workspacev2" || n === "openwindow" || n === "closewindow" ||
          n === "movewindow" || n === "movewindowv2" || n === "resizewindow" || n === "resizewindowv2" ||
          n === "activewindow" || n === "activewindowv2" || n === "changefloatingmode" ||
          n === "fullscreen" || n === "pin" || n === "focusedmon" ||
          n === "monitoradded" || n === "monitorremoved") {
        debounceOverlapTimer.restart()
      }
      if (n === "openwindow" || n === "closewindow" || n === "urgent"
          || n === "movewindow" || n === "movewindowv2"
          || n === "workspace" || n === "workspacev2") modelTimer.restart()
      // Park/restore moves get one deferred rebuild: the 40ms rebuild can land
      // inside Quickshell's Hyprland-handle lag and freeze pre-move state into
      // the model (stale isMinimized kept the running icon beside its tile).
      // Event-driven single shot — self-terminating, no polling.
      if (n === "movewindow" || n === "movewindowv2") modelSettleTimer.restart()
      // configreloaded fires Quickshell refreshWorkspaces + refreshToplevels
      // which destroy/recreate workspace objects and re-assign toplevel handles.
      // Settle handles cleanly via modelSettleTimer.
      if (n === "configreloaded") modelSettleTimer.restart()
    }
  }

  function updateNotifService() {
    if (!root.notifService && root.shell && typeof root.shell.serviceFor === "function") {
      var s = root.shell.serviceFor("omarchy.notifications") || root.shell.firstPartyServiceFor("omarchy.notifications")
      if (s) {
        root.notifService = s
        root._notifServiceAttempts = 0
      }
    }
  }

  // Startup retry poll for the notifications service. Self-terminates once
  // resolved; capped at ~5s (25 ticks) so a shell that never exposes the
  // service can't keep the event loop awake forever (zero-CPU invariant).
  property int _notifServiceAttempts: 0
  Timer {
    id: serviceCheckTimer
    interval: 200
    repeat: true
    running: !root.notifService && root._notifServiceAttempts < 25
    onTriggered: {
      root._notifServiceAttempts++
      root.updateNotifService()
    }
  }

  function handleNotificationReceived(row) {
    if (!row) return
    var ts = row.timestamp || row.id || 0
    if (ts && ts === root._lastProcessedNotifTimestamp) return
    root._lastProcessedNotifTimestamp = ts

    var allEntries = root.pinnedSection.concat(root.runningSection)
    var matchedEntries = DockModel.findNotificationTargets(allEntries, root.appRows, row)
    if (!matchedEntries || matchedEntries.length === 0) return

    var activeHandle = root.hyprToplevelFor(ToplevelManager.activeToplevel)
    var activeAddr = root.windowAddress(activeHandle)

    var map = DockModel.copyMap(root.urgentMap)
    var found = false

    for (var e = 0; e < matchedEntries.length; e++) {
      var entry = matchedEntries[e]
      if (!entry) continue
      var appId = entry.appId || entry.id
      var wins = entry.windowList || []
      var isFocused = false

      for (var w = 0; w < wins.length; w++) {
        var wa = wins[w] ? wins[w].address : ""
        if (wa && wa === activeAddr) {
          isFocused = true
          break
        }
      }

      if (!isFocused && root.activeId && (DockModel.isAppMatch(appId, root.activeId) || (entry.id && DockModel.isAppMatch(entry.id, root.activeId)))) {
        isFocused = true
      }

      // Foreground Suppression Rule: An app currently focused in the foreground suppresses urgency bounce
      if (!isFocused) {
        map[appId] = true
        for (var w2 = 0; w2 < wins.length; w2++) {
          var wa2 = wins[w2] ? wins[w2].address : ""
          if (wa2) map[wa2] = true
        }
        found = true
      }
    }

    if (found) {
      root.urgentMap = map
      modelTimer.restart()
    }

    // Play notification alert sound (suppressed if DND is active)
    if (root.urgentSound && root.urgentSoundName !== "none" && !root.isDndActive) {
      Quickshell.execDetached(["canberra-gtk-play", "-i", root.urgentSoundName])
    }
  }

  Connections {
    target: root.notifService ? root.notifService.popupModel : null
    function onRowsInserted(parent, first, last) {
      if (!root.showUrgentHint || !root.urgentOnNotification || !root.notifService || !root.notifService.popupModel) return
      for (var i = first; i <= last; i++) {
        var row = root.notifService.popupModel.get(i)
        if (row) root.handleNotificationReceived(row)
      }
    }
    function onCountChanged() {
      if (!root.showUrgentHint || !root.urgentOnNotification || !root.notifService || !root.notifService.popupModel) return
      if (root.notifService.popupModel.count > 0) {
        var row = root.notifService.popupModel.get(0)
        if (row) root.handleNotificationReceived(row)
      }
    }
  }

  onShellChanged: {
    root.updateNotifService()
    root.rescanApps()
  }
  onPinnedIdsChanged: root.refreshDock()

  // ------------------------------------------------- functions

  function loadPinned() {
    root.pinnedIds = DockModel.parsePinned(dockFile.text())
  }

  function loadConfig() {
    var raw = String(configFile.text() || "").trim()
    var parsed = {}
    if (raw) {
      try {
        parsed = JSON.parse(raw)
      } catch (e) {
        parsed = {}
      }
    }
    root.autohide = parsed && parsed.autohide !== false
    root.intelligentAutohide = parsed && parsed.intelligentAutohide !== false
    root.showAppsButton = parsed && parsed.showAppsButton !== false
    root.showTooltips = parsed && parsed.showTooltips !== false
    root.showMinimizedTiles = parsed ? parsed.showMinimizedTiles !== false : true
    // Migrates the old boolean: an explicit magnification:false meant no growth.
    root.hoverEffect = parsed && typeof parsed.hoverEffect === "string"
      ? parsed.hoverEffect
      : ((parsed && parsed.magnification === false) ? "off" : "zoom")
    root.launchBounce = parsed && parsed.launchBounce !== false
    root.advancedTooltips = parsed && parsed.advancedTooltips !== false
    root.screenName = parsed && typeof parsed.screen === "string" ? parsed.screen : ""
    root.configuredIconSize = parsed && typeof parsed.iconSize === "number" ? parsed.iconSize : 0
    if (parsed && (parsed.opacity === "theme" || parsed.opacity === "auto" || parsed.opacity === -1)) {
      root.dockOpacity = -1.0
    } else if (parsed && typeof parsed.opacity === "number") {
      root.dockOpacity = Math.max(0.0, Math.min(1.0, parsed.opacity))
    } else {
      root.dockOpacity = 1.0
    }
    root.dockShape = parsed && typeof parsed.shape === "string" ? parsed.shape : "rounded"
    root.dockBgColor = parsed && typeof parsed.bgColor === "string" ? parsed.bgColor : "theme"
    root.folderColor = parsed && typeof parsed.folderColor === "string" ? parsed.folderColor : "theme"
    root.itemSpacing = parsed && typeof parsed.itemSpacing === "number" ? parsed.itemSpacing : 4
    if (parsed && typeof parsed.minimizeMode === "string") {
      root.minimizeMode = parsed.minimizeMode
    } else if (parsed && parsed.clickToMinimize === true) {
      root.minimizeMode = "active"
    } else {
      root.minimizeMode = "active"
    }
    root.showUrgentHint = parsed ? parsed.showUrgentHint !== false : true
    root.urgentOnNotification = parsed ? parsed.urgentOnNotification !== false : true
    root.urgentSound = parsed ? parsed.urgentSound !== false : true
    root.urgentSoundName = parsed && typeof parsed.urgentSoundName === "string" ? parsed.urgentSoundName : "bell"
    root.revealDelay = parsed && typeof parsed.revealDelay === "number"
      ? Math.max(0, Math.min(2000, Math.round(parsed.revealDelay)))
      : 160
    root.tooltipDelay = parsed && typeof parsed.tooltipDelay === "number"
      ? Math.max(0, Math.min(5000, Math.round(parsed.tooltipDelay)))
      : 450
    if (parsed && Array.isArray(parsed.pinnedFolders)) {
      root.pinnedFolders = parsed.pinnedFolders
    } else {
      root.pinnedFolders = [
        { path: "~/Downloads", name: "Downloads", icon: "folder-download" }
      ]
    }
  }

  function rescanApps() {
    root.appRows = root.shell && root.shell.appLibrary ? root.shell.appLibrary.sortedEntries("") : []
    root.refreshDock()
  }

  function handleThemeChanged() {
    try {
      var t = String(themeIconsFile.text() || "").trim()
      if (t) root.currentIconThemeName = t
    } catch (e) {}
    root.themeVersion++
    if (root.shell && root.shell.appLibrary) {
      try { root.shell.appLibrary.refreshIcons() } catch (e) {}
    }
    root.rescanApps()
  }

  function folderColorLabel(colorId) {
    if (!colorId || colorId === "theme" || colorId === "auto") return "Auto (Theme)"
    if (colorId === "white") return "White"
    if (colorId === "black") return "Black"
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
    return map[colorId] || colorId
  }

  function setFolderColor(color) {
    root.folderColor = color
    root.themeVersion++
    root.saveConfig()
  }

  function openDockSettingsMenu(x, y) {
    root.contextName = "Dock Settings"
    root.contextWindows = 0
    root.contextWindowList = []
    root.contextPinned = false
    root.contextX = x
    root.contextY = y
    root.settingsSubmenu = ""
    root.contextAppId = "__dock_settings__"
  }

  function setAutohideMode(mode) {
    if (mode === "always") {
      root.autohide = false
      root.intelligentAutohide = false
    } else if (mode === "intelligent") {
      root.autohide = true
      root.intelligentAutohide = true
    } else if (mode === "autohide") {
      root.autohide = true
      root.intelligentAutohide = false
    }
    root.saveConfig()
    root.syncVisibility()
  }

  function setDockOpacity(val) {
    root.dockOpacity = val
    root.saveConfig()
  }

  function setHoverEffect(mode) {
    root.hoverEffect = mode
    root.saveConfig()
  }

  function setDockShape(shape) {
    root.dockShape = shape
    root.saveConfig()
  }

  function setDockBgColor(col) {
    root.dockBgColor = col
    root.saveConfig()
  }

  function setIconSize(sz) {
    root.configuredIconSize = sz
    root.saveConfig()
  }

  function setItemSpacing(sp) {
    root.itemSpacing = sp
    root.saveConfig()
  }

  function setUrgentSoundName(name) {
    root.urgentSoundName = name
    root.urgentSound = name !== "none"
    if (name !== "none" && !root.isDndActive) {
      Quickshell.execDetached(["canberra-gtk-play", "-i", name])
    }
    root.saveConfig()
  }

  function cycleApp(appId, direction) {
    var entry = root.entryForId(appId)
    var next = root.stepWindow(root.visibleWindows(entry ? (entry.windowList || []) : []), direction)
    if (next && next.address) {
      root.focusWindowByAddress(next.address, appId)
      return
    }
    // No handles to tell parked from visible: fall back to the pure order.
    var top = DockModel.pickAppWindow(
      (ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []), ToplevelManager.activeToplevel, appId, direction)
    if (top) root.focusToplevel(top, appId)
  }

  // ------------------------------------------------- window plumbing

  function hyprToplevelFor(toplevel) {
    if (!toplevel || !Hyprland.toplevels) return null
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].wayland === toplevel) return list[i]
    return null
  }

  function windowAddress(handle) {
    var value = String((handle && handle.address) || "").trim()
    if (!value) return ""
    if (value.slice(0, 2) === "0x" || value.slice(0, 2) === "0X") value = value.slice(2)
    return "0x" + value
  }

  function luaString(value) {
    return String(value == null ? "" : value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  }

  // Hyprland 0.56 moved dispatchers to Lua; Quickshell reports which syntax
  // the running compositor speaks.
  function hyprDispatch(lua, legacy) {
    Hyprland.dispatch(Hyprland.usingLua ? lua : legacy)
  }

  // Wheel over the Omarchy logo walks workspaces in order. "e+1"/"e-1" are
  // standard Hyprland workspace selectors (nearest existing, relative).
  function cycleWorkspace(dir) {
    var sel = dir > 0 ? "e+1" : "e-1"
    root.hyprDispatch('hl.dsp.focus({ workspace = "' + sel + '" })',
                      "workspace " + sel)
  }

  function workspaceTarget(workspace) {
    if (!workspace) return ""
    var name = String(workspace.name || "")
    return name !== "" ? name : String(workspace.id)
  }

  function liveToplevelForAddress(addr) {
    if (!addr) return null
    try {
      var tops = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
      for (var i = 0; i < tops.length; i++) {
        var top = tops[i]
        if (!top) continue
        var h = root.hyprToplevelFor(top)
        if (root.windowAddress(h) === addr) return top
      }
    } catch (e) {}
    return null
  }

  function liveHyprToplevelForAddress(addr) {
    if (!addr) return null
    try {
      var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
      for (var i = 0; i < tops.length; i++) {
        var h = tops[i]
        if (h && root.windowAddress(h) === addr) return h
      }
    } catch (e) {}
    return null
  }

  function focusWindowByAddress(addr, appId) {
    if (!addr) return
    root.clearUrgentApp(appId || "", addr)
    var handle = root.liveHyprToplevelForAddress(addr)
    var top = root.liveToplevelForAddress(addr)


    if (handle) {
      var workspace = handle.workspace
      if (workspace && workspace.name === root.minimizedWorkspace) {
        root.restoreWindow(addr, appId)
        return
      }
      if (top) DockModel.focusWindow(top)
      if (workspace && Hyprland.focusedWorkspace && workspace.id !== Hyprland.focusedWorkspace.id) {
        var targetWs = root.workspaceTarget(workspace)
        if (targetWs) {
          root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(targetWs) + '" })',
                            "workspace " + targetWs)
        }
      }
    } else if (top) {
      root.focusToplevel(top, appId)
    }
  }

  // Brings a window forward cleanly. Native Wayland activation hands over focus
  // and brings the window forward without warping the mouse pointer away from the dock
  // or desynchronizing layer-shell input state. Switches workspace when target is on another workspace.
  function focusToplevel(toplevel, appId) {
    if (!toplevel) return
    var handle = root.hyprToplevelFor(toplevel)
    var addr = root.windowAddress(handle)
    var aid = appId || (toplevel.appId ? DockModel.normalizeId(toplevel.appId) : "")
    root.clearUrgentApp(aid, addr)
    var workspace = handle ? handle.workspace : null

    if (workspace && workspace.name === root.minimizedWorkspace) {
      root.restoreWindow(handle, aid)
      return
    }

    DockModel.focusWindow(toplevel)

    if (workspace && Hyprland.focusedWorkspace && workspace.id !== Hyprland.focusedWorkspace.id) {
      var targetWs = root.workspaceTarget(workspace)
      if (targetWs) {
        root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(targetWs) + '" })',
                          "workspace " + targetWs)
      }
    }
  }

  function minimizeToplevel(topOrAddr) {
    var address = typeof topOrAddr === "string" ? topOrAddr : root.windowAddress(root.hyprToplevelFor(topOrAddr))
    if (!address) return false

    var handle = root.liveHyprToplevelForAddress(address)
    var origin = (handle && handle.workspace) ? root.workspaceTarget(handle.workspace) : root.workspaceTarget(Hyprland.focusedWorkspace)
    if (!origin || origin === root.minimizedWorkspace) origin = root.workspaceTarget(Hyprland.focusedWorkspace)
    if (origin === root.minimizedWorkspace) return false

    var origins = DockModel.copyMap(root.minimizedOrigins)
    origins[address] = origin
    root.minimizedOrigins = origins

    var parkedTimes = DockModel.copyMap(root.parkedAt)
    parkedTimes[address] = Date.now()
    root.parkedAt = parkedTimes


    root.hyprDispatch(
      'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
        + root.luaString(root.minimizedWorkspace) + '", follow = false })',
      "movetoworkspacesilent " + root.minimizedWorkspace + ",address:" + address)
    return true
  }

  function restoreWindow(targetRef, appId, useOrigin) {
    var address = typeof targetRef === "string" ? targetRef : root.windowAddress(targetRef)
    if (!address) return false


    // Default restore target is the workspace the user is on right now;
    // useOrigin=true sends the window back to where it was parked from.
    var target = ""
    if (useOrigin && root.minimizedOrigins[address]) target = root.minimizedOrigins[address]
    if (!target) target = root.workspaceTarget(Hyprland.focusedWorkspace)
    if (!target) return false

    var origins = DockModel.copyMap(root.minimizedOrigins)
    delete origins[address]
    root.minimizedOrigins = origins

    var parkedTimes = DockModel.copyMap(root.parkedAt)
    delete parkedTimes[address]
    root.parkedAt = parkedTimes

    // Silent move (follow = false): a dispatcher-driven window focus would
    // warp the mouse pointer into the restored window's center. The workspace
    // switch plus native Wayland activation below focus the window cleanly
    // and leave the cursor exactly where the user left it.
    root.hyprDispatch(
      'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
        + root.luaString(target) + '", follow = false })',
      "movetoworkspacesilent " + target + ",address:" + address)
    root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(target) + '" })',
                      "workspace " + target)

    var top = root.liveToplevelForAddress(address)
    if (top) {
      DockModel.focusWindow(top)
    }
    return true
  }

  // Restores a group of windows in one compositor transaction:
  // all moves are dispatched silently first, then workspace focus and window
  // activation happen exactly once. This prevents the "one-by-one fullscreen"
  // flash that occurs when restoreWindow() is called in a loop (each call
  // previously triggered its own focus switch and Wayland activation).
  //
  // primaryAddress: the window to focus after all moves. When null/undefined,
  // the most-recently-parked window (highest parkedAt timestamp) is chosen.
  //
  // useOrigin: when true, each window returns to the workspace it was parked
  // from (minimizedOrigins). Default restores everything onto the user's
  // currently active workspace.
  function restoreWindowBatch(wins, primaryAddress, useOrigin) {
    if (!wins || wins.length === 0) return

    // Single-copy the maps — O(n) instead of O(n²) individual copies.
    var origins = DockModel.copyMap(root.minimizedOrigins)
    var parkedTimes = DockModel.copyMap(root.parkedAt)

    var focusAddr = null
    var focusTarget = null
    var bestTime = -1

    for (var i = 0; i < wins.length; i++) {
      var w = wins[i]
      if (!w || !w.address) continue
      var address = w.address

      var target = ""
      if (useOrigin && origins[address]) target = origins[address]
      if (!target) target = root.workspaceTarget(Hyprland.focusedWorkspace)
      if (!target) continue

      var t = parkedTimes[address] !== undefined ? parkedTimes[address] : 0
      delete origins[address]
      delete parkedTimes[address]

      // Silent move only — no workspace switch or window focus per iteration.
      root.hyprDispatch(
        'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
          + root.luaString(target) + '", follow = false })',
        "movetoworkspacesilent " + target + ",address:" + address)

      // Track which window to focus: explicit override first, then most-recently-parked.
      if (primaryAddress && address === primaryAddress) {
        focusAddr = address
        focusTarget = target
        bestTime = Infinity
      } else if (bestTime !== Infinity && t >= bestTime) {
        bestTime = t
        focusAddr = address
        focusTarget = target
      }
    }

    // Commit map mutations once.
    root.minimizedOrigins = origins
    root.parkedAt = parkedTimes

    // Single workspace switch + single window activation after all moves.
    if (focusTarget) {
      root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(focusTarget) + '" })',
                        "workspace " + focusTarget)
      var top = root.liveToplevelForAddress(focusAddr)
      if (top) DockModel.focusWindow(top)
    }
  }

  // The workspace a window sits on right now. Model primitives freeze state at
  // rebuild time, and Quickshell's Hyprland handle can lag silent moves onto
  // the special workspace, so park/visibility decisions resolve live at click
  // time and fall back to the cached name only while no handle exists.
  function liveWsNameOf(win) {
    var cached = win ? String(win.workspaceName || "") : ""
    var h = (win && win.address) ? root.liveHyprToplevelForAddress(win.address) : null
    if (h && h.workspace) return String(h.workspace.name || h.workspace.id || "")
    if (win && win.address && root.minimizedOrigins && root.minimizedOrigins[win.address] !== undefined)
      return root.minimizedWorkspace
    return cached
  }

  function isWinParkedLive(win) {
    return root.liveWsNameOf(win) === root.minimizedWorkspace
  }

  // The window an app should act on: the one it was last focused in, as long as
  // it is still around and not parked.
  function windowByAddress(windows, address) {
    if (!address) return null
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      if (!win) continue
      if (win.address === address) {
        return !root.isWinParkedLive(win) ? win : null
      }
    }
    return null
  }

  // The app's windows that are still on screen, in window order.
  function visibleWindows(windows) {
    var out = []
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      if (!win) continue
      if (!root.isWinParkedLive(win)) out.push(win)
    }
    return out
  }

  // Which of these windows holds the focus, if any.
  function focusedIndex(windows) {
    if (!root.activeWindowAddress) return -1
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && windows[i].address && windows[i].address === root.activeWindowAddress) return i
    }
    return -1
  }

  // A window of this app on the workspace you are looking at.
  function windowHere(windows) {
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      var wsName = root.liveWsNameOf(win)
      if (win && (wsName === String(root.focusedWorkspaceId) || wsName === root.focusedWorkspaceName)) {
        return win
      }
    }
    return null
  }

  // One step around the app's windows from wherever the focus is.
  function stepWindow(windows, direction) {
    if (windows.length === 0) return null
    if (windows.length === 1) return windows[0]

    var step = direction < 0 ? -1 : 1
    var at = root.focusedIndex(windows)
    if (at < 0) return windows[step > 0 ? 0 : windows.length - 1]
    return windows[(at + step + windows.length) % windows.length]
  }

  // Handles of this app's parked windows, in window order. Nothing is
  // remembered for this: the workspace a window sits on is the answer, so a
  // shell restart cannot lose track of one.
  function parkedWindows(windows) {
    var out = []
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      if (win && root.isWinParkedLive(win)) out.push(win)
    }
    return out
  }

  // The app's parked window that has been waiting the longest — the head of
  // the chronological FIFO. Windows parked before this shell session have no
  // timestamp and sort first, matching the "recover the oldest" expectation.
  function oldestParked(parked) {
    if (!parked || parked.length <= 1) return (parked && parked[0]) || null
    var best = parked[0]
    var bestTime = (best && best.address && root.parkedAt[best.address] !== undefined) ? root.parkedAt[best.address] : 0
    for (var i = 1; i < parked.length; i++) {
      var p = parked[i]
      var t = (p && p.address && root.parkedAt[p.address] !== undefined) ? root.parkedAt[p.address] : 0
      if (t < bestTime) {
        best = p
        bestTime = t
      }
    }
    return best
  }

  function recentWindow(appId, windows) {
    return root.windowByAddress(windows, root.appRecentWindow[appId])
  }

  function minimizeAllWindows(entry) {
    var windows = entry ? (entry.windowList || []) : []
    var parked = false
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      if (!win || !win.address) continue
      if (!root.isWinParkedLive(win) && root.minimizeToplevel(win.address))
        parked = true
    }
    return parked
  }

  // The one window this app should put away: the focused one, else the one it
  // was last focused in, else the first that is still on screen.
  function minimizeOneWindow(entry) {
    var windows = entry ? (entry.windowList || []) : []
    var target = null

    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && windows[i].address && windows[i].address === root.activeWindowAddress) {
        target = windows[i]
        break
      }
    }
    if (!target) target = root.recentWindow(entry ? entry.appId : "", windows)
    if (!target) {
      for (var j = 0; j < windows.length; j++) {
        if (windows[j] && !root.isWinParkedLive(windows[j])) {
          target = windows[j]
          break
        }
      }
    }

    return (target && target.address) ? root.minimizeToplevel(target.address) : false
  }

  function minimizeApp(entry) {
    return root.minimizeMode === "all"
      ? root.minimizeAllWindows(entry)
      : root.minimizeOneWindow(entry)
  }

  // Everything the dock remembers about a window is keyed by address, so one
  // pass over the live windows is enough to drop what closed.
  function pruneWindowState() {
    var live = {}
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      var address = root.windowAddress(list[i])
      if (address) live[address] = true
    }

    root.minimizedOrigins = root.keepLive(root.minimizedOrigins, live, false)
    root.parkedAt = root.keepLive(root.parkedAt, live, false)
    root.appRecentWindow = root.keepLive(root.appRecentWindow, live, true)
    root.urgentMap = root.keepUrgentLive(root.urgentMap, live)

    // recentOpenedWindowAddrs entries carry their own expiry; drop the stale ones.
    var now = Date.now()
    var roa = root.recentOpenedWindowAddrs || {}
    var nextRoa = {}
    var roaChanged = false
    for (var rkey in roa) {
      if (roa[rkey] < now) roaChanged = true
      else nextRoa[rkey] = roa[rkey]
    }
    if (roaChanged) root.recentOpenedWindowAddrs = nextRoa
  }

  // urgentMap mixes two key shapes: "0x…" per-window addresses and bare appIds
  // set by the notification service. Address keys die with their window; appId
  // keys are not addresses and must survive the prune until the user clicks or focuses.
  function keepUrgentLive(map, live) {
    var keys = Object.keys(map)
    if (keys.length === 0) return map

    var next = {}
    var dropped = false
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (key.slice(0, 2) === "0x" && !live[key]) dropped = true
      else next[key] = map[key]
    }
    return dropped ? next : map
  }

  // Clears urgency entries from urgentMap for an application and its windows.
  // Called whenever an app/window receives focus or is activated/clicked by user.
  function clearUrgentApp(appId, address) {
    if (!root.urgentMap) return
    var hasKeys = false
    for (var k in root.urgentMap) {
      if (root.urgentMap[k]) { hasKeys = true; break }
    }
    if (!hasKeys) return

    var map = DockModel.copyMap(root.urgentMap)
    var changed = false

    var normAddr = ""
    if (address) {
      var rawAddr = String(address).trim()
      if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
      if (rawAddr) normAddr = "0x" + rawAddr
    }

    // Direct address deletion if present
    if (normAddr && map[normAddr]) {
      delete map[normAddr]
      changed = true
    }

    var allEntries = root.pinnedSection.concat(root.runningSection)
    var targetEntries = []

    // Find entries matching address or appId
    for (var i = 0; i < allEntries.length; i++) {
      var entry = allEntries[i]
      if (!entry) continue
      var entryId = entry.appId || entry.id
      var matched = false

      if (appId && (entryId === appId || DockModel.isAppMatch(entryId, appId))) {
        matched = true
      }

      if (!matched && normAddr && entry.windowList) {
        for (var w = 0; w < entry.windowList.length; w++) {
          var winAddr = entry.windowList[w] ? entry.windowList[w].address : ""
          if (winAddr && winAddr === normAddr) {
            matched = true
            break
          }
        }
      }

      if (matched) {
        targetEntries.push(entry)
      }
    }

    // Direct raw appId deletion
    if (appId) {
      var rawId = DockModel.stripDesktop(appId)
      var normId = DockModel.normalizeId(appId)
      if (map[appId]) { delete map[appId]; changed = true }
      if (rawId && map[rawId]) { delete map[rawId]; changed = true }
      if (normId && map[normId]) { delete map[normId]; changed = true }
    }

    // Delete keys for matched entries
    for (var t = 0; t < targetEntries.length; t++) {
      var tEntry = targetEntries[t]
      var tId = tEntry.appId || tEntry.id
      if (tId && map[tId]) { delete map[tId]; changed = true }
      if (tEntry.id && map[tEntry.id]) { delete map[tEntry.id]; changed = true }
      if (tEntry.appId && map[tEntry.appId]) { delete map[tEntry.appId]; changed = true }
      var tWins = tEntry.windowList || []
      for (var tw = 0; tw < tWins.length; tw++) {
        var twAddr = tWins[tw] ? tWins[tw].address : ""
        if (twAddr && map[twAddr]) {
          delete map[twAddr]
          changed = true
        }
      }
    }

    // Also check if any remaining key in map matches appId via DockModel.isAppMatch
    if (appId) {
      for (var mKey in map) {
        if (mKey.slice(0, 2) !== "0x" && DockModel.isAppMatch(mKey, appId)) {
          delete map[mKey]
          changed = true
        }
      }
    }

    if (changed) {
      root.urgentMap = map
      modelTimer.restart()
    }
  }

  // byValue: the map holds addresses as values (app -> window) rather than keys.
  function keepLive(map, live, byValue) {
    var keys = Object.keys(map)
    if (keys.length === 0) return map

    var next = {}
    var dropped = false
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (live[byValue ? map[key] : key]) next[key] = map[key]
      else dropped = true
    }
    return dropped ? next : map
  }

  // ------------------------------------------------- external keybind hooks
  // Hyprland plugins cannot register compositor binds directly, but these IPC
  // targets expose dock actions to `qs -p /usr/share/omarchy/shell ipc call omadock <fn>`
  // so users can bind them in ~/.config/hypr/bindings.lua, e.g.:
  //   o.bind("SUPER + M", "Minimize focused",
  //     "exec qs -p /usr/share/omarchy/shell ipc call omadock minimizeActive")
  IpcHandler {
    target: "omadock"

    function minimizeActive(): void {
      var addr = root.activeWindowAddress
      if (addr !== "") root.minimizeToplevel(addr)
    }

    function restoreLast(): void {
      var parked = []
      var all = root.pinnedSection.concat(root.runningSection)
      for (var i = 0; i < all.length; i++) {
        if (!all[i]) continue
        parked = parked.concat(root.parkedWindows(all[i].windowList || []))
      }
      if (parked.length > 0) root.restoreWindow(root.oldestParked(parked), "")
    }
  }

  // ------------------------------------------------- launch feedback

  function launchApp(appId, entry) {
    if (!root.shell || !root.shell.appLibrary) return
    var target = entry || root.entryForId(appId)
    var deskEntry = DockModel.entryFor(root.appRows, appId)
    if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries) {
      deskEntry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    }
    var targetId = (deskEntry && deskEntry.id) ? deskEntry.id : appId
    var targetName = (deskEntry && deskEntry.name) ? deskEntry.name : (target && target.name ? target.name : appId)
    if (deskEntry && deskEntry.id) {
      root.shell.appLibrary.launch(deskEntry.id, targetName)
    } else {
      var webAppMatch = String(appId).match(/^(?:chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(.*?)__?-(?:default|profile.*)$/i)
                     || String(appId).match(/^(?:chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(.*?)$/i)
      if (webAppMatch) {
        var webDomain = webAppMatch[1].replace(/^https?___?/i, "").replace(/__.*$/, "")
        Quickshell.execDetached(["omarchy-launch-webapp", "https://" + webDomain])
      } else {
        root.shell.appLibrary.launch(targetId, targetName)
      }
    }
    root.markLaunching(appId, target ? target.windows : 0)
  }

  function markLaunching(appId, windowsBefore) {
    var pending = DockModel.copyMap(root.launchPending)
    pending[appId] = { deadline: Date.now() + root.launchTimeout, windows: windowsBefore || 0 }
    root.launchPending = pending
    launchPruneTimer.start()
  }

  // A pending launch ends when the app gained a window, or when waiting stops
  // being informative.
  function pruneLaunching() {
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
    if (remaining === 0) launchPruneTimer.stop()
  }

  function saveConfig() {
    var conf = {}
    try {
      var txt = String(configFile.text() || "").trim()
      if (txt) conf = JSON.parse(txt) || {}
    } catch (e) {
      conf = {}
    }
    conf.autohide = root.autohide
    conf.intelligentAutohide = root.intelligentAutohide
    conf.showAppsButton = root.showAppsButton
    conf.showTooltips = root.showTooltips
    conf.showMinimizedTiles = root.showMinimizedTiles
    conf.hoverEffect = root.hoverEffect
    delete conf.magnification
    conf.launchBounce = root.launchBounce
    conf.advancedTooltips = root.advancedTooltips
    if (root.screenName) conf.screen = root.screenName
    if (root.configuredIconSize > 0) conf.iconSize = root.configuredIconSize
    else delete conf.iconSize
    conf.opacity = root.dockOpacity < 0 ? "theme" : root.dockOpacity
    conf.shape = root.dockShape
    conf.bgColor = root.dockBgColor
    conf.folderColor = root.folderColor
    conf.itemSpacing = root.itemSpacing
    conf.minimizeMode = root.minimizeMode
    conf.clickToMinimize = root.minimizeMode !== "off"
    conf.showUrgentHint = root.showUrgentHint
    conf.urgentOnNotification = root.urgentOnNotification
    conf.urgentSound = root.urgentSound
    conf.urgentSoundName = root.urgentSoundName
    conf.revealDelay = root.revealDelay
    conf.tooltipDelay = root.tooltipDelay
    conf.pinnedFolders = root.pinnedFolders
    configFile.setText(JSON.stringify(conf, null, 2))
  }

  // ------------------------------------------------- what a click means
  //
  // A left click says "give me this app". Everything below is decided from live
  // state only — which windows exist, which are parked, whether the focus is
  // already inside the app — so there is nothing to remember and nothing to go
  // stale:
  //
  //   no windows                      launch it
  //   focus elsewhere, something parked   bring the parked one back
  //   focus elsewhere                  focus it, preferring this workspace
  //   focus inside, mode "all"         park the whole app
  //   focus inside, several open       step to the app's next window
  //   focus inside, one open           park it, when parking is on
  //
  // Two of those rules carry the weight. Preferring a window on the current
  // workspace keeps a click from teleporting you while the app is already in
  // front of you. Stepping through windows is what makes every click on a
  // multi-window app do something visible: parking one of several hands focus
  // straight to a sibling, so the app never stops being active, and both a
  // park-first and a restore-first rule end up stuck — one parks forever, the
  // other toggles one window forever. Stepping has no such corner, and a
  // specific window can still be parked from the context menu.
  function activate(appId) {
    if (!root.shell || !root.shell.appLibrary) return

    var entry = root.entryForId(appId)
    var windows = entry ? (entry.windowList || []) : []
    if (!entry || !entry.running || windows.length === 0) {
      root.launchApp(appId, entry)
      return
    }

    var visible = root.visibleWindows(windows)
    var parked = root.parkedWindows(windows)
    var focusedIdx = root.focusedIndex(visible)


    // Check if this application has any urgent windows or is currently bouncing
    var hadUrgency = false
    var urgentWin = null
    for (var u = 0; u < visible.length; u++) {
      var ua = visible[u] ? visible[u].address : ""
      if (ua && root.urgentMap[ua]) {
        urgentWin = visible[u]
        hadUrgency = true
        break
      }
    }

    var urgentParked = null
    for (var p = 0; p < parked.length; p++) {
      var pa = parked[p] ? parked[p].address : ""
      if (pa && root.urgentMap[pa]) {
        urgentParked = parked[p]
        hadUrgency = true
        break
      }
    }

    // Clear urgency map entries for this application immediately on click
    if (root.urgentMap[appId]) hadUrgency = true
    root.clearUrgentApp(appId, "")

    // If an urgent window is parked/minimized: restore it directly to its origin workspace
    if (urgentParked) {
      root.restoreWindow(urgentParked.address || urgentParked, appId, true)
      return
    }

    // If this app was urgent and not yet focused on screen, focus or restore directly without minimizing
    if (hadUrgency && focusedIdx < 0) {
      if (urgentWin && urgentWin.address) {
        root.focusWindowByAddress(urgentWin.address, appId)
        return
      }
      if (parked.length > 0) {
        root.restoreWindow(root.oldestParked(parked), appId, true)
        return
      }
      var target = root.windowHere(visible) || root.recentWindow(appId, visible) || visible[0]
      if (target && target.address) root.focusWindowByAddress(target.address, appId)
      return
    }


    // 1. If an active window of this application is currently focused
    if (focusedIdx >= 0) {
      if (hadUrgency) {
        // Attention Priority Rule: Clicking an urgent app acknowledges attention and keeps the app in front without minimizing.
        return
      }

      if (root.minimizeMode === "all") {
        root.minimizeAllWindows(entry)
        return
      }
      if (root.minimizeMode === "active") {
        if (visible[focusedIdx] && visible[focusedIdx].address) {
          root.minimizeToplevel(visible[focusedIdx].address)
        } else {
          root.minimizeOneWindow(entry)
        }
        return
      }
      // If minimize is disabled ("off"), cycle through visible windows
      if (visible.length > 1) {
        var next = root.stepWindow(visible, 1)
        if (next && next.address) root.focusWindowByAddress(next.address, appId)
        return
      }
      return
    }

    // 2. Nothing focused: bring a visible window of this app forward
    // (preferring current workspace, then recent, then first).
    if (visible.length > 0) {
      var target = root.windowHere(visible) || root.recentWindow(appId, visible) || visible[0]
      if (target && target.address) root.focusWindowByAddress(target.address, appId)
    } else if (parked.length > 0 && !root.showMinimizedTiles) {
      // When minimized preview tiles are disabled, clicking the app icon restores the window.
      root.restoreWindow(root.oldestParked(parked), appId)
    }
  }

  // Menu rows name the workspace a window sits on, including the parked ones.
  function windowRowLabel(window) {
    var title = String((window && window.title) || "Window")
    var wsName = root.liveWsNameOf(window)
    var isMin = wsName === root.minimizedWorkspace
    var label = isMin ? "minimized" : (wsName !== "" ? wsName : "")
    return label !== "" ? "[" + label + "] " + title : title
  }

  function entryForId(appId) {
    var i
    for (i = 0; i < root.pinnedSection.length; i++) {
      if (root.pinnedSection[i].appId === appId || DockModel.isAppMatch(root.pinnedSection[i].appId, appId))
        return root.pinnedSection[i]
    }
    for (i = 0; i < root.runningSection.length; i++) {
      if (root.runningSection[i].appId === appId || DockModel.isAppMatch(root.runningSection[i].appId, appId))
        return root.runningSection[i]
    }
    return null
  }

  function setPinned(next) {
    root.pinnedIds = next
    dockFile.setText(DockModel.serializePinned(next))
  }

  function togglePin(appId) {
    root.setPinned(DockModel.togglePinned(root.pinnedIds, appId))
  }

  function launchDesktopAction(action, appName) {
    if (!action) return
    root.markLaunching(root.contextAppId || "", 0)
    try {
      if (typeof action.execute === "function") {
        action.execute()
        return
      }
    } catch (e) {}

    try {
      if (action.command && action.command.length > 0) {
        Quickshell.execDetached(action.command)
      }
    } catch (e2) {}
  }

  function isWindowFocused(win) {
    if (!win || !win.address || !root.activeWindowAddress) return false
    return win.address === root.activeWindowAddress
  }

  function isWindowParked(win) {
    if (!win) return false
    return root.isWinParkedLive(win)
  }

  function syncContextWindows() {
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
    try {
      if (root.appContextMenuColumnRef && root.appContextMenuColumnRef.selectedWindowIdx >= wins.length) {
        root.appContextMenuColumnRef.selectedWindowIdx = -1
      }
    } catch (e) {}
  }

  function openContext(appId, x, y) {
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
    try { if (root.appContextMenuColumnRef) root.appContextMenuColumnRef.selectedWindowIdx = -1 } catch (e) {}
    root.contextX = x
    root.contextY = y
  }

  function closeContext() {
    root.contextAppId = ""
  }

  // ------------------------------------------------- minimized tile context
  property var contextTileWins: []
  property string contextTileAppId: ""
  property string contextTileName: ""
  property bool contextTilePinned: false

  function openTileContext(wins, appId, cx) {
    root.contextTileWins = wins || []
    root.contextTileAppId = appId || ""
    // Resolve display name from desktop entries
    var deskEntry = DockModel.entryFor(root.appRows, appId)
    if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries)
      deskEntry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    root.contextTileName = (deskEntry && deskEntry.name) ? deskEntry.name : appId
    var canonicalId = (deskEntry && deskEntry.id) ? deskEntry.id : appId
    root.contextTilePinned = DockModel.isPinned(root.pinnedIds, appId)
      || (canonicalId !== appId && DockModel.isPinned(root.pinnedIds, canonicalId))
    root.contextX = cx
    root.contextY = 0
    root.contextAppId = "__tile_context__"
    root.syncVisibility()
  }

  function restoreContextTile() {
    root.restoreWindowBatch(root.contextTileWins || [])
  }

  function restoreContextTileOriginal() {
    root.restoreWindowBatch(root.contextTileWins || [], null, true)
  }

  function closeContextTile() {
    var wins = root.contextTileWins
    for (var i = 0; i < wins.length; i++) {
      var w = wins[i]
      if (w && w.address) root.hyprDispatch(
        'hl.dsp.window.close({ window = "address:' + w.address + '" })',
        "closewindow address:" + w.address)
    }
  }

  function openFolderStack(path, name, cx) {
    if (root.activeStackFolder === path) {
      root.closeFolderStack()
      return
    }
    root.closeContext()
    // Kill any in-flight scan first: assigning running = true while a process
    // is already running is a no-op in Quickshell, which used to let a slow
    // older scan race the new one.
    if (folderStackScanner.running) folderStackScanner.running = false
    root.activeStackFolder = path
    root.activeStackName = name || "Folder"
    root.activeStackX = cx
    root.activeStackEntries = []
    folderStackScanner.targetFolder = (path || "").replace(/^~/, Quickshell.env("HOME"))
    folderStackScanner.running = true
    root.syncVisibility()
  }

  function closeFolderStack() {
    if (folderStackScanner.running) folderStackScanner.running = false
    root.activeStackFolder = ""
    root.activeStackName = ""
    root.activeStackEntries = []
    root.syncVisibility()
  }

  function openFolderContext(path, name, cx, cy) {
    root.closeFolderStack()
    root.contextFolderPath = path
    root.contextFolderName = name || "Folder"
    root.contextX = cx
    root.contextY = cy
    root.contextAppId = "__folder_context__"
    root.syncVisibility()
  }

  function isFolderPinned(path) {
    var norm = (path || "").replace(/^~/, Quickshell.env("HOME"))
    var list = root.pinnedFolders || []
    for (var i = 0; i < list.length; i++) {
      var p = (list[i].path || "").replace(/^~/, Quickshell.env("HOME"))
      if (p === norm) return true
    }
    return false
  }

  function toggleFolderPin(path, name, icon) {
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
      next.push({ path: path, name: name || "Folder", icon: icon || DockModel.folderIconFor(path, "") })
    }
    root.pinnedFolders = next
    root.saveConfig()
  }

  // Widest piece of content in the open menu. Only implicit widths are read, so
  // feeding the result back into every row cannot loop.
  function menuContentWidth(item) {
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

  // ------------------------------------------------- panel window

  PanelWindow {
    id: dockWindow

    screen: root.dockScreen
    color: "transparent"
    WlrLayershell.namespace: "omadock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: (!root.autohide) ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: (!root.autohide) ? Math.round(dockCard.height + Style.gapsOut * 2) : 0
    anchors {
      bottom: true
      left: true
      right: true
    }
    implicitHeight: 650

    mask: Region {
      item: dockCardComp.dockCard
      regions: [
        Region { item: contextMenuComp },
        Region { item: folderStackPopoverComp },
        Region { item: revealStrip },
        Region { item: globalDismiss }
      ]
    }

    // Bottom edge reveal strip — thin edge trigger with zero click-swallowing
    Item {
      id: revealStrip
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: root.revealHeight

      HoverHandler {
        id: revealHover
        onHoveredChanged: root.syncVisibility()
      }

      Rectangle {
        id: revealPill
        visible: root.autohide && !root.dockVisible
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(1)
        anchors.horizontalCenter: parent.horizontalCenter
        width: revealHover.hovered ? Style.space(64) : Style.space(28)
        height: Style.space(3.5)
        radius: height / 2
        color: revealHover.hovered ? Color.bar.active : Util.alpha(Color.bar.text, 0.60)
        border.color: Qt.rgba(0, 0, 0, 0.40)
        border.width: 1

        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 180 } }
      }
    }

    // Global dismiss area - catches clicks outside context menu or folder stack
    Item {
      id: globalDismiss
      width: (root.contextAppId !== "" || root.activeStackFolder !== "" || root.dragAppId !== "") ? dockWindow.width : 0
      height: (root.contextAppId !== "" || root.activeStackFolder !== "" || root.dragAppId !== "") ? dockWindow.height : 0
      MouseArea {
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        // Accept every button: the layer-shell mask routes all clicks here
        // while a menu is open, so a right-click on empty space must dismiss
        // the menu too instead of being swallowed with no effect.
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: function(mouse) {
          if (root.contextAppId !== "") {
            root.closeContext()
          }
          if (root.activeStackFolder !== "") {
            root.closeFolderStack()
          }
        }
        onReleased: function(mouse) {
          if (root.dragAppId !== "") {
            root.dragAppId = ""
            root.dropBeforeId = ""
            root.syncVisibility()
          }
        }
      }
    }

    // ------------------------------------------------------------ dock container
    DockCard {
      id: dockCardComp
      rootRef: root
    }

    // ------------------------------------------------------------ Folder Stack Popover
    FolderPopup {
      id: folderStackPopoverComp
      rootRef: root
    }

    // ------------------------------------------------------------ context menu
    DockContextMenu {
      id: contextMenuComp
      rootRef: root
    }
  }
}
