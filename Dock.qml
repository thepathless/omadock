import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
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
  readonly property alias hitboxHover: dockCardComp.hitboxHover
  readonly property alias minimizedTilesRepeater: dockCardComp.minimizedTilesRepeater
  readonly property alias foldersRepeater: dockCardComp.foldersRepeater
  readonly property var contextMenu: contextMenuLoader.item ? contextMenuLoader.item.body : null
  readonly property var folderStackPopover: folderStackLoader.item ? folderStackLoader.item.body : null
  readonly property alias contentItemRef: dockWindow.contentItem
  readonly property alias dockWindowRef: dockWindow
  readonly property var appContextMenuColumnRef: root.contextMenu ? root.contextMenu.appContextMenuColumn : null
  readonly property alias customFolderPickerProc: customFolderPickerProc
  readonly property alias folderStackScanner: folderStackScanner

  readonly property var dockRoot: root

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  readonly property string dockPath: Quickshell.env("HOME") + "/.config/omarchy/dock.json"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/omadock.json"
  property bool _savingConfig: false

  property string screenName: ""
  // Real, connected outputs only: Qt keeps placeholder screens (empty name)
  // alive while every output is gone and Quickshell marks destroyed outputs
  // dangling ("{ NULL SCREEN }"). Hosting the dock window on either one
  // breaks revival, so the fallback picks the first genuine screen instead
  // of blindly trusting screens[0]. Also feeds the settings panel's monitor
  // picker.
  readonly property var realScreens: {
    var list = Quickshell.screens || []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var cand = list[i]
      if (cand && cand.name && cand.name !== "{ NULL SCREEN }") out.push(cand)
    }
    return out
  }

  function pickScreen() {
    var name = root.forcedScreenName || root.screenName
    var s = name ? root.screenForName(name) : null
    if (s) return s
    return root.realScreens.length > 0 ? root.realScreens[0] : null
  }

  readonly property var dockScreen: root.pickScreen()

  // The output's own scale (Hyprland's monitor scale, e.g. 1.5). Qt renders
  // fractional scales at the next whole ratio (2) and the compositor scales
  // the buffer down, so pixel-exact drawing has to target this grid, not
  // Screen.devicePixelRatio. HyprlandMonitor.scale reads 0 until the monitor
  // list has been fetched, hence the refresh (Component.onCompleted) and the
  // fallback.
  readonly property real outputScale: {
    var m = root.dockScreen ? Hyprland.monitorFor(root.dockScreen) : null
    return (m && m.scale > 0) ? m.scale : 1
  }

  // ------------------------------------------------- multi-monitor
  // Set by DockHost when one dock runs per monitor. forcedScreenName pins this
  // instance to its monitor regardless of the "screen" config key; isPrimary
  // marks the one dock that owns global side effects (alert sounds);
  // sharedState carries parked-window bookkeeping across all docks so a tile
  // lands on the monitor its window was minimized from, whichever dock did it.
  property string forcedScreenName: ""
  property bool isPrimary: true
  property bool ipcEnabled: true
  property QtObject sharedState: null
  property bool multiMonitor: false
  property bool perMonitorApps: true
  readonly property bool filterByMonitor: root.perMonitorApps && root.forcedScreenName !== ""

  function monitorNameForWorkspace(target) {
    if (!target || !Hyprland.workspaces) return ""
    var list = Hyprland.workspaces.values || []
    for (var i = 0; i < list.length; i++) {
      var ws = list[i]
      if (!ws) continue
      if (String(ws.name || "") === target || String(ws.id) === target)
        return (ws.monitor && ws.monitor.name) ? String(ws.monitor.name) : ""
    }
    return ""
  }

  // The monitor a window belongs to. A parked window sits on the shared
  // special workspace, so it belongs to the monitor it was minimized from.
  function monitorNameForHypr(h) {
    if (!h) return ""
    var addr = root.windowAddress(h)
    var origin = (addr && root.minimizedOrigins) ? root.minimizedOrigins[addr] : undefined
    if (origin !== undefined) {
      var fromOrigin = root.monitorNameForWorkspace(String(origin))
      if (fromOrigin) return fromOrigin
    }
    // The workspace's monitor tracks moveworkspace events; the window's own
    // monitor is only a fallback.
    var mon = (h.workspace && h.workspace.monitor) ? h.workspace.monitor : h.monitor
    return (mon && mon.name) ? String(mon.name) : ""
  }

  // Unresolved handles count as local: a window may show on every dock for a
  // beat while Hyprland catches up, but it never vanishes from all of them.
  function isHyprOnThisMonitor(h) {
    if (!root.filterByMonitor) return true
    var name = root.monitorNameForHypr(h)
    return name === "" || name === root.forcedScreenName
  }

  function isToplevelOnThisMonitor(top) {
    if (!root.filterByMonitor) return true
    var h = root.hyprToplevelFor(top)
    return h ? root.isHyprOnThisMonitor(h) : true
  }

  onFilterByMonitorChanged: modelTimer.restart()

  property bool _syncingShared: false
  onMinimizedOriginsChanged: root.pushSharedState()
  onParkedAtChanged: root.pushSharedState()
  onSharedStateChanged: root.pullSharedState()

  function pushSharedState() {
    if (!root.sharedState || root._syncingShared) return
    root._syncingShared = true
    root.sharedState.minimizedOrigins = root.minimizedOrigins
    root.sharedState.parkedAt = root.parkedAt
    root._syncingShared = false
  }

  function pullSharedState() {
    if (!root.sharedState || root._syncingShared) return
    root._syncingShared = true
    root.minimizedOrigins = root.sharedState.minimizedOrigins || ({})
    root.parkedAt = root.sharedState.parkedAt || ({})
    root._syncingShared = false
    modelTimer.restart()
  }

  Connections {
    target: root.sharedState
    function onMinimizedOriginsChanged() { root.pullSharedState() }
    function onParkedAtChanged() { root.pullSharedState() }
  }

  function screenForName(name) {
    var list = root.realScreens
    for (var i = 0; i < list.length; i++)
      if (list[i].name === name) return list[i]
    return null
  }

  readonly property var appLibrary: (shell && shell.appLibrary) ? shell.appLibrary : localAppLibrary

  // Fallback standalone application library for host capability gates (e.g. Omarchy 4.x scoped plugins)
  QtObject {
    id: localAppLibrary

    signal appsChanged()

    // Absolute-path icon index, mirroring the host AppLibrary. Qt's themed
    // lookup resolves against the *configured* icon theme, so a theme that is
    // named but not installed (e.g. Omarchy's vantablack -> "Yaru-gray", which
    // yaru-icon-theme no longer ships) makes Quickshell.iconPath() return ""
    // for every name and the dock renders blank slots. The host's own menu
    // survives that because it consults this index first; the fallback library
    // has to do the same or it is strictly more fragile than the host.
    property var iconIndex: ({})

    function sortedEntries(query) {
      try {
        var values = DesktopEntries.applications.values
        if (!values) return []
        return values.filter(function(e) { return !e.noDisplay })
      } catch (e) {
        console.warn("[omadock] Failed reading desktop entries:", e)
        return []
      }
    }

    function entryName(entry) {
      if (!entry) return ""
      var target = (entry && entry.entry) ? entry.entry : entry
      var n = String(target.name || "")
      return n !== "" ? n : String(target.id || "")
    }

    function iconSource(icon) {
      var value = String(icon || "")
      if (value === "") return localAppLibrary.fallbackIcon()
      if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
      if (value.charAt(0) === "/") return Util.fileUrl(value)
      // Reading iconIndex registers the dependency, so swapping the property
      // after a scan re-evaluates every binding that called through here.
      var found = localAppLibrary.iconIndex[value]
      if (found) return Util.fileUrl(found)
      var themed = ""
      try {
        themed = Quickshell.iconPath(value, true)
      } catch (e) {
        console.warn("[omadock] Failed resolving themed icon path:", value, e)
      }
      if (themed && themed.length > 0) return themed
      return localAppLibrary.fallbackIcon()
    }

    // Generic placeholder, resolved through the same index so it survives a
    // broken theme too. Returns "" only if nothing at all is on disk, which
    // callers already treat as "draw nothing".
    function fallbackIcon() {
      var found = localAppLibrary.iconIndex["application-x-executable"]
      if (found) return Util.fileUrl(found)
      var themed = ""
      try {
        themed = Quickshell.iconPath("application-x-executable", true)
      } catch (e) {
        console.warn("[omadock] Failed resolving fallback icon path:", e)
      }
      return themed || ""
    }

    function refreshIcons() {
      if (!iconIndexScan.running) iconIndexScan.running = true
    }

    // SVGs before PNGs so the first hit per name is the scalable one; awk
    // keeps only that first hit, so QML parses ~2 300 lines instead of ~23 600.
    function iconIndexScanCommand() {
      return [
        'dirs="$HOME/.icons $HOME/.local/share/icons";',
        'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
        '{ for ext in svg png; do',
        '  for base in $dirs; do',
        '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" -o -path "*/places/*" -o -path "*/mimetypes/*" \\) -name "*.$ext" 2>/dev/null;',
        '  done;',
        '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
        'done; } | awk -F/ \'{ n = $NF; sub(/\\.[^.]*$/, "", n); if (!(n in seen)) { seen[n] = 1; print } }\''
      ].join(' ')
    }

    function launch(desktopId, name) {
      var id = String(desktopId || "")
      if (id === "") return
      // Always append .desktop — DesktopEntry.id strips the extension, so
      // ids like org.telegram.desktop need it re-added to resolve correctly.
      // Redirect stdout and stderr to /dev/null so spawned applications don't inherit
      // transient QProcess pipes that close when gtk-launch exits (causing EPIPE crashes).
      var args = ["bash", "-c", "exec uwsm-app -- gtk-launch -- \"$1\" >/dev/null 2>&1", "_", id + ".desktop"]
      var desktop = DockModel.entryFor(root.appRows, id)
      // GTK's generic terminal launch loses the CLI app-id, so a known CLI
      // product would come back wearing its terminal's identity. Route only
      // those two through Omarchy's TUI wrapper with the already parsed argv;
      // every other terminal entry keeps its normal launch path.
      if (desktop && DockModel.isKnownCli(id) && desktop.runInTerminal && desktop.command && desktop.command.length > 0) {
        var tuiCommand = ["omarchy-launch-tui", "--app-id=org.omarchy." + id].concat(DockModel.toArray(desktop.command))
        args = ["bash", "-c", 'cd -- "$1" || exit; shift; exec "$@" >/dev/null 2>&1',
                "_", desktop.workingDirectory || Quickshell.env("HOME")].concat(tuiCommand)
      }
      // gtk-launch exits non-zero up front when the desktop file no longer
      // resolves (stale pin, uninstalled app), but execDetached cannot
      // observe exit codes. Launches run through launchProc so failures
      // surface a notification instead of bouncing silently. The overlap
      // fallback keeps rare concurrent clicks fire-and-forget; the probe
      // itself exits within milliseconds.
      if (launchProc.running) {
        Quickshell.execDetached(args)
        return
      }
      launchProc.pendingName = String(name || id)
      launchProc.command = args
      launchProc.running = true
    }
  }

  // One-shot scans only: started on load, on app-list changes and on theme
  // changes. Nothing polls, so the dock stays at 0% CPU when idle.
  Process {
    id: iconIndexScan
    command: ["bash", "-c", localAppLibrary.iconIndexScanCommand()]
    // One collected read, parsed once: a callback per line cost ~23 600
    // GUI-thread calls on every start and theme change.
    stdout: StdioCollector { id: iconIndexOut; waitForEnd: true }
    onExited: {
      localAppLibrary.iconIndex = DockModel.parseIconIndex(iconIndexOut.text)
      localAppLibrary.appsChanged()
    }
  }

  // Launch wrapper: one-shot, event-driven (a failed gtk-launch probe exits
  // in milliseconds), so this adds zero idle CPU. A non-zero exit means the
  // desktop file no longer resolves and the user gets told about it.
  Process {
    id: launchProc
    property string pendingName: ""
    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0 && launchProc.pendingName !== "")
        root.notifyAppMissing(launchProc.pendingName, "It cannot be launched — reinstall the app or unpin it from the dock.")
      launchProc.pendingName = ""
    }
  }

  // Coalesces bursts of app-list changes (one package install touches many
  // entries) into a single rescan.
  Timer {
    id: iconIndexDebounce
    interval: 750
    onTriggered: if (!iconIndexScan.running) iconIndexScan.running = true
  }

  Connections {
    target: (root.appLibrary === localAppLibrary && typeof DesktopEntries !== "undefined") ? DesktopEntries : null
    function onApplicationsChanged() {
      iconIndexDebounce.restart()
      localAppLibrary.appsChanged()
    }
  }

  // Build the index once at load, but only when the host withheld its own
  // library — with a host library present the index would be dead weight.
  Component.onCompleted: {
    // Apply the config now: a missing omadock.json never fires onLoaded (the
    // capped gate rejects it), so without this the loadConfig defaults (pinned
    // Downloads folder, documented hover effect, blur-rule reconcile) never
    // ran on a fresh install. Real values re-apply unchanged once the async
    // gate lands them.
    root.loadConfig()
    if (root.appLibrary === localAppLibrary) iconIndexScan.running = true
    // Fills HyprlandMonitor.scale for outputScale.
    Hyprland.refreshMonitors()
  }

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
  // Largest size an icon reaches under either hover effect; icons decode at
  // this size once instead of on every animation frame.
  readonly property real maxIconArt: Math.ceil(root.baseIconArt * Math.max(root.zoomPeak, root.magnifyPeak))

  // Shared slot geometry. Every item (apps, groups, folders, drives, the
  // Omarchy button) draws its artwork in the same baseIconArt box, centred in
  // the part of the slot above a fixed indicator band. The box never moves with
  // running state, so icons stay level whether or not they carry dots.
  readonly property real indicatorBand: Style.space(6)
  // Distance from the slot's bottom edge to the bottom of the artwork.
  readonly property real iconArtBottom: Math.round(root.indicatorBand + (root.iconSlot - root.indicatorBand - root.baseIconArt) / 2)
  // Vertical offset of the artwork's centre from the slot's centre, for
  // things centred on the row (separators, preview tiles).
  readonly property real iconCenterOffset: -root.indicatorBand / 2

  // The card's own handler in dockCard-local coordinates.
  readonly property real pointerX: cardHover.hovered
    ? cardHover.point.position.x
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
  // Split sections turn each separator into the gap between two panels. Each
  // panel reaches the card padding past its outer icons, so the separator
  // slot is sized to leave the chosen visible gap between the panels.
  readonly property real sectionGap: Style.space(root.sectionSpacing)
  // Without the split, a divider's slot gets half the margin an icon has
  // inside its own slot on each side. Squeezed against its neighbours, the
  // line made every difference in icon width show; with the full margin it
  // stood too far apart. Half sits between the two.
  readonly property real separatorWidth: root.splitSections
    ? Math.max(Style.space(1), root.sectionGap + 2 * root.baseRowLeft - 2 * root.gapWidth)
    : Style.space(1) + Math.round((root.iconSlot - root.baseIconArt) / 2)
  readonly property int groupSlots: (root.appGroups && DockModel.isList(root.appGroups)) ? root.appGroups.length : 0
  readonly property int folderSlots: root.pinnedFolders ? root.pinnedFolders.length : 0
  readonly property int driveSlots: (root.showRemovableDrives && root.mountedDrives) ? root.mountedDrives.length : 0
  readonly property bool hasFolderSeparator: (root.folderSlots > 0 || root.driveSlots > 0) && (root.pinnedSection.length > 0 || root.groupSlots > 0 || root.hasTiles || root.visibleRunningCount > 0)
  // Folders | drives divider: drives come and go with the hardware, so they
  // get a section of their own instead of trailing the pinned folders.
  readonly property bool hasDriveSeparator: root.folderSlots > 0 && root.driveSlots > 0

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
  // Left tile divider (pinned|tiles) renders only when pins or groups precede the tiles.
  readonly property bool hasLeftTileSeparator: root.hasTiles && (root.pinnedSection.length > 0 || root.groupSlots > 0)

  // Width arithmetic total: hidden (fully-tiled) entries occupy zero width,
  // so the row-width and gap math must count only visible icons.
  readonly property int visibleSlotTotal: root.appsSlots + root.pinnedSection.length + root.groupSlots + root.visibleRunningCount + root.folderSlots + root.driveSlots
  readonly property int elementTotal: root.visibleSlotTotal
    + (root.hasSeparator ? 1 : 0)
    + (root.hasFolderSeparator ? 1 : 0)
    + (root.hasDriveSeparator ? 1 : 0)
    + (root.hasLeftTileSeparator ? 1 : 0)
    + (root.hasTiles ? root.tileCount : 0)

  readonly property real baseRowWidth: root.visibleSlotTotal * root.iconSlot
    + (root.hasSeparator ? root.separatorWidth : 0)
    + (root.hasFolderSeparator ? root.separatorWidth : 0)
    + (root.hasDriveSeparator ? root.separatorWidth : 0)
    + (root.hasLeftTileSeparator ? root.separatorWidth : 0)
    + (root.hasTiles ? root.tileCount * root.tileWidth : 0)
    + Math.max(0, root.elementTotal - 1) * root.gapWidth

  // Where the row starts within the card (card-local coordinates).
  readonly property real baseRowLeft: dockCard ? dockCard.contentLeftInset : Style.space(5)

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

  // Layout slot expansion handles spacing naturally; manual translation nudges are deprecated.
  function waveOffsetAt(homeCenter) {
    return 0
  }

  // ------------------------------------------------- contrast

  // The bar foreground is tuned for the bar's own background. A custom dock
  // colour can land on the same side of the scale — a light theme's dark text
  // on a dark card, or the reverse — so flip only when the two collide.
  function isLight(value) {
    return (0.2126 * value.r + 0.7152 * value.g + 0.0722 * value.b) > 0.5
  }

  // Corner radius for the dock card. An automatic "rounded" tracks the card's
  // own height, so the panel keeps the same visual softness at any icon size.
  readonly property real cardRadiusHeight: dockCard.height > 0 ? dockCard.height : (root.iconSlot + Style.space(10))
  readonly property int autoRoundedRadius: Math.max(Style.space(14), Math.min(Style.space(28), Math.round(root.cardRadiusHeight * 0.26)))
  // A hand-set "rounded" radius stays a few pixels short of a pill, which is
  // a shape of its own.
  readonly property int maxRoundedRadius: Math.max(2, Math.floor(root.cardRadiusHeight / 2) - 4)
  readonly property int roundedRadius: root.cornerRadius >= 0
    ? Math.max(2, Math.min(root.maxRoundedRadius, root.cornerRadius))
    : root.autoRoundedRadius
  readonly property int effectiveCardRadius: {
    var h = root.cardRadiusHeight
    if (root.dockShape === "round" || root.dockShape === "pill") return Math.round(h / 2)
    if (root.dockShape === "square") return 0
    if (root.dockShape === "theme" || root.dockShape === "auto") {
      var n = Style.cornerRadius
      return (typeof n === "number" && isFinite(n) && n >= 0) ? n : Math.max(14, Style.space(14))
    }
    return root.roundedRadius
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
      console.warn("[omadock] Invalid dock background colour, using theme:", custom, e)
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
  property var terminalHosts: ({})
  property var terminalApps: ({})
  property var dockModel: ({ pinned: [], running: [] })
  // Height a popup may use above the card: the screen above the dock, less
  // the margin the full-screen layer used to leave (Style.space(36)).
  // Tooltips currently alive (shown or fading out); see TooltipLife.
  property int tooltipsAlive: 0
  readonly property real popupMaxHeight: Math.max(240,
    (root.dockScreen ? root.dockScreen.height : 1080) - Style.space(36)
    - Style.gapsOut - (dockCardComp ? dockCardComp.dockCard.height : 0) - Style.space(16))
  // Live scan of parked windows for the preview-tile section. Built straight
  // off Hyprland's own toplevel list, so it cannot go stale the way cached
  // model primitives can.
  property var minimizedWindows: []
  property string _minimizedSig: ""
  readonly property var pinnedSection: root.dockModel.pinned || []
  // Pinned apps and app groups in dock order (DockModel.pinnedRow).
  readonly property var pinnedRow: DockModel.pinnedRow(root.pinnedSection, root.appGroups)

  // Keys and lookups for the keyed Repeater models (KeyedListModel), which
  // keep the delegates of items that stay when these lists are replaced.
  function pinnedRowKey(item) {
    return item.kind === "group" ? "group:" + item.id : "app:" + item.appId
  }
  readonly property var pinnedRowKeys: root.pinnedRow.map(root.pinnedRowKey)
  readonly property var pinnedRowByKey: {
    var map = {}
    for (var i = 0; i < root.pinnedRow.length; i++) map[root.pinnedRowKey(root.pinnedRow[i])] = root.pinnedRow[i]
    return map
  }
  readonly property var runningKeys: root.runningSection.map(function(e) { return e.appId })
  readonly property var runningByKey: {
    var map = {}
    for (var i = 0; i < root.runningSection.length; i++) map[root.runningSection[i].appId] = root.runningSection[i]
    return map
  }
  readonly property var runningSection: root.dockModel.running || []
  readonly property var groupedSection: root.dockModel.grouped || []

  function refreshDock() {
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
    notificationBadgeTimer.restart()
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

  readonly property string activeId: {
    var top = ToplevelManager.activeToplevel
    return top && top.appId ? DockModel.normalizeId(top.appId) : ""
  }

  readonly property string activeWindowAddress: {
    var top = ToplevelManager.activeToplevel
    if (!top) return ""
    var h = root.hyprToplevelFor(top)
    return h ? root.windowAddress(h) : ""
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
  // Counts urgency events (Hyprland urgent, app notifications) so items can
  // animate again for a new event while they are already marked urgent.
  property int urgentEvents: 0
  // The app ids and window addresses the latest urgency event was about.
  property var urgentEventKeys: []
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
  property string dropTargetAppId: ""
  property string dropTargetGroupId: ""
  property string dragSourceGroupId: ""
  property real dropIndicatorX: 0
  // Pinned folders and app groups are dragged too: folders to reorder them,
  // and either one off the dock to take it away.
  property string dragFolderPath: ""
  property string dragGroupId: ""
  // Insert index among the pinned folders for the dragged folder; -1 while
  // the pointer is outside the folder section.
  property int dropFolderIndex: -1
  // Insert index in pinnedRow for a pinned app or group being dragged;
  // -1 while the pointer is outside the pinned run.
  property int dropRowIndex: -1
  // The drag has been pulled up off the dock: letting go unpins or removes.
  property bool dragRemoveArmed: false
  // Pointer of the drag in progress, in dock card coordinates.
  property real dragPointerX: 0
  property real dragPointerY: 0
  readonly property bool dockDragActive: root.dragAppId !== "" || root.dragFolderPath !== "" || root.dragGroupId !== ""

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
  // Directory the open stack is showing: the pinned folder, or one of its
  // subfolders after clicking into it. activeStackTrail holds the folders
  // walked through ({ path, name }), so Back can return step by step.
  property string activeStackPath: ""
  // The folder being listed. Its name, path and entries replace the shown
  // ones together when the scan lands, so switching folders never flashes
  // an empty or half-filled stack.
  property string pendingStackPath: ""
  property string pendingStackName: ""
  property bool activeStackLoading: false
  property real pendingStackX: 0
  property var activeStackTrail: []
  // "stack" (list) or "grid" (larger icons and previews), per pinned folder.
  readonly property string activeStackView: root.activeStackFolder !== "" ? root.folderViewFor(root.activeStackFolder) : "stack"
  property var activeStackEntries: []
  property int activeStackTotalCount: 0
  property real activeStackX: 0
  property string contextFolderPath: ""
  property string contextFolderName: ""

  // ------------------------------------------------- removable drives state
  property bool showRemovableDrives: true
  property var mountedDrives: []
  property string contextDriveDev: ""
  property string contextDriveMount: ""
  property string contextDriveName: ""
  property string contextDriveSpace: ""

  // ------------------------------------------------- app groups state
  property var appGroups: []
  property string activeAppGroupId: ""
  property var activeAppGroupData: null
  property real activeAppGroupX: 0
  property var contextAppGroupData: null

  // ------------------------------------------------- configuration options

  property string alignment: "center" // "center" | "left" | "right"

  property bool autohide: true
  property bool intelligentAutohide: true
  property bool showAppsButton: true
  property bool showTooltips: true
  property bool showMinimizedTiles: true
  // "zoom" grows only the icon under the pointer and leaves the layout alone —
  // the default. "wave" grows neighbours; lift, glow and glitch keep the
  // icon's size. "off" disables hover effects.
  property string hoverEffect: "zoom"
  readonly property bool waveHover: root.hoverEffect === "wave"
  // What HoverFx and DockIconArt read, in one object so each dock item
  // passes a single property.
  readonly property var hoverFx: ({
    effect: root.hoverEffect,
    reveal: root.iconHoverOriginal && root.iconHoverReveal,
    glow: Color.accent
  })
  property bool launchBounce: true
  property bool advancedTooltips: true
  property real borderOpacity: -1.0
  property real dockOpacity: 1.0
  readonly property real effectiveDockOpacity: {
    if (root.dockOpacity < 0) {
      var a = (Color.bar && Color.bar.background && typeof Color.bar.background.a === "number") ? Color.bar.background.a : 1.0
      return (isFinite(a) && a >= 0) ? a : 1.0
    }
    return Math.max(0.0, Math.min(1.0, root.dockOpacity))
  }
  property string dockShape: "rounded"
  // Corner radius for the "rounded" shape in logical pixels, set by hand in
  // Settings; negative keeps the automatic one that follows the dock height.
  property int cornerRadius: -1
  property string dockBgColor: "theme"
  property bool showBackground: true
  // Background fill: "solid" (dockBgColor) or "gradient" (below).
  property string bgFill: "solid"
  // Gradient palette: "theme" (built from the Omarchy theme's colours) or
  // one of gradientPresets. gradientStrength: how strongly the colours cover
  // the base background, 0..1.
  property string gradientPreset: "theme"
  property real gradientStrength: 0.6
  readonly property var gradientPresets: [
    { id: "aurora", name: "Aurora", colors: ["#5dffb0", "#7fc4ff", "#c99cff"] },
    { id: "sunset", name: "Sunset", colors: ["#ff7a59", "#ff4f8b", "#ffc15e"] },
    { id: "ocean", name: "Ocean", colors: ["#1e90ff", "#00c2c7", "#6a5cff"] },
    { id: "forest", name: "Forest", colors: ["#2e8b57", "#a3c95a", "#1f6f5c"] },
    { id: "rose", name: "Rose", colors: ["#ff9ac1", "#c86bfa", "#ffd1dc"] },
    { id: "lavender", name: "Lavender", colors: ["#b8a1ff", "#7aa2ff", "#f0b3ff"] },
    { id: "ember", name: "Ember", colors: ["#ff5e3a", "#ff9f1c", "#8b1e3f"] },
    { id: "citrus", name: "Citrus", colors: ["#ffd43b", "#94d82d", "#ff922b"] },
    { id: "mono", name: "Mono", colors: ["#9aa0a6", "#5f6368", "#d0d4d8"] }
  ]

  // Three colours from the current theme: its accent, then the two named
  // palette colours (colors.toml) that sit furthest enough in hue from the
  // accent and from each other, so the gradient never collapses into one
  // hue. Falls back to the accent alone when the theme names no colours.
  readonly property var themeGradientColors: {
    var _tv = root.themeVersion
    var text = ""
    try {
      text = DockModel.readCapped(themeColorsFile.text, DockModel.MAX_COLORS_TOML_BYTES)
    } catch (e) {
      console.warn("[omadock] Failed reading theme colors:", e)
    }
    var named = {}
    var re = /^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/gm
    var m
    while ((m = re.exec(text)) !== null) named[m[1]] = m[2]
    var accent = named.accent || String(Color.accent)
    var picked = [accent]
    var order = ["magenta", "blue", "cyan", "red", "green", "orange", "yellow"]
    function hueGap(a, b) {
      var ha = Qt.color(a).hslHue, hb = Qt.color(b).hslHue
      if (ha < 0 || hb < 0) return 1
      var d = Math.abs(ha - hb)
      return Math.min(d, 1 - d)
    }
    for (var i = 0; i < order.length && picked.length < 3; i++) {
      var c = named[order[i]]
      if (!c) continue
      var ok = true
      for (var j = 0; j < picked.length; j++) if (hueGap(c, picked[j]) < 0.07) ok = false
      if (ok) picked.push(c)
    }
    while (picked.length < 3) picked.push(accent)
    return picked
  }

  readonly property var gradientColors: {
    if (root.gradientPreset !== "theme") {
      for (var i = 0; i < root.gradientPresets.length; i++)
        if (root.gradientPresets[i].id === root.gradientPreset) return root.gradientPresets[i].colors
    }
    return root.themeGradientColors
  }

  // Static film grain over the background card, 0 (off) .. 1.
  property real grain: 0
  property bool showShadow: true
  // Draw each section of the dock (the parts between separators) as its own
  // panel, with a gap where the separator line would be.
  property bool splitSections: false
  // Shadow opacity, 0..1.
  property real shadowStrength: 0.4
  // Compositor blur behind the dock: "system" leaves it to the user's own
  // Hyprland layer rules; "on"/"off" add a runtime rule that overrides them.
  property string blurMode: "system"
  // Icon style: "original", "mono", "pixel" or "dots" (see DockIconArt).
  property string iconStyle: "original"
  // Colour for the mono and dots styles: the dock's text colour, the accent,
  // or "bw": near black or near white, whichever contrasts more with the
  // background behind the icons.
  property string iconTint: "text"
  // Cells across an icon for the pixel and dots styles.
  property int iconGrid: 16
  // mono / dots: adaptive contrast (0..1) and effect strength over the
  // original icon (0..1).
  property real iconContrast: 0
  property real iconStrength: 1
  // With an icon style on: show the hovered icon as shipped.
  property bool iconHoverOriginal: false
  // With iconHoverOriginal: the original dithers in cell by cell, rising
  // from the bottom, instead of replacing the styled icon at once.
  property bool iconHoverReveal: false
  // The mono / dots ink, kept readable against what sits behind the icons
  // (see readableOn): an accent tint over a theme gradient built from that
  // same accent would otherwise vanish into it.
  readonly property color iconTintColor: root.tintFor(root.iconTint, root.dockForeground, root.iconBackdropColor)

  // Tint for an iconTint mode ("text", "accent", "bw") over a backdrop.
  function tintFor(mode, textColor, backdrop) {
    if (mode === "bw") return root.blackOrWhiteOn(backdrop)
    return root.readableOn(mode === "accent" ? Color.accent : textColor, backdrop)
  }

  // Near black or near white, whichever contrasts more with the backdrop.
  function blackOrWhiteOn(backdrop) {
    var dark = Qt.color("#141414")
    var light = Qt.color("#f2f2f2")
    return root.contrastRatio(dark, backdrop) >= root.contrastRatio(light, backdrop) ? dark : light
  }

  // Best guess at the colour behind the icons: the card's fill (for a
  // gradient, its colours averaged and mixed into the base by the strength
  // they cover it with), or the theme background when the card is off.
  readonly property color iconBackdropColor: {
    var base = Color.bar.background
    if (!root.showBackground) return Color.background
    if (root.bgFill === "gradient") {
      var cols = root.gradientColors || []
      if (cols.length === 0) return base
      var r = 0, g = 0, b = 0
      for (var i = 0; i < cols.length; i++) {
        var c = Qt.color(cols[i])
        r += c.r; g += c.g; b += c.b
      }
      r /= cols.length; g /= cols.length; b /= cols.length
      var k = Math.min(1, root.gradientStrength * 0.75)
      return Qt.rgba(base.r + (r - base.r) * k, base.g + (g - base.g) * k, base.b + (b - base.b) * k, 1)
    }
    var custom = String(root.dockBgColor || "")
    return custom.charAt(0) === "#" ? Qt.color(custom) : base
  }

  // Divider lines: the backdrop mixed toward black or white, whichever
  // contrasts more, just far enough to be seen and no further. A fixed tint
  // of the text colour all but vanished on light docks. A light line on a
  // dark dock reads at a lower ratio than a dark one on a light dock, and
  // glares sooner, so it stops earlier.
  // The dock's rim, shared by the panels and by "theme" dividers.
  readonly property real rimAlpha: {
    // Specular Frosted Glass Rim: Crisp highlight with high alpha for contrast on dark and light surfaces
    var autoAlpha = (root.effectiveDockOpacity < 0.25 || root.dockBgColor === "none")
      ? 0.48
      : Math.max(0.24, root.effectiveDockOpacity * 0.35)
    // Manual override from Settings → Appearance → Border opacity.
    return root.borderOpacity < 0 ? autoAlpha : Math.max(0.0, Math.min(1.0, root.borderOpacity))
  }
  readonly property color rimColor: Util.alpha(root.dockForeground, root.rimAlpha)

  // Divider lines: "simple" is a thin line in dividerColor, "theme" is drawn
  // like the rim, in its colour, opacity and width, and "custom" in the
  // rim's colour with its own width and opacity.
  readonly property color dividerLineColor: root.dividerStyle === "theme" ? root.rimColor
    : root.dividerStyle === "custom" ? Util.alpha(root.dockForeground, root.dividerOpacity)
    : root.dividerColor
  readonly property real dividerLineWidth: root.dividerStyle === "theme" ? root.borderWidth
    : root.dividerStyle === "custom" ? root.dividerWidth
    : Style.space(1)

  readonly property color dividerColor: {
    var bg = Qt.color(root.iconBackdropColor)
    var ink = root.blackOrWhiteOn(bg)
    var target = ink.hslLightness > 0.5 ? 1.4 : 1.6
    var c = bg
    for (var t = 0.04; t <= 0.6; t += 0.02) {
      c = Qt.rgba(bg.r + (ink.r - bg.r) * t, bg.g + (ink.g - bg.g) * t, bg.b + (ink.b - bg.b) * t, 1)
      if (root.contrastRatio(c, bg) >= target) break
    }
    return c
  }

  // WCAG relative luminance and contrast ratio.
  function luminance(c) {
    function lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
  }
  function contrastRatio(a, b) {
    var la = root.luminance(a), lb = root.luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  // A colour with the given hue and saturation, moved in lightness away
  // from the backdrop (darker on a light one, lighter on a dark one) until
  // it reaches a 3:1 contrast ratio, the WCAG minimum for graphics.
  function readableOn(color, backdrop) {
    var c = Qt.color(color)
    var bg = Qt.color(backdrop)
    if (root.contrastRatio(c, bg) >= 3) return c
    var darker = root.luminance(bg) > 0.18
    var h = c.hslHue < 0 ? 0 : c.hslHue
    var sat = c.hslSaturation
    var best = c
    for (var step = 1; step <= 20; step++) {
      var l = darker ? Math.max(0, c.hslLightness - step * 0.05) : Math.min(1, c.hslLightness + step * 0.05)
      best = Qt.hsla(h, sat, l, c.a)
      if (root.contrastRatio(best, bg) >= 3) break
    }
    return best
  }
  // Without a card to cast one, each icon casts its own shadow.
  readonly property bool iconShadow: root.showShadow && !root.showBackground && root.shadowStrength > 0
  property bool showBorder: true
  // Running/open marks under items: "theme" follows the dock shape,
  // "rounded" dots and pills, "square" square dots and bars.
  property string indicatorShape: "theme"
  readonly property bool indicatorSquare: {
    if (root.indicatorShape === "square") return true
    if (root.indicatorShape === "rounded") return false
    if (root.dockShape === "square") return true
    if (root.dockShape === "theme" || root.dockShape === "auto") return !(Style.cornerRadius > 0)
    return false
  }
  // Rim width in logical pixels, 1..6.
  property real borderWidth: 1.5
  // App group tile look: "rounded" (softly rounded rim), "square" (rim
  // without rounding) or "none" (bare mini-icon grid).
  property string groupStyle: "rounded"
  // Icons in an opened group (AppGroupPopup): "theme" follows iconStyle,
  // "none" keeps them original. The tile on the dock always follows it.
  property string groupIconEffects: "theme"
  property bool settingsPanelOpen: false
  property string settingsPanelPage: "appearance"
  property int themeVersion: 0
  property string currentIconThemeName: "Yaru"
  property string folderColor: "theme"
  // Colour for symbolic folder and drive icons in the original icon style,
  // on the dock's own backdrop.
  readonly property color symbolicIconColor: root.symbolicColorOn(root.iconBackdropColor)

  // Symbolic icon colour over a given backdrop: white or black when set,
  // for "bw" whichever of the two contrasts more with that backdrop (so a
  // folder can be dark on the dock and light in a dark stack popup), and
  // otherwise white or black to suit the theme.
  function symbolicColorOn(backdrop) {
    var c
    if (root.folderColor === "white") c = Qt.color("#ffffff")
    else if (root.folderColor === "black") c = Qt.color("#111111")
    else if (root.folderColor === "bw") c = root.blackOrWhiteOn(backdrop)
    else c = Qt.color((Color.bar.background.hslLightness < 0.5 || Color.background.hslLightness < 0.5) ? "#ffffff" : "#111111")
    // Pure white glares next to the app icons; mix a little of the backdrop
    // into light glyphs so they sit in the panel instead.
    if (c.hslLightness > 0.5) {
      var bg = Qt.color(backdrop)
      var k = root.symbolicLightSoftening
      c = Qt.rgba(c.r + (bg.r - c.r) * k, c.g + (bg.g - c.g) * k, c.b + (bg.b - c.b) * k, 1)
    }
    return c
  }
  // Share of the backdrop mixed into light symbolic glyphs.
  readonly property real symbolicLightSoftening: 0.25
  property int itemSpacing: 4
  // Gap between the panels when sections are split.
  property int sectionSpacing: 18
  // Length of the section divider lines, in percent of the dock's height.
  property string dividerGeometry: "classic"
  property int dividerHeight: 70
  property string dividerStyle: "simple"
  property real dividerWidth: 1.5
  property real dividerOpacity: 0.4
  property string minimizeMode: "active"
  // Hyprland warps the pointer into a window it activates (and on workspace
  // switches); keepPointer suppresses that for focus changes the dock makes.
  property bool keepPointer: true
  readonly property bool clickToMinimize: root.minimizeMode !== "off"
  property bool showUrgentHint: true
  property bool urgentOnNotification: true
  property bool showNotificationBadges: true
  property var notificationBadges: ({})
  property var notificationPopupRows: []
  property bool urgentSound: true
  property string urgentSoundName: "bell"
  property var notifService: null
  property var _lastProcessedNotifTimestamp: 0
  property int revealDelay: 160
  property int tooltipDelay: 450
  // Least time between two wheel steps on the dock.
  property int wheelStepDelay: 150

  // ------------------------------------------------- autohide state

  property bool dockVisible: false
  readonly property int revealHeight: 6

  property bool windowsOverlapDock: false

  Timer {
    id: hideTimer
    interval: 550
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

  // Process identity survives TUI app-id overrides. Scan on window-list changes;
  // the helper bounds each descendant walk to known CLI names.
  Timer {
    id: terminalHostDebounce
    interval: 100
    onTriggered: if (!terminalIdentityScan.running) terminalIdentityScan.running = true
  }

  Process {
    id: terminalIdentityScan
    command: ["python3", decodeURIComponent(Qt.resolvedUrl("scripts/terminal-hosts.py").toString().replace(/^file:\/\//, ""))]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var identities = JSON.parse(text) || ({})
          root.terminalHosts = identities.terminals || ({})
          root.terminalApps = identities.apps || ({})
          modelTimer.restart()
        } catch (e) {
          console.warn("[omadock] Failed resolving terminal and CLI identities:", e)
        }
      }
    }
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
          console.warn("[omadock] Failed parsing clients JSON:", e)
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
        var cardX = dockCardComp ? dockCardComp.x : ((screenLogicalW - cardW) / 2)
        var dockLeft = monX + cardX
        var dockRight = dockLeft + cardW
        var dockTop = monY + screenLogicalH - cardH - Style.gapsOut
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
    property string sortKey: "modified"
    // scripts/list-folder.py lists, sorts and caps the folder (see its header).
    // timeout: a stalled filesystem (network mount) must not leave the helper running.
    command: ["timeout", "-k", "2", "10", "python3", decodeURIComponent(Qt.resolvedUrl("scripts/list-folder.py").toString().replace(/^file:\/\//, "")), folderStackScanner.targetFolder, folderStackScanner.sortKey, "300"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(this.text) || { count: 0, items: [] }
          // Stale-result guard: only apply if this scan is still for the
          // folder the user currently has open (or any at all). Prevents a
          // slow older scan from painting one folder's files under another's
          // header, or repopulating after the stack was closed.
          var wanted = String(root.pendingStackPath || "")
          if (parsed.folder !== wanted) return
          root.applyStackScan(parsed.items || [], parsed.count || 0)
        } catch (e) {
          console.warn("[omadock] Failed parsing folder scan:", e)
          root.applyStackScan([], 0)
        }
      }
    }
  }

  Process {
    id: customFolderPickerProc
    // Goes through the XDG FileChooser portal, so the picker is whatever the
    // desktop routes FileChooser to (the default file manager when it ships a
    // portal backend); a GTK dialog, zenity or kdialog are fallbacks.
    command: ["python3", decodeURIComponent(Qt.resolvedUrl("scripts/pick-folder.py").toString().replace(/^file:\/\//, ""))]
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

  Process {
    id: removableDrivesScanner
    // scripts/list-drives.py reads lsblk and prints the drives as JSON.
    command: ["python3", root.scriptPath("list-drives.py")]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(this.text) || []
          root.mountedDrives = DockModel.isList(parsed) ? parsed : []
        } catch (e) {
          console.warn("[omadock] Failed parsing removable drives:", e)
          root.mountedDrives = []
        }
      }
    }
  }

  Process {
    id: udevMonitorProc
    command: ["udevadm", "monitor", "--subsystem-match=block", "--udev"]
    running: root.showRemovableDrives
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        driveDebounceTimer.restart()
      }
    }
  }

  Timer {
    id: driveDebounceTimer
    interval: 600
    repeat: false
    onTriggered: root.scanRemovableDrives()
  }

  Process {
    id: ejectProc
    property string dev: ""
    property string mountpoint: ""
    property string driveName: ""
    // scripts/eject-drive.py: gio, then udisksctl, then umount; the label is
    // cleaned before it reaches the notification.
    command: ["python3", root.scriptPath("eject-drive.py"), ejectProc.dev, ejectProc.mountpoint, ejectProc.driveName]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.closeContext()
        root.scanRemovableDrives()
      }
    }
  }

  // A chooser closed by the compositor rather than through its own Cancel may
  // never answer the portal, which would leave the picker process waiting and
  // swallow every later click. Asking again restarts it instead.
  function pickCustomFolder() {
    if (customFolderPickerProc.running) {
      customFolderPickerProc.running = false
      Qt.callLater(function() { customFolderPickerProc.running = true })
      return
    }
    customFolderPickerProc.running = true
  }

  function scanRemovableDrives() {
    if (!root.showRemovableDrives) {
      root.mountedDrives = []
      return
    }
    if (!removableDrivesScanner.running) removableDrivesScanner.running = true
  }

  function openDriveContext(dev, mp, name, space, cx, cy) {
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

  function ejectDrive(dev, mountpoint, name) {
    ejectProc.dev = dev || ""
    ejectProc.mountpoint = mountpoint || ""
    ejectProc.driveName = name || "Drive"
    ejectProc.running = true
  }

  function setDockAlignment(align) {
    var a = String(align || "").toLowerCase()
    root.alignment = (a === "left" || a === "right") ? a : "center"
    root.saveConfig()
    if (root.intelligentAutohide) debounceOverlapTimer.restart()
    root.syncVisibility()
  }

  function setDockPosition(pos) {
    setDockAlignment(pos)
  }

  function openAppGroup(gdata, cx, cy) {
    if (root.activeAppGroupId === (gdata && gdata.id ? gdata.id : "")) {
      root.closeAppGroup()
      return
    }
    root.closeContext()
    root.closeFolderStack()
    root.activeAppGroupId = (gdata && gdata.id) ? gdata.id : ""
    root.activeAppGroupData = gdata
    root.activeAppGroupX = cx
    root.syncVisibility()
  }

  function closeAppGroup() {
    root.activeAppGroupId = ""
    root.activeAppGroupData = null
    root.syncVisibility()
  }

  function openAppGroupContext(gdata, cx, cy) {
    root.closeContext()
    root.closeFolderStack()
    root.closeAppGroup()
    root.contextAppId = "__app_group_context__"
    root.contextAppGroupData = gdata
    root.contextX = cx
    root.contextY = cy
  }

  function createAppGroupFromRunning() {
    var all = (root.pinnedSection || []).concat(root.runningSection || [])
    var ids = []
    for (var i = 0; i < all.length; i++) {
      if (all[i] && all[i].running && all[i].appId && ids.indexOf(all[i].appId) < 0) {
        ids.push(all[i].appId)
      }
    }
    if (ids.length === 0) return
    var newGroup = {
      id: "group_" + Date.now(),
      name: "Group " + (root.appGroups ? (root.appGroups.length + 1) : 1),
      icon: "folder",
      apps: ids,
      cols: 3
    }
    root.appGroups = (root.appGroups || []).concat([newGroup])
    root.saveConfig()
  }

  function createAppGroupFromDrop(targetAppId, draggedAppId) {
    if (!targetAppId || !draggedAppId || targetAppId === draggedAppId) return
    var targetEntry = DockModel.entryFor(root.appRows, targetAppId)
    var folderName = "Folder"
    if (targetEntry && targetEntry.name) {
      folderName = targetEntry.name + " & more"
    }

    // The group takes the place of the app it was dropped on.
    var pinsNow = root.pinnedIds || []
    var at = pinsNow.indexOf(targetAppId)
    var anchor = ""
    for (var n = at + 1; at >= 0 && n < pinsNow.length; n++) {
      if (pinsNow[n] !== targetAppId && pinsNow[n] !== draggedAppId) { anchor = pinsNow[n]; break }
    }
    var newGroup = {
      id: "group_" + Date.now(),
      name: folderName,
      icon: "folder",
      apps: [targetAppId, draggedAppId],
      cols: 3,
      before: anchor
    }
    root.appGroups = (root.appGroups || []).concat([newGroup])

    // Remove grouped items from pinnedIds so they now live inside the folder
    var pins = root.pinnedIds || []
    var nextPins = []
    for (var p = 0; p < pins.length; p++) {
      if (pins[p] !== targetAppId && pins[p] !== draggedAppId) {
        nextPins.push(pins[p])
      }
    }
    root.setPinned(nextPins)
    root.saveConfig()
  }

  function addAppToGroup(groupId, appId) {
    if (!groupId || !appId) return
    var groups = root.appGroups || []
    var next = []
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (g && g.id === groupId) {
        var curApps = DockModel.toArray(g.apps)
        if (curApps.indexOf(appId) < 0) curApps.push(appId)
        next.push({ id: g.id, name: g.name, icon: g.icon, apps: curApps, cols: g.cols || 3, before: g.before || "" })
      } else {
        next.push(g)
      }
    }
    root.appGroups = next

    // Remove from pinnedIds if it was pinned
    var pins = root.pinnedIds || []
    var nextPins = []
    for (var p = 0; p < pins.length; p++) {
      if (pins[p] !== appId) nextPins.push(pins[p])
    }
    root.setPinned(nextPins)
    root.saveConfig()
  }

  function updateAppGroupName(groupId, newName) {
    if (!groupId || !newName) return
    var groups = root.appGroups || []
    var next = []
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (g && g.id === groupId) {
        next.push({ id: g.id, name: newName.trim(), icon: g.icon, apps: g.apps, cols: g.cols || 3, before: g.before || "" })
      } else {
        next.push(g)
      }
    }
    root.appGroups = next
    if (root.activeAppGroupData && root.activeAppGroupData.id === groupId) {
      root.activeAppGroupData = Object.assign({}, root.activeAppGroupData, { name: newName.trim() })
    }
    root.saveConfig()
  }

  function renameAppGroup(groupId, newName) {
    root.updateAppGroupName(groupId, newName)
  }

  function updateAppGroupColumns(groupId, cols) {
    if (!groupId || !cols) return
    var groups = root.appGroups || []
    var next = []
    var c = Math.max(2, Math.min(4, cols))
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (g && g.id === groupId) {
        next.push({ id: g.id, name: g.name, icon: g.icon, apps: g.apps, cols: c, before: g.before || "" })
      } else {
        next.push(g)
      }
    }
    root.appGroups = next
    if (root.activeAppGroupData && root.activeAppGroupData.id === groupId) {
      root.activeAppGroupData = Object.assign({}, root.activeAppGroupData, { cols: c })
    }
    root.saveConfig()
  }

  function removeAppFromGroup(groupId, appId, insertBeforeId) {
    if (!groupId || !appId) return
    var groups = root.appGroups || []
    var next = []
    var remainingApps = []

    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (g && g.id === groupId) {
        var curApps = DockModel.toArray(g.apps)
        var filtered = []
        for (var a = 0; a < curApps.length; a++) {
          if (curApps[a] !== appId) filtered.push(curApps[a])
        }
        remainingApps = filtered
        if (filtered.length > 1) {
          next.push({ id: g.id, name: g.name, icon: g.icon, apps: filtered, cols: g.cols || 3, before: g.before || "" })
        }
      } else {
        next.push(g)
      }
    }
    root.appGroups = next

    var pins = (root.pinnedIds || []).slice()

    // If remaining length === 1, dissolve group: extract single remaining app into pinnedIds
    if (remainingApps.length === 1) {
      var lastApp = remainingApps[0]
      if (pins.indexOf(lastApp) < 0) {
        pins.push(lastApp)
      }
      if (root.activeAppGroupId === groupId) {
        root.closeAppGroup()
      }
    } else if (remainingApps.length === 0) {
      if (root.activeAppGroupId === groupId) {
        root.closeAppGroup()
      }
    }

    // Restore removed app to pinned items if not dragging (e.g. context menu ungroup)
    if (!root.dragSourceGroupId) {
      if (pins.indexOf(appId) < 0) {
        if (insertBeforeId) {
          var toIdx = pins.indexOf(DockModel.stripDesktop(insertBeforeId))
          if (toIdx >= 0) pins.splice(toIdx, 0, appId)
          else pins.push(appId)
        } else {
          pins.push(appId)
        }
      }
    }

    root.setPinned(pins)
    root.saveConfig()

    if (remainingApps.length > 1 && root.activeAppGroupId === groupId) {
      var foundGroup = null
      for (var j = 0; j < next.length; j++) {
        if (next[j].id === groupId) { foundGroup = next[j]; break }
      }
      if (foundGroup) root.activeAppGroupData = foundGroup
      else root.closeAppGroup()
    }
  }

  // Dissolves a group: its apps become pins where the group stood. Removing
  // a group (removeAppGroup) drops its apps from the dock instead, as
  // dragging a pin off the dock unpins it.
  function ungroupAppGroup(groupId) {
    if (!groupId) return
    if (root.activeAppGroupId === groupId) root.closeAppGroup()
    root.applyPinnedRow(DockModel.ungroupRow(root.pinnedRow, groupId))
  }

  function removeAppGroup(groupId) {
    var groups = root.appGroups || []
    var next = []
    for (var i = 0; i < groups.length; i++) {
      if (groups[i] && groups[i].id !== groupId) {
        next.push(groups[i])
      }
    }
    root.appGroups = next
    root.saveConfig()
    if (root.activeAppGroupId === groupId) root.closeAppGroup()
  }

  function syncVisibility() {
    // Mode 1: Always Show
    if (!root.autohide) {
      hideTimer.stop()
      revealTimer.stop()
      root.dockVisible = true
      return
    }

    var isHovered = (root.cardHover && root.cardHover.hovered) || (root.hitboxHover && root.hitboxHover.hovered) || (revealHover && revealHover.hovered) || root.contextAppId !== "" || root.dockDragActive || root.activeStackFolder !== "" || root.activeAppGroupId !== "" || root.settingsPanelOpen || root.externalDragOver || root.appDropTargetId !== ""

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
  onActiveAppGroupIdChanged: root.syncVisibility()
  onDragAppIdChanged: root.syncVisibility()
  onSettingsPanelOpenChanged: root.syncVisibility()
  onExternalDragOverChanged: {
    if (!root.externalDragOver) root.dropPinArmed = false
    root.syncVisibility()
  }
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
      root.closeAppGroup()
    }
  }

  // ------------------------------------------------- file views
  //
  // Watched files feed the long-lived shell process, so the byte ceiling and
  // the regular-file gate apply BEFORE any content is loaded into QML: every
  // watched path goes through CappedFileView, which keeps FileView as a change
  // watcher only and reads content through a stat-then-read gate bounded by
  // DockModel.MAX_*_BYTES (a large file or FIFO can never enter or stall the
  // shell at the read boundary). DockModel.readCapped stays as defense in
  // depth on the accepted slice. Reload cycles are debounced (fileChanged only
  // fires from the filesystem watcher, never from our own atomic writes — the
  // debounce coalesces rapid external edit bursts and the _savingConfig guard
  // keeps the read after a save from re-applying stale data).

  // Coalesces rapid external change bursts into one reload per file.
  Timer {
    id: configReloadDebounce
    interval: 120
    repeat: false
    // The read is asynchronous; onLoaded applies it once it lands.
    onTriggered: configFile.reload()
  }

  Timer {
    id: dockReloadDebounce
    interval: 120
    repeat: false
    onTriggered: dockFile.reload()
  }

  CappedFileView {
    id: configFile
    path: root.configPath
    maxBytes: DockModel.MAX_CONFIG_BYTES
    watchChanges: true
    atomicWrites: true
    onLoaded: {
      if (root._savingConfig) return
      root.loadConfig()
      root.scanRemovableDrives()
    }
    onFileChanged: {
      if (root._savingConfig) return
      configReloadDebounce.restart()
    }
  }

  CappedFileView {
    id: dockFile
    path: root.dockPath
    maxBytes: DockModel.MAX_DOCK_JSON_BYTES
    watchChanges: true
    atomicWrites: true
    onLoaded: root.loadPinned()
    onFileChanged: dockReloadDebounce.restart()
  }

  CappedFileView {
    id: themeIconsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/icons.theme"
    maxBytes: DockModel.MAX_ICONS_THEME_BYTES
    watchChanges: true
    onLoaded: root.handleThemeChanged()
    onFileChanged: themeIconsFile.reload()
  }

  CappedFileView {
    id: themeColorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    maxBytes: DockModel.MAX_COLORS_TOML_BYTES
    watchChanges: true
    onLoaded: root.handleThemeChanged()
    onFileChanged: themeColorsFile.reload()
  }

  CappedFileView {
    id: dndConfigFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/notifications.json"
    maxBytes: DockModel.MAX_NOTIFICATIONS_BYTES
    watchChanges: true
    onFileChanged: dndConfigFile.reload()
  }

  readonly property bool isDndActive: {
    if (root.notifService && typeof root.notifService.doNotDisturb === "boolean") {
      return root.notifService.doNotDisturb
    }
    try {
      var txt = DockModel.readCapped(dndConfigFile.text, DockModel.MAX_NOTIFICATIONS_BYTES).trim()
      if (txt) {
        var parsed = JSON.parse(txt)
        if (parsed && typeof parsed.dnd === "boolean") return parsed.dnd
      }
    } catch (e) {
      console.warn("[omadock] Failed reading dnd config:", e)
    }
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
      terminalHostDebounce.restart()
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
      } catch (e) {
        console.warn("[omadock] Error handling active toplevel change:", e)
      }
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
      // A config reload drops runtime layer rules along with the Lua state.
      if (n === "configreloaded") {
        root.applyBlurRule(true)
        modelSettleTimer.restart()
        terminalHostDebounce.restart()
        return
      }
      if (n === "windowtitlev2") {
        terminalHostDebounce.restart()
        modelTimer.restart()
      }
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
        root.urgentEventKeys = [fullAddr]
        root.urgentEvents++
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
        if (root.urgentMap) {
          root.clearUrgentApp("", fullAddr)
        }
        if (root.minimizedOrigins && root.minimizedOrigins[fullAddr]) {
          var mo = DockModel.copyMap(root.minimizedOrigins)
          delete mo[fullAddr]
          root.minimizedOrigins = mo
        }
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
      // Per-monitor docks: a workspace (and its windows) changing monitor
      // moves those apps to another dock.
      if (root.filterByMonitor && (n === "moveworkspace" || n === "moveworkspacev2"
          || n === "monitoradded" || n === "monitorremoved")) modelSettleTimer.restart()
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

  function refreshNotificationBadges() {
    var rows = root.showNotificationBadges ? root.notificationPopupRows : []
    var popups = root.notifService ? root.notifService.popupModel : null
    if (root.showNotificationBadges && popups) {
      rows = []
      for (var i = 0; i < Math.min(popups.count, 512); i++) rows.push(popups.get(i))
    }
    root.notificationBadges = DockModel.notificationCounts(
      root.pinnedSection.concat(root.runningSection), root.appRows, rows)
  }

  // Overlay plugins may not receive the first-party notification service.
  // The shell's active-popup files offer a read-only, event-driven fallback.
  Process {
    id: notificationPopupWatch
    running: root.showNotificationBadges && !root.notifService
    command: ["python3", decodeURIComponent(Qt.resolvedUrl("scripts/notification-popups.py").toString().replace(/^file:\/\//, ""))]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        try {
          var rows = JSON.parse(line)
          root.notificationPopupRows = Array.isArray(rows) ? rows : []
          notificationBadgeTimer.restart()
        } catch (e) {
          console.warn("[omadock] Failed reading notification popup snapshot:", e)
        }
      }
    }
  }

  // Several role changes can describe one replacement notification.
  Timer {
    id: notificationBadgeTimer
    interval: 20
    onTriggered: root.refreshNotificationBadges()
  }
  onNotifServiceChanged: notificationBadgeTimer.restart()
  onShowNotificationBadgesChanged: notificationBadgeTimer.restart()

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
    var eventKeys = []

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
        eventKeys.push(appId)
        for (var w2 = 0; w2 < wins.length; w2++) {
          var wa2 = wins[w2] ? wins[w2].address : ""
          if (wa2) { map[wa2] = true; eventKeys.push(wa2) }
        }
        found = true
      }
    }

    if (found) {
      root.urgentMap = map
      root.urgentEventKeys = eventKeys
      root.urgentEvents++
      modelTimer.restart()
    }

    // Play notification alert sound (suppressed if DND is active)
    // Only one dock chimes when several run side by side.
    if (root.isPrimary && root.urgentSound && root.urgentSoundName !== "none" && !root.isDndActive) {
      Quickshell.execDetached(["canberra-gtk-play", "-i", root.urgentSoundName])
    }
  }

  Connections {
    target: root.notifService ? root.notifService.popupModel : null
    function onRowsInserted(parent, first, last) {
      notificationBadgeTimer.restart()
      if (!root.showUrgentHint || !root.urgentOnNotification || !root.notifService || !root.notifService.popupModel) return
      for (var i = first; i <= last; i++) {
        var row = root.notifService.popupModel.get(i)
        if (row) root.handleNotificationReceived(row)
      }
    }
    function onRowsRemoved(parent, first, last) { notificationBadgeTimer.restart() }
    function onDataChanged(topLeft, bottomRight, roles) { notificationBadgeTimer.restart() }
    function onModelReset() { notificationBadgeTimer.restart() }
    function onCountChanged() {
      notificationBadgeTimer.restart()
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
    root.pinnedIds = DockModel.parsePinned(DockModel.readCapped(dockFile.text, DockModel.MAX_DOCK_JSON_BYTES))
  }

  // The look: every value a preset holds, parsed and clamped exactly as the
  // config file is. Used when the config loads and when a preset applies.
  // Sets properties only; callers save and update the blur rule.
  function applyLook(parsed) {
    // Migrates the old boolean: an explicit magnification:false meant no growth.
    root.hoverEffect = parsed && ["zoom", "wave", "lift", "glow", "glitch", "off"].indexOf(parsed.hoverEffect) >= 0
      ? parsed.hoverEffect
      : ((parsed && parsed.magnification === false) ? "off" : "zoom")
    root.launchBounce = parsed && parsed.launchBounce !== false
    root.configuredIconSize = parsed && typeof parsed.iconSize === "number" && isFinite(parsed.iconSize) && parsed.iconSize > 0
      ? Math.max(16, Math.min(96, Math.round(parsed.iconSize))) : 0
    if (parsed && (parsed.opacity === "theme" || parsed.opacity === "auto" || parsed.opacity === -1)) {
      root.dockOpacity = -1.0
    } else if (parsed && typeof parsed.opacity === "number") {
      root.dockOpacity = Math.max(0.0, Math.min(1.0, parsed.opacity))
    } else {
      root.dockOpacity = 1.0
    }
    if (parsed && (parsed.borderOpacity === "theme" || parsed.borderOpacity === "auto" || parsed.borderOpacity === -1)) {
      root.borderOpacity = -1.0
    } else if (parsed && typeof parsed.borderOpacity === "number") {
      root.borderOpacity = Math.max(0.0, Math.min(1.0, parsed.borderOpacity))
    } else {
      root.borderOpacity = -1.0
    }
    root.dockShape = parsed && typeof parsed.shape === "string" ? parsed.shape : "rounded"
    root.cornerRadius = parsed && typeof parsed.cornerRadius === "number" && isFinite(parsed.cornerRadius) && parsed.cornerRadius >= 0
      ? Math.max(2, Math.round(parsed.cornerRadius)) : -1
    root.dockBgColor = parsed && typeof parsed.bgColor === "string" ? parsed.bgColor : "theme"
    root.showBackground = parsed ? parsed.showBackground !== false : true
    root.bgFill = (parsed && parsed.bgFill === "gradient") ? "gradient" : "solid"
    root.gradientPreset = parsed && typeof parsed.gradientPreset === "string" ? parsed.gradientPreset : "theme"
    root.gradientStrength = parsed && typeof parsed.gradientStrength === "number" ? Math.max(0, Math.min(1, parsed.gradientStrength)) : 0.6
    root.grain = parsed && typeof parsed.grain === "number" ? Math.max(0, Math.min(1, parsed.grain)) : 0
    root.showShadow = parsed ? parsed.showShadow !== false : true
    root.splitSections = parsed ? parsed.splitSections === true : false
    root.shadowStrength = parsed && typeof parsed.shadowStrength === "number"
      ? Math.max(0, Math.min(1, parsed.shadowStrength))
      : 0.4
    root.blurMode = (parsed && (parsed.blur === "on" || parsed.blur === "off")) ? parsed.blur : "system"
    root.iconStyle = (parsed && ["mono", "pixel", "dots"].indexOf(parsed.iconStyle) >= 0) ? parsed.iconStyle : "original"
    root.iconTint = (parsed && (parsed.iconTint === "accent" || parsed.iconTint === "bw")) ? parsed.iconTint : "text"
    root.iconHoverOriginal = parsed ? parsed.iconHoverOriginal === true : false
    root.iconHoverReveal = parsed ? parsed.iconHoverReveal === true : false
    root.iconContrast = parsed && typeof parsed.iconContrast === "number" ? Math.max(0, Math.min(1, parsed.iconContrast)) : 0
    root.iconStrength = parsed && typeof parsed.iconStrength === "number" ? Math.max(0, Math.min(1, parsed.iconStrength)) : 1
    root.iconGrid = parsed && typeof parsed.iconGrid === "number"
      ? Math.max(8, Math.min(32, Math.round(parsed.iconGrid)))
      : 16
    root.showBorder = parsed ? parsed.showBorder !== false : true
    root.indicatorShape = (parsed && (parsed.indicatorShape === "rounded" || parsed.indicatorShape === "square")) ? parsed.indicatorShape : "theme"
    root.borderWidth = parsed && typeof parsed.borderWidth === "number"
      ? Math.max(1, Math.min(6, parsed.borderWidth))
      : 1.5
    // Anything else, including the retired "theme" style, falls back to rounded.
    root.groupStyle = (parsed && ["square", "none"].indexOf(parsed.groupStyle) >= 0) ? parsed.groupStyle : "rounded"
    root.groupIconEffects = (parsed && parsed.groupIconEffects === "none") ? "none" : "theme"
    root.folderColor = parsed && typeof parsed.folderColor === "string" ? parsed.folderColor : "theme"
    root.itemSpacing = parsed && typeof parsed.itemSpacing === "number" && isFinite(parsed.itemSpacing)
      ? Math.max(0, Math.min(32, Math.round(parsed.itemSpacing))) : 4
    root.sectionSpacing = parsed && typeof parsed.sectionSpacing === "number" ? Math.max(0, Math.min(48, Math.round(parsed.sectionSpacing))) : 18
    root.dividerGeometry = parsed && parsed.dividerGeometry === "long" ? "long" : "classic"
    root.dividerHeight = parsed && typeof parsed.dividerHeight === "number" && isFinite(parsed.dividerHeight) ? Math.max(20, Math.min(100, Math.round(parsed.dividerHeight))) : 70
    root.dividerStyle = parsed && ["theme", "custom"].indexOf(parsed.dividerStyle) >= 0 ? parsed.dividerStyle : "simple"
    root.dividerWidth = parsed && typeof parsed.dividerWidth === "number" && isFinite(parsed.dividerWidth) ? Math.max(1, Math.min(6, Math.round(parsed.dividerWidth * 2) / 2)) : 1.5
    root.dividerOpacity = parsed && typeof parsed.dividerOpacity === "number" && isFinite(parsed.dividerOpacity) ? Math.max(0, Math.min(1, parsed.dividerOpacity)) : 0.4
    // Theme dividers without a border, saved before they turned custom.
    // Converted in place: saving here would write the rest of the config
    // before it is read.
    if (root.dividerStyle === "theme" && !root.showBorder) {
      root.dividerWidth = root.borderWidth
      root.dividerOpacity = Math.round(root.rimAlpha * 100) / 100
      root.dividerStyle = "custom"
    }
  }

  function loadConfig() {
    var raw = DockModel.readCapped(configFile.text, DockModel.MAX_CONFIG_BYTES).trim()
    var parsed = {}
    if (raw) {
      try {
        parsed = JSON.parse(raw)
      } catch (e) {
        console.warn("[omadock] Failed parsing omadock.json, using defaults:", e)
        parsed = {}
      }
    }
    root.alignment = (parsed && (parsed.alignment || parsed.position)) ? String(parsed.alignment || parsed.position).toLowerCase() : "center"
    if (root.alignment !== "left" && root.alignment !== "right") root.alignment = "center"
    root.showRemovableDrives = parsed ? parsed.showRemovableDrives !== false : true
    if (parsed && DockModel.isList(parsed.appGroups)) {
      // Persisted collections are shape- and size-bounded before reaching the
      // long-lived shell (see DockModel boundAppGroups / boundPinnedFolders).
      root.appGroups = DockModel.boundAppGroups(parsed.appGroups)
    } else {
      root.appGroups = []
    }
    root.presets = parsed ? DockModel.boundPresets(parsed.presets) : []
    root.autohide = parsed && parsed.autohide !== false
    root.intelligentAutohide = parsed && parsed.intelligentAutohide !== false
    root.showAppsButton = parsed && parsed.showAppsButton !== false
    root.showTooltips = parsed && parsed.showTooltips !== false
    root.showMinimizedTiles = parsed ? parsed.showMinimizedTiles !== false : true
    root.advancedTooltips = parsed && parsed.advancedTooltips !== false
    root.screenName = parsed && typeof parsed.screen === "string" ? parsed.screen : ""
    root.multiMonitor = parsed ? parsed.multiMonitor === true : false
    root.perMonitorApps = parsed ? parsed.perMonitorApps !== false : true
    root.applyLook(parsed)
    root.blurSize = parsed && typeof parsed.blurSize === "number" ? Math.max(0, Math.min(20, Math.round(parsed.blurSize))) : 0
    root.systemBlurSize = DockModel.boundSystemBlurSize(parsed ? parsed.systemBlurSize : 0)
    root.applyBlurRule(false)
    if (parsed && typeof parsed.minimizeMode === "string") {
      root.minimizeMode = parsed.minimizeMode
    } else if (parsed && parsed.clickToMinimize === true) {
      root.minimizeMode = "active"
    } else {
      root.minimizeMode = "active"
    }
    root.keepPointer = parsed ? parsed.keepPointer !== false : true
    root.showUrgentHint = parsed ? parsed.showUrgentHint !== false : true
    root.urgentOnNotification = parsed ? parsed.urgentOnNotification !== false : true
    root.showNotificationBadges = parsed ? parsed.showNotificationBadges !== false : true
    root.urgentSound = parsed ? parsed.urgentSound !== false : true
    root.urgentSoundName = DockModel.cleanSoundName(parsed ? parsed.urgentSoundName : "bell")
    root.revealDelay = parsed && typeof parsed.revealDelay === "number"
      ? Math.max(0, Math.min(2000, Math.round(parsed.revealDelay)))
      : 160
    root.tooltipDelay = parsed && typeof parsed.tooltipDelay === "number"
      ? Math.max(0, Math.min(5000, Math.round(parsed.tooltipDelay)))
      : 450
    root.wheelStepDelay = parsed && typeof parsed.wheelStepDelay === "number"
      ? Math.max(0, Math.min(1000, Math.round(parsed.wheelStepDelay)))
      : 150
    if (parsed && DockModel.isList(parsed.pinnedFolders)) {
      root.pinnedFolders = DockModel.boundPinnedFolders(parsed.pinnedFolders)
    } else {
      root.pinnedFolders = [
        { path: "~/Downloads", name: "Downloads", icon: "folder-download" }
      ]
    }
  }

  function rescanApps() {
    terminalHostDebounce.restart()
    root.appRows = root.appLibrary ? root.appLibrary.sortedEntries("") : []
    root.refreshDock()
  }

  // Up to five sources report one theme switch (three Color signals, the
  // icon theme file, the colors file); each used to rescan apps and rebuild
  // the dock. After the first load they coalesce into one run once the
  // burst is over; the first load applies at once so icons do not flash.
  property bool _themeApplied: false
  function handleThemeChanged() {
    if (!root._themeApplied) {
      root._themeApplied = true
      root.applyThemeChange()
      return
    }
    themeChangeTimer.restart()
  }

  Timer {
    id: themeChangeTimer
    interval: 100
    onTriggered: root.applyThemeChange()
  }

  function applyThemeChange() {
    try {
      var t = DockModel.readCapped(themeIconsFile.text, DockModel.MAX_ICONS_THEME_BYTES).trim()
      if (t) root.currentIconThemeName = t
    } catch (e) {
      console.warn("[omadock] Failed reading icon theme:", e)
    }
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

  function folderColorLabel(colorId) {
    if (!colorId || colorId === "theme" || colorId === "auto") return "Auto (Theme)"
    if (colorId === "white") return "White"
    if (colorId === "black") return "Black"
    if (colorId === "bw") return "Black or white"
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
    root.contextAppId = "__dock_settings__"
  }

  // ------------------------------------------------- compositor blur
  // Hyprland blurs layers through layer rules, which can switch blur on or
  // off per layer but not size it: blur size is one global setting
  // (decoration.blur.size). So "on" can also carry a size, applied globally,
  // and the size Hyprland had before (systemBlurSize) is put back when the
  // dock stops overriding it. The rule lives in a Lua global so a later change
  // (or "system") can disable it again without reloading the user's config.
  // One dock applies it: every dock shares the "omadock" namespace.
  // "" until the first apply, so a rule left behind by an earlier shell
  // session (the Lua state outlives the shell) is always reconciled.
  property string _appliedBlurMode: ""

  function applyBlurRule(force) {
    if (!root.isPrimary) return
    if (force || root.blurMode !== root._appliedBlurMode) {
      var lua = "if _G.omadock_blur_rule then _G.omadock_blur_rule:set_enabled(false) end"
      if (root.blurMode !== "system") {
        lua += " _G.omadock_blur_rule = hl.layer_rule({ match = { namespace = \"^omadock$\" }, blur = "
          + (root.blurMode === "on" ? "true" : "false") + ", blur_popups = "
          + (root.blurMode === "on" ? "true" : "false") + ", ignore_alpha = 0.05 })"
      }
      Quickshell.execDetached(["hyprctl", "eval", lua])
      root._appliedBlurMode = root.blurMode
    }
    // The size can change while the mode stays the same.
    root.applyBlurSize(force)
  }

  // Global blur size the dock asks for while blur is "on"; 0 leaves it alone.
  property int blurSize: 0
  // Hyprland's own blur size, captured before the first override so it can be
  // restored; persisted, since the override outlives a shell restart.
  property int systemBlurSize: 0
  property int _appliedBlurSize: 0

  function setHyprBlurSize(size) {
    Quickshell.execDetached(["hyprctl", "eval",
      "hl.config({ decoration = { blur = { size = " + Math.round(size) + " } } })"])
  }

  function applyBlurSize(force) {
    if (!root.isPrimary) return
    var want = (root.blurMode === "on" && root.blurSize > 0) ? root.blurSize : 0
    if (!force && want === root._appliedBlurSize) return
    if (want > 0) root.setHyprBlurSize(want)
    else if (root._appliedBlurSize > 0 && root.systemBlurSize > 0) root.setHyprBlurSize(root.systemBlurSize)
    root._appliedBlurSize = want
  }

  // currentSize: Hyprland's blur size right now, read by the settings panel;
  // remembered as the system size the first time the dock overrides it.
  function setBlurSize(size, currentSize) {
    if (root.systemBlurSize <= 0 && root._appliedBlurSize <= 0 && currentSize > 0)
      root.systemBlurSize = DockModel.boundSystemBlurSize(currentSize)
    root.blurSize = Math.max(1, Math.min(20, Math.round(size)))
    root.applyBlurSize(false)
    root.saveConfig()
  }

  // ------------------------------------------------- drops from outside
  // Folders dragged in from a file manager are pinned as stacks. Hover
  // handlers do not fire during a drag, so the drop areas report it here to
  // keep (or bring) the dock in view.
  property bool externalDragOver: false
  // A file is being dragged out of the open folder stack. The dismiss area
  // collapses meanwhile: it spans nearly the whole screen, and while it is in
  // the input mask the compositor offers the drag to the dock instead of the
  // window under the pointer.
  property bool fileDragOut: false
  // While a folder is dragged over the dock: its path once confirmed to be a
  // directory (dropCandidatePath), and where among the pinned folders it
  // would land (0..count). Opening a dragged item with an app comes first
  // (see beginAppDrop): pinning only arms once the pointer has rested in the
  // folder section (DockCard's pinDwell), and only then does the folder row
  // open a gap there, the way the macOS dock does.
  property string dropCandidatePath: ""
  property bool dropPinArmed: false
  readonly property string dropPreviewPath: (root.dropPinArmed && root.externalDragOver) ? root.dropCandidatePath : ""
  property int dropInsertIndex: -1

  // Called on drag enter: finds the first directory among the dragged URLs.
  function previewDraggedFolder(urls) {
    root.dropCandidatePath = ""
    root.dropPinArmed = false
    var paths = root.localPathsFromUrls(urls)
    if (paths.length === 0) return
    if (dropFolderProbe.running) dropFolderProbe.running = false
    dropFolderProbe.command = ["sh", "-c", 'for p; do [ -d "$p" ] && { printf "%s\\n" "$p"; exit 0; }; done', "sh"].concat(paths)
    dropFolderProbe.running = true
  }

  Process {
    id: dropFolderProbe
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        if (root.externalDragOver && line) root.dropCandidatePath = String(line)
      }
    }
  }

  function insertFolderPin(path, name, icon, index) {
    if (root.isFolderPinned(path)) return
    var next = (root.pinnedFolders || []).slice()
    var at = (index >= 0 && index <= next.length) ? index : next.length
    next.splice(at, 0, { path: path, name: name || "Folder", icon: icon || DockModel.folderIconFor(path, "") })
    root.pinnedFolders = next
    root.saveConfig()
  }

  // Local filesystem path of a helper in scripts/.
  function scriptPath(name) {
    return decodeURIComponent(Qt.resolvedUrl("scripts/" + name).toString().replace(/^file:\/\//, ""))
  }

  function localPathsFromUrls(urls) {
    return DockModel.localPathsFromUrls(urls)
  }

  function pinDroppedFolders(urls) {
    var paths = root.localPathsFromUrls(urls)
    dropFolderCheck.insertAt = root.dropInsertIndex
    root.dropPinArmed = false
    root.dropCandidatePath = ""
    root.dropInsertIndex = -1
    if (paths.length === 0) return
    // Only directories are pinned; the check runs out of process.
    dropFolderCheck.command = ["sh", "-c", 'for p; do [ -d "$p" ] && printf "%s\\n" "$p"; done', "sh"].concat(paths)
    dropFolderCheck.running = true
  }

  Process {
    id: dropFolderCheck
    // Where the next confirmed folder goes; -1 appends. Advances per folder
    // so several dropped at once keep their order.
    property int insertAt: -1
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        var chosen = String(line || "").replace(/\/+$/, "")
        if (chosen === "" || root.isFolderPinned(chosen)) return
        var home = Quickshell.env("HOME")
        var relPath = (chosen === home || chosen.indexOf(home + "/") === 0) ? "~" + chosen.slice(home.length) : chosen
        root.insertFolderPin(relPath, chosen.split("/").pop() || "Folder", DockModel.folderIconFor(relPath, ""), dropFolderCheck.insertAt)
        if (dropFolderCheck.insertAt >= 0) dropFolderCheck.insertAt++
      }
    }
  }

  // ------------------------------------------------- media controls
  // The MPRIS player an app exposes, matched on the player's DesktopEntry
  // (or, failing that, its Identity) against the dock app id. Proxies such as
  // playerctld name no app, so they never match. A playing instance wins
  // when an app exposes several (e.g. browser tabs).
  function mediaPlayerFor(appId) {
    if (!appId || appId.indexOf("__") === 0) return null
    var list = (Mpris.players && Mpris.players.values) ? Mpris.players.values : []
    var fallback = null
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p) continue
      var entry = String(p.desktopEntry || "").replace(/\.desktop$/, "")
      var ident = String(p.identity || "")
      var matches = (entry !== "" && DockModel.isAppMatch(appId, entry))
        || (entry === "" && ident !== "" && DockModel.isAppMatch(appId, ident))
      if (!matches) continue
      if (p.isPlaying) return p
      if (!fallback) fallback = p
    }
    return fallback
  }

  // Player for the app whose context menu is open, if any.
  readonly property var contextPlayer: root.mediaPlayerFor(root.contextAppId)

  // ------------------------------------------------- files dropped on apps
  // Dragging files onto an app icon opens them with that app, as the macOS
  // dock does, when its desktop entry declares every dropped file's MIME type
  // (scripts/drop-check.py). The check runs once per icon entered; files let
  // go before it answers open as soon as it says yes.
  property string appDropTargetId: ""
  property string appDropState: ""    // "", "pending", "yes", "no"
  property var appDropPaths: []
  property string _appDropOpenId: ""  // dropped while pending: open on "yes"
  onAppDropTargetIdChanged: root.syncVisibility()

  // The desktop entry id an app launches through (same lookup as launchApp).
  function desktopIdFor(appId) {
    var deskEntry = DockModel.entryFor(root.appRows, appId)
    if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries)
      deskEntry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    return (deskEntry && deskEntry.id) ? deskEntry.id : appId
  }

  function beginAppDrop(appId, urls) {
    root.appDropTargetId = appId
    root._appDropOpenId = ""
    root.appDropPaths = root.localPathsFromUrls(urls)
    if (root.appDropPaths.length === 0) {
      root.appDropState = "no"
      return
    }
    root.appDropState = "pending"
    if (appDropCheck.running) appDropCheck.running = false
    appDropCheck.command = ["python3",
      decodeURIComponent(Qt.resolvedUrl("scripts/drop-check.py").toString().replace(/^file:\/\//, "")),
      root.desktopIdFor(appId)].concat(root.appDropPaths)
    appDropCheck.running = true
  }

  function endAppDrop(appId) {
    if (root.appDropTargetId !== appId) return
    root.appDropTargetId = ""
    // A drop still waiting on the check keeps its state until it answers.
    if (root._appDropOpenId === "") root.appDropState = ""
  }

  // Returns false when the app cannot take the files (the drop is refused).
  function dropOnApp(appId) {
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

  function openFilesWith(appId, paths) {
    if (!paths || paths.length === 0) return
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", "--", root.desktopIdFor(appId) + ".desktop"].concat(paths))
  }

  Process {
    id: appDropCheck
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        var ok = String(line).trim() === "yes"
        if (root._appDropOpenId !== "") {
          if (ok) root.openFilesWith(root._appDropOpenId, root.appDropPaths)
          root._appDropOpenId = ""
          root.appDropState = ""
          return
        }
        if (root.appDropTargetId !== "") root.appDropState = ok ? "yes" : "no"
      }
    }
  }

  function setBlurMode(mode) {
    root.blurMode = mode
    root.applyBlurRule(false)
    root.saveConfig()
  }

  function openSettingsPanel() {
    root.closeContext()
    root.closeFolderStack()
    root.closeAppGroup()
    root.settingsPanelOpen = true
  }

  function closeSettingsPanel() {
    root.settingsPanelOpen = false
    root.syncVisibility()
  }

  // Plain value settings from the settings panel: set, persist.
  function setOption(key, value) {
    root[key] = value
    root.saveConfig()
  }

  // Leaving "theme" for "custom" starts from the rim's width and opacity, so
  // the lines look the same until changed.
  function setDividerStyle(style) {
    if (style === "custom" && root.dividerStyle === "theme") {
      root.dividerWidth = root.borderWidth
      root.dividerOpacity = Math.round(root.rimAlpha * 100) / 100
    }
    root.dividerStyle = style
    root.saveConfig()
  }

  // "theme" dividers follow the rim, so they turn "custom" when it goes
  // away: they keep their look and stay adjustable.
  function setShowBorder(show) {
    if (!show && root.dividerStyle === "theme") root.setDividerStyle("custom")
    root.showBorder = show
    root.saveConfig()
  }

  function setDockScreen(name) {
    root.screenName = name || ""
    root.saveConfig()
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

  function setBorderOpacity(val) {
    root.borderOpacity = val
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
    name = DockModel.cleanSoundName(name)
    root.urgentSoundName = name
    root.urgentSound = name !== "none"
    if (name !== "none" && !root.isDndActive) {
      Quickshell.execDetached(["canberra-gtk-play", "-i", name])
    }
    root.saveConfig()
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
    return "0x" + value.toLowerCase()
  }

  function luaString(value) {
    return String(value == null ? "" : value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  }

  // Hyprland 0.56 moved dispatchers to Lua; Quickshell reports which syntax
  // the running compositor speaks.
  function hyprDispatch(lua, legacy) {
    Hyprland.dispatch(Hyprland.usingLua ? lua : legacy)
  }

  // Runs action with Hyprland's pointer warps switched off. Activation goes
  // over Wayland and workspace switches over the IPC socket, so the setting
  // has to land first: the actions wait for hyprctl to exit. The compositor
  // restores the user's no_warps value on its own timer, which survives a
  // shell crash; repeated calls extend the window instead of saving "true".
  property var pendingNoWarpActions: []

  function withoutPointerWarp(action) {
    if (!root.keepPointer || !Hyprland.usingLua) {
      action()
      return
    }
    root.pendingNoWarpActions = root.pendingNoWarpActions.concat([action])
    if (!noWarpProc.running) noWarpProc.running = true
  }

  Process {
    id: noWarpProc
    command: ["hyprctl", "eval",
      'if _G.omadock_nowarp_saved == nil then _G.omadock_nowarp_saved = hl.get_config("cursor.no_warps") end\n'
      + 'hl.config({ cursor = { no_warps = true } })\n'
      + '_G.omadock_nowarp_gen = (_G.omadock_nowarp_gen or 0) + 1\n'
      + 'local gen = _G.omadock_nowarp_gen\n'
      + 'hl.timer(function()\n'
      + '  if _G.omadock_nowarp_gen ~= gen then return end\n'
      + '  hl.config({ cursor = { no_warps = _G.omadock_nowarp_saved } })\n'
      + '  _G.omadock_nowarp_saved = nil\n'
      + 'end, { timeout = 500, type = "oneshot" })']
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("[omadock] Pointer-warp suppression failed:", exitCode)
      var actions = root.pendingNoWarpActions
      root.pendingNoWarpActions = []
      for (var i = 0; i < actions.length; i++) actions[i]()
    }
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
    } catch (e) {
      console.warn("[omadock] Failed resolving live toplevel for address:", e)
    }
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
    } catch (e) {
      console.warn("[omadock] Failed resolving live Hyprland toplevel for address:", e)
    }
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
      root.withoutPointerWarp(function() {
        var live = root.liveToplevelForAddress(addr)
        var h = root.liveHyprToplevelForAddress(addr)
        if (!live) return
        DockModel.focusWindow(live)
        var ws = h ? h.workspace : null
        if (ws && Hyprland.focusedWorkspace && ws.id !== Hyprland.focusedWorkspace.id) {
          var targetWs = root.workspaceTarget(ws)
          if (targetWs) {
            root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(targetWs) + '" })',
                              "workspace " + targetWs)
          }
        }
      })
    } else if (top) {
      root.focusToplevel(top, appId)
    }
  }

  // Brings a window forward cleanly. Native Wayland activation hands over focus
  // and brings the window forward without desynchronizing layer-shell input
  // state; withoutPointerWarp keeps Hyprland from moving the pointer to it.
  // Switches workspace when target is on another workspace.
  function focusToplevel(toplevel, appId) {
    if (!toplevel) return
    var handle = root.hyprToplevelFor(toplevel)
    var addr = root.windowAddress(handle)
    if (!addr) {
      DockModel.focusWindow(toplevel)
      return
    }
    var aid = appId || (toplevel.appId ? DockModel.normalizeId(toplevel.appId) : "")
    root.clearUrgentApp(aid, addr)
    var workspace = handle ? handle.workspace : null

    if (workspace && workspace.name === root.minimizedWorkspace) {
      root.restoreWindow(handle, aid)
      return
    }

    // Resolve by address after the subprocess: a window may close meanwhile.
    root.withoutPointerWarp(function() {
      var live = addr ? root.liveToplevelForAddress(addr) : null
      if (!live) return
      DockModel.focusWindow(live)
      var h = root.liveHyprToplevelForAddress(addr)
      var ws = h ? h.workspace : null
      if (ws && Hyprland.focusedWorkspace && ws.id !== Hyprland.focusedWorkspace.id) {
        var targetWs = root.workspaceTarget(ws)
        if (targetWs) {
          root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(targetWs) + '" })',
                            "workspace " + targetWs)
        }
      }
    })
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
    root.withoutPointerWarp(function() {
      root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(target) + '" })',
                        "workspace " + target)

      var top = root.liveToplevelForAddress(address)
      if (top) {
        DockModel.focusWindow(top)
      }
    })
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
      root.withoutPointerWarp(function() {
        root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(focusTarget) + '" })',
                          "workspace " + focusTarget)
        var top = root.liveToplevelForAddress(focusAddr)
        if (top) DockModel.focusWindow(top)
      })
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

  // Turns wheel events into steps: -1 (up), 1 (down) or 0. High-resolution
  // wheels send many small deltas per notch, so deltas add up to a full notch
  // (120) first, and a step needs wheelStepDelay since the previous one,
  // which also tames free-spinning wheels. Leftovers are dropped rather than
  // queued. Each wheel target keeps its own state under key.
  property var wheelState: ({})

  function wheelStep(key, angleDelta) {
    if (!angleDelta) return 0
    var now = Date.now()
    var st = root.wheelState[key] || { acc: 0, lastEvent: 0, lastStep: 0 }
    if (now - st.lastEvent > 400 || (st.acc !== 0 && (st.acc > 0) !== (angleDelta > 0))) st.acc = 0
    st.lastEvent = now
    st.acc += angleDelta
    var step = 0
    if (Math.abs(st.acc) >= 120) {
      if (now - st.lastStep >= root.wheelStepDelay) {
        step = st.acc > 0 ? -1 : 1
        st.lastStep = now
      }
      st.acc = 0
    }
    // Reuse one slot per current target rather than retaining every app ever scrolled.
    root.wheelState = ({})
    root.wheelState[key] = st
    return step
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

  // The app's parked window that has been waiting the shortest time — the tail of
  // the chronological FIFO. Windows parked most recently sort first.
  function recentParked(parked) {
    if (!parked || parked.length <= 1) return (parked && parked[0]) || null
    var best = parked[0]
    var bestTime = (best && best.address && root.parkedAt[best.address] !== undefined) ? root.parkedAt[best.address] : 0
    for (var i = 1; i < parked.length; i++) {
      var p = parked[i]
      var t = (p && p.address && root.parkedAt[p.address] !== undefined) ? root.parkedAt[p.address] : 0
      if (t > bestTime) {
        best = p
        bestTime = t
      }
    }
    return best
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
  // set by the notification service. Address keys die with their window; bare appId
  // keys only survive while the app is running with active windows or launching.
  function keepUrgentLive(map, live) {
    var keys = Object.keys(map)
    if (keys.length === 0) return map

    var next = {}
    var dropped = false
    var allEntries = root.pinnedSection.concat(root.runningSection).concat(root.groupedSection || [])

    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (key.slice(0, 2) === "0x") {
        if (!live[key]) dropped = true
        else next[key] = map[key]
      } else {
        var isLiveApp = false
        if (root.launchPending && root.launchPending[key]) {
          isLiveApp = true
        } else {
          for (var e = 0; e < allEntries.length; e++) {
            var entry = allEntries[e]
            if (!entry) continue
            var eId = entry.appId || entry.id
            if (eId === key || DockModel.isAppMatch(eId, key)) {
              var wins = entry.windowList || []
              for (var w = 0; w < wins.length; w++) {
                var wa = wins[w] ? wins[w].address : ""
                if (wa && live[wa]) {
                  isLiveApp = true
                  break
                }
              }
              break
            }
          }
        }
        if (isLiveApp) {
          next[key] = map[key]
        } else {
          dropped = true
        }
      }
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

    if (normAddr && map[normAddr]) {
      delete map[normAddr]
      changed = true
    }

    var allEntries = root.pinnedSection.concat(root.runningSection).concat(root.groupedSection || [])
    var targetEntries = []

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

    if (appId) {
      var rawId = DockModel.stripDesktop(appId)
      var normId = DockModel.normalizeId(appId)
      if (map[appId]) { delete map[appId]; changed = true }
      if (rawId && map[rawId]) { delete map[rawId]; changed = true }
      if (normId && map[normId]) { delete map[normId]; changed = true }
    }

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
  function minimizeActive() {
    var addr = root.activeWindowAddress
    if (addr !== "") root.minimizeToplevel(addr)
  }

  // Returns whether a window was restored, so DockHost can fall through to the
  // next monitor's dock when this one has nothing parked.
  function restoreLast() {
    var parked = []
    var all = root.pinnedSection.concat(root.runningSection)
    for (var i = 0; i < all.length; i++) {
      if (!all[i]) continue
      parked = parked.concat(root.parkedWindows(all[i].windowList || []))
    }
    if (parked.length === 0) return false
    return root.restoreWindow(root.oldestParked(parked), "")
  }

  // With several docks running, DockHost owns the "omadock" target instead.
  IpcHandler {
    target: "omadock"
    enabled: root.ipcEnabled

    function minimizeActive(): void {
      root.minimizeActive()
    }

    function restoreLast(): void {
      root.restoreLast()
    }

    function toggleVisibility(): void {
      root.dockVisible = !root.dockVisible
    }

    function reveal(): void {
      root.dockVisible = true
    }

    function hide(): void {
      root.dockVisible = false
    }

    function setAlignment(align: string): void {
      root.setDockAlignment(align)
    }

    function openSettings(): void {
      root.openSettingsPanel()
    }

    function openSettingsPage(page: string): void {
      root.settingsPanelPage = page
      root.openSettingsPanel()
    }

    function closeSettings(): void {
      root.closeSettingsPanel()
    }

    function setPosition(pos: string): void {
      root.setDockPosition(pos)
    }
  }

  // ------------------------------------------------- launch feedback

  function launchApp(appId, entry) {
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

  // Reads no file, so bindings can use the current configuration.
  function buildConfig(base) {
    var conf = base && typeof base === "object" && !Array.isArray(base) ? base : {}
    conf.alignment = root.alignment || "center"
    delete conf.position
    conf.showRemovableDrives = root.showRemovableDrives
    conf.appGroups = DockModel.boundAppGroups(root.appGroups)
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
    else delete conf.screen
    conf.multiMonitor = root.multiMonitor
    conf.perMonitorApps = root.perMonitorApps
    if (root.configuredIconSize > 0) conf.iconSize = root.configuredIconSize
    else delete conf.iconSize
    conf.opacity = root.dockOpacity < 0 ? "theme" : root.dockOpacity
    conf.borderOpacity = root.borderOpacity < 0 ? "theme" : root.borderOpacity
    conf.shape = root.dockShape
    if (root.cornerRadius >= 0) conf.cornerRadius = root.cornerRadius
    else delete conf.cornerRadius
    conf.bgColor = root.dockBgColor
    conf.showBackground = root.showBackground
    conf.bgFill = root.bgFill
    conf.gradientPreset = root.gradientPreset
    conf.gradientStrength = root.gradientStrength
    conf.grain = root.grain
    conf.showShadow = root.showShadow
    conf.splitSections = root.splitSections
    conf.shadowStrength = root.shadowStrength
    conf.blur = root.blurMode
    if (root.blurSize > 0) conf.blurSize = root.blurSize
    else delete conf.blurSize
    if (root.systemBlurSize > 0) conf.systemBlurSize = root.systemBlurSize
    conf.iconStyle = root.iconStyle
    conf.iconTint = root.iconTint
    conf.iconHoverOriginal = root.iconHoverOriginal
    conf.iconHoverReveal = root.iconHoverReveal
    conf.iconContrast = root.iconContrast
    conf.iconStrength = root.iconStrength
    conf.iconGrid = root.iconGrid
    conf.showBorder = root.showBorder
    conf.indicatorShape = root.indicatorShape
    conf.borderWidth = root.borderWidth
    conf.groupStyle = root.groupStyle
    conf.groupIconEffects = root.groupIconEffects
    conf.folderColor = root.folderColor
    conf.itemSpacing = root.itemSpacing
    conf.sectionSpacing = root.sectionSpacing
    conf.dividerGeometry = root.dividerGeometry
    conf.dividerHeight = root.dividerHeight
    conf.dividerStyle = root.dividerStyle
    conf.dividerWidth = root.dividerWidth
    conf.dividerOpacity = root.dividerOpacity
    conf.minimizeMode = root.minimizeMode
    conf.clickToMinimize = root.minimizeMode !== "off"
    conf.keepPointer = root.keepPointer
    conf.showUrgentHint = root.showUrgentHint
    conf.urgentOnNotification = root.urgentOnNotification
    conf.showNotificationBadges = root.showNotificationBadges
    conf.urgentSound = root.urgentSound
    conf.urgentSoundName = root.urgentSoundName
    conf.revealDelay = root.revealDelay
    conf.tooltipDelay = root.tooltipDelay
    conf.wheelStepDelay = root.wheelStepDelay
    conf.pinnedFolders = DockModel.boundPinnedFolders(root.pinnedFolders)
    conf.presets = DockModel.boundPresets(root.presets)
    return conf
  }

  // The current look as a preset stores it.
  readonly property var currentLook: DockModel.pickLook(root.buildConfig({}))

  function saveConfig() {
    // configBase returns null for a file holding anything other than a JSON
    // object (a typo, an array, an oversize paste): rewriting from {} would
    // silently drop every key the dock does not own, so skip the save.
    var conf = configFile.oversized ? null
      : DockModel.configBase(DockModel.readCapped(configFile.text, DockModel.MAX_CONFIG_BYTES))
    if (conf === null) {
      console.warn("[omadock] omadock.json is not a readable JSON object (or is over the size cap); not saving so its other keys survive. Fix the file to save settings again.")
      return
    }
    conf = root.buildConfig(conf)
    root._savingConfig = true
    configFile.setText(JSON.stringify(conf, null, 2))
    Qt.callLater(function() { root._savingConfig = false })
  }

  // ------------------------------------------------- appearance presets
  // Named copies of the look (DockModel.LOOK_KEYS), at most six, kept in the
  // config. Applying one goes through applyLook, like loading the config.
  property var presets: []
  readonly property bool canSavePreset: (root.presets || []).length < DockModel.MAX_PRESETS
  readonly property string activePresetId: {
    var cur = root.currentLook
    var list = root.presets || []
    for (var i = 0; i < list.length; i++)
      if (list[i] && DockModel.lookIncludes(cur, list[i].look)) return list[i].id
    return ""
  }

  function presetIndex(id) {
    var list = root.presets || []
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === id) return i
    return -1
  }

  // The preset with this name, ignoring case; "" when none or the name is
  // longer than a preset name can be.
  function presetIdByName(name) {
    var raw = String(name == null ? "" : name).trim()
    if (raw === "" || raw.length > DockModel.MAX_PRESET_NAME) return ""
    var want = DockModel.cleanPresetName(raw).toLowerCase()
    var list = root.presets || []
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].name.toLowerCase() === want) return list[i].id
    return ""
  }

  // Read-only snapshot of the dock items' rectangles in window coordinates,
  // for the benchmark and live tests (IPC itemGeometry). Changes nothing.
  function itemGeometry() {
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
    for (i = 0; i < card.pinnedRowRepeater.count; i++) {
      var slot = card.pinnedRowRepeater.itemAt(i)
      it = slot ? slot.item : null
      if (!it) continue
      if (it.groupData !== undefined) add(it, "group", (it.groupData || {}).id, 0, false)
      else if (it.appId !== undefined) add(it, "app", it.appId, it.windows, it.urgent)
    }
    for (i = 0; i < card.runningRepeater.count; i++) {
      it = card.runningRepeater.itemAt(i)
      if (it) add(it, "app", it.appId, it.windows, it.urgent)
    }
    for (i = 0; i < card.minimizedTilesRepeater.count; i++)
      add(card.minimizedTilesRepeater.itemAt(i), "tile", "", 1, false)
    for (i = 0; i < card.foldersRepeater.count; i++) {
      it = card.foldersRepeater.itemAt(i)
      if (it) add(it, "folder", it.folderPath, 0, false)
    }
    for (i = 0; i < card.drivesRepeater.count; i++) {
      it = card.drivesRepeater.itemAt(i)
      if (it) add(it, "drive", it.mountpoint, 0, false)
    }
    return JSON.stringify(out)
  }

  function presetNameTaken(name, exceptId) {
    var id = root.presetIdByName(name)
    return id !== "" && id !== exceptId
  }

  function nextPresetName() {
    for (var n = 1; n <= DockModel.MAX_PRESETS + 1; n++)
      if (!root.presetNameTaken("Preset " + n, "")) return "Preset " + n
    return "Preset"
  }

  function replacePreset(i, preset) {
    var next = root.presets.slice()
    next[i] = preset
    root.presets = next
    root.saveConfig()
  }

  // A new preset from the current look; returns its id, or "" when the list
  // is full. A missing or taken name becomes "Preset N".
  function savePreset(name) {
    if (!root.canSavePreset) return ""
    var clean = DockModel.cleanPresetName(name)
    if (clean === "" || root.presetNameTaken(clean, "")) clean = root.nextPresetName()
    var id = "preset_" + Date.now()
    while (root.presetIndex(id) >= 0) id += "0"
    root.presets = (root.presets || []).concat([{ id: id, name: clean, look: root.currentLook }])
    root.saveConfig()
    return id
  }

  // Refuses an empty name or one another preset has.
  function renamePreset(id, name) {
    var i = root.presetIndex(id)
    var clean = DockModel.cleanPresetName(name)
    if (i < 0 || clean === "" || root.presetNameTaken(clean, id)) return false
    var p = root.presets[i]
    root.replacePreset(i, { id: p.id, name: clean, look: p.look })
    return true
  }

  function updatePreset(id) {
    var i = root.presetIndex(id)
    if (i < 0) return false
    var p = root.presets[i]
    root.replacePreset(i, { id: p.id, name: p.name, look: root.currentLook })
    return true
  }

  function deletePreset(id) {
    var i = root.presetIndex(id)
    if (i < 0) return false
    var next = root.presets.slice()
    next.splice(i, 1)
    root.presets = next
    root.saveConfig()
    return true
  }

  // Keys a preset lacks (saved before they existed) keep their current value.
  function applyPreset(id) {
    var i = root.presetIndex(id)
    if (i < 0) return false
    root.applyLook(Object.assign({}, root.currentLook, root.presets[i].look))
    root.applyBlurRule(false)
    root.saveConfig()
    return true
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
    if (!root.appLibrary) return

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
    } else if (parked.length > 0) {
      // Restore the window (preferring most recently parked, or oldest)
      root.restoreWindow(root.recentParked(parked) || root.oldestParked(parked), appId)
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
    var grouped = root.groupedSection || []
    for (i = 0; i < grouped.length; i++) {
      if (grouped[i].appId === appId || DockModel.isAppMatch(grouped[i].appId, appId))
        return grouped[i]
    }
    return null
  }

  function setPinned(next) {
    // A group standing before an app that is no longer pinned moves before
    // the next one that is, instead of dropping to the end.
    var groups = DockModel.reanchorGroups(root.appGroups, root.pinnedIds, next)
    root.pinnedIds = next
    dockFile.setText(DockModel.serializePinned(next))
    if (groups !== root.appGroups) {
      root.appGroups = groups
      root.saveConfig()
    }
  }

  // Puts pinned apps and app groups in the order of a pinnedRow.
  function applyPinnedRow(row) {
    var state = DockModel.rowState(row, root.pinnedIds)
    root.appGroups = state.groups
    root.setPinned(state.pins)
    root.saveConfig()
  }

  function togglePin(appId) {
    var id = DockModel.stripDesktop(appId)
    if (!id) return
    // Pin-time validation: never pin an id that no longer resolves to an
    // installed desktop entry — the pin could only ever bounce silently.
    // Unpinning bypasses the check so stale pins can always be removed.
    if (!DockModel.isPinned(root.pinnedIds, id) && !root.resolveDesktopEntry(id)) {
      root.notifyAppMissing(id, "It cannot be pinned to the dock — reinstall the app first.")
      return
    }
    root.setPinned(DockModel.togglePinned(root.pinnedIds, id))
  }

  function resolveDesktopEntry(appId) {
    var entry = DockModel.entryFor(root.appRows, appId)
    if (!entry && typeof DesktopEntries !== "undefined" && DesktopEntries)
      entry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    return entry || null
  }

  // Shared feedback for the "app is gone" classes (launching a stale pin,
  // pinning an unresolvable id) that used to fail silently. The label is
  // markup-escaped: notification bodies are rendered as markup.
  function notifyAppMissing(name, detail) {
    var label = String(name || "This app").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    Quickshell.execDetached([
      "notify-send", "-a", "OmaDock", "-i", "dialog-error",
      "App no longer installed",
      label + " is no longer installed. " + String(detail || "Reinstall the app or unpin it from the dock.")
    ])
  }

  function launchDesktopAction(action, appName) {
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
    if (root.appContextMenuColumnRef && root.appContextMenuColumnRef.selectedWindowIdx >= wins.length) {
      root.appContextMenuColumnRef.selectedWindowIdx = -1
    }
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
    if (root.appContextMenuColumnRef) root.appContextMenuColumnRef.selectedWindowIdx = -1
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
  function applyStackScan(items, count) {
    if (root.pendingStackPath === "") return
    root.activeStackPath = root.pendingStackPath
    root.activeStackName = root.pendingStackName
    root.activeStackX = root.pendingStackX
    root.activeStackTotalCount = count
    root.activeStackEntries = items
    root.activeStackLoading = false
  }

  function showStackDir(dir, name) {
    if (folderStackScanner.running) folderStackScanner.running = false
    root.pendingStackPath = dir
    root.pendingStackName = name
    root.activeStackLoading = true
    // First open: nothing to keep on screen, so show the header right away.
    if (root.activeStackEntries.length === 0) {
      root.activeStackPath = dir
      root.activeStackName = name
    }
    folderStackScanner.targetFolder = dir
    folderStackScanner.sortKey = root.folderSortFor(root.activeStackFolder)
    folderStackScanner.running = true
  }

  // Step into a subfolder of the open stack.
  function enterStackDir(dir, name) {
    var trail = root.activeStackTrail.slice()
    trail.push({ path: root.activeStackPath, name: root.activeStackName })
    root.activeStackTrail = trail
    root.showStackDir(dir, name || dir.split("/").pop() || "Folder")
  }

  function stackBack() {
    var trail = root.activeStackTrail.slice()
    if (trail.length === 0) return
    var prev = trail.pop()
    root.activeStackTrail = trail
    root.showStackDir(prev.path, prev.name)
  }

  function closeFolderStack() {
    if (folderStackScanner.running) folderStackScanner.running = false
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

  function openFolderContext(path, name, cx, cy) {
    root.closeFolderStack()
    root.contextFolderPath = path
    root.contextFolderName = name || "Folder"
    root.contextX = cx
    root.contextY = cy
    root.contextAppId = "__folder_context__"
    root.syncVisibility()
  }

  // Per-folder stack order, stored on the pinned entry (see list-folder.py).
  readonly property var folderSortLabels: ({
    name: "Name",
    kind: "Kind",
    modified: "Date Modified",
    added: "Date Added",
    size: "Size"
  })

  function folderSortFor(path) {
    var norm = (path || "").replace(/^~/, Quickshell.env("HOME"))
    var list = root.pinnedFolders || []
    for (var i = 0; i < list.length; i++) {
      if ((list[i].path || "").replace(/^~/, Quickshell.env("HOME")) === norm)
        return list[i].sort || "modified"
    }
    return "modified"
  }

  function folderViewFor(path) {
    var norm = (path || "").replace(/^~/, Quickshell.env("HOME"))
    var list = root.pinnedFolders || []
    for (var i = 0; i < list.length; i++) {
      if ((list[i].path || "").replace(/^~/, Quickshell.env("HOME")) === norm)
        return list[i].view === "grid" ? "grid" : "stack"
    }
    return "stack"
  }

  // Sets one field (sort, view) on a pinned folder's entry and saves.
  function setFolderOption(path, key, value) {
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

  function setFolderSort(path, sort) {
    root.setFolderOption(path, "sort", sort)
    // Re-list an open stack of this folder in its new order.
    var open = String(root.activeStackFolder || "").replace(/^~/, Quickshell.env("HOME"))
    if (open !== "" && open === (path || "").replace(/^~/, Quickshell.env("HOME")))
      root.showStackDir(root.activeStackPath, root.activeStackName)
  }

  function setFolderView(path, view) {
    root.setFolderOption(path, "view", view === "grid" ? "grid" : "stack")
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

  // Move an app group within the pinned run, or a pinned folder among the
  // folders, so it lands before the item now at insertIndex (the end when
  // insertIndex is past the last one).
  function moveAppGroup(groupId, insertIndex) {
    var row = root.pinnedRow
    var from = -1
    for (var i = 0; i < row.length; i++) {
      if (row[i].kind === "group" && row[i].id === groupId) { from = i; break }
    }
    var next = DockModel.moveBefore(row, from, insertIndex)
    if (next !== row) root.applyPinnedRow(next)
  }

  function moveFolder(path, insertIndex) {
    var list = root.pinnedFolders || []
    var from = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].path === path) { from = i; break }
    }
    var next = DockModel.moveBefore(list, from, insertIndex)
    if (next === list) return
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

  // ------------------------------------- layer-surface recovery (issue #9)
  // Suspend/resume, monitor unplug and DPMS make Hyprland close every layer
  // surface (zwlr_layer_surface_v1.closed on output removal); Quickshell
  // treats that as final and deletes the backing window outright
  // (WlrLayershell.deleteOnInvisible), and nothing used to bring it back —
  // the dock vanished until a shell restart. Track the close and rebuild the
  // surface as soon as a real screen is available again. Fully event-driven.
  property bool dockSurfaceClosed: false

  Connections {
    target: dockWindow
    function onClosed() { root.dockSurfaceClosed = true }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      if (root.dockSurfaceClosed)
        // Defer past binding evaluation so dockWindow.screen has adopted
        // the fresh QuickshellScreenInfo before the window is recreated.
        Qt.callLater(root.recoverDockSurface)
    }
  }

  function recoverDockSurface() {
    if (!root.dockSurfaceClosed || !root.dockScreen) return
    root.dockSurfaceClosed = false
    // Setting visible takes the supported recreate path: setVisibleDirect(true)
    // builds a new backing window and a fresh wlr-layer-shell surface on the
    // current screen. Screen reassignment alone cannot revive a deleted one.
    dockWindow.visible = true
  }

  // ------------------------------------------------- panel window

  PanelWindow {
    id: dockWindow

    screen: root.dockScreen
    color: "transparent"
    WlrLayershell.namespace: "omadock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: (appGroupLoader.item && appGroupLoader.item.body.isEditingName)
      ? WlrKeyboardFocus.OnDemand
      : WlrKeyboardFocus.None
    exclusionMode: (!root.autohide) ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: (!root.autohide) ? Math.round((dockCardComp ? dockCardComp.dockCard.height : 0) + Style.gapsOut * 2) : 0
    anchors {
      bottom: true
      left: true
      right: true
    }
    // Only the card plus room above it for magnification, the launch/urgent
    // bounce and the drag "Unpin" bubble; menus and tooltips are popups.
    // Even logical height keeps the layer origin on the physical pixel grid
    // at scale 1.5 (DockIndicator snaps to it).
    readonly property real dockHeadroom: Style.space(56)
    implicitHeight: {
      var h = Math.ceil((dockCardComp ? dockCardComp.dockCard.height : 64) + Style.gapsOut + dockWindow.dockHeadroom)
      return h + (h % 2)
    }

    mask: Region {
      item: (root.dockVisible && dockCardComp && dockCardComp.dockHitbox) ? dockCardComp.dockHitbox : dockCardComp.dockCard
      regions: [
        Region { item: revealStrip },
        Region { item: globalDismiss },
        Region { item: maskTracker }
      ]
    }

    // A Region rebuilds only when its own item's x/y/width/height change, not
    // when an ancestor moves. The hitbox sits inside the card, which slides
    // in (anchors.bottomMargin) and moves with the alignment, so without this
    // zero-size follower the mask kept the card's hidden position from start
    // up and the dock got no pointer input. (Popups anchored to the card used
    // to trigger the rebuild by accident.)
    Item {
      id: maskTracker
      x: dockCardComp ? dockCardComp.x : 0
      y: dockCardComp ? dockCardComp.y : 0
      width: 0
      height: 0
    }

    // Bottom edge reveal strip — thin edge trigger with zero click-swallowing
    Item {
      id: revealStrip
      anchors.bottom: parent.bottom
      x: {
        var cardW = (dockCardComp && dockCardComp.dockCard.width > 0) ? dockCardComp.dockCard.width : Style.space(320)
        var targetW = Math.min(parent.width, cardW + Style.space(96))
        if (root.alignment === "left") return Style.gapsOut
        if (root.alignment === "right") return parent.width - targetW - Style.gapsOut
        return Math.round((parent.width - targetW) / 2)
      }
      width: {
        var cardW = (dockCardComp && dockCardComp.dockCard.width > 0) ? dockCardComp.dockCard.width : Style.space(320)
        return Math.min(parent.width, cardW + Style.space(96))
      }
      height: (root.autohide && !root.dockVisible) ? root.revealHeight : 0
      visible: height > 0

      HoverHandler {
        id: revealHover
        onHoveredChanged: root.syncVisibility()
      }

      // A drag reaching the edge reveals a hidden dock, like hovering does.
      DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: root.externalDragOver = true
        onExited: if (!dockCardComp.folderDropActive) root.externalDragOver = false
      }

      Rectangle {
        id: revealStripRect
        anchors.bottom: parent.bottom
        x: Math.round((parent.width - width) / 2)
        Behavior on x {
          NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
        width: revealHover.hovered ? Style.space(48) : Style.space(24)
        height: Style.space(3)
        radius: height / 2
        color: Util.alpha(Color.bar.text, revealHover.hovered ? 0.6 : 0.25)
        Behavior on width { NumberAnimation { duration: 150 } }
        Behavior on color { ColorAnimation { duration: 150 } }
      }
    }

    // Clears a drag released outside the card (popups dismiss through their focus grabs).
    Item {
      id: globalDismiss
      width: root.dockDragActive ? dockWindow.width : 0
      height: root.dockDragActive ? dockWindow.height : 0

      MouseArea {
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onReleased: function(mouse) {
          if (root.dragAppId !== "") {
            root.dragAppId = ""
            root.dropBeforeId = ""
            root.dropTargetAppId = ""
            root.dropTargetGroupId = ""
            root.dragSourceGroupId = ""
            root.dragRemoveArmed = false
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
    // Created only while open: idle popup windows cost a QQuickWindow each,
    // and several hidden ones next to the dock broke its hover handling.
    LazyLoader {
      id: folderStackLoader
      active: root.activeStackFolder !== "" && root.dockVisible

      DockPopupWindow {
        id: folderStackWindow
        dockRoot: root
        open: true
        centerX: root.activeStackX
        body: folderStackPopoverComp
        onDismissed: root.closeFolderStack()

        FolderPopup {
          id: folderStackPopoverComp
          rootRef: dockRoot   // not `root`: inside the menu that name is its own property
        }
      }
    }

    // ------------------------------------------------------------ App Group Popover
    // Created only while open: idle popup windows cost a QQuickWindow each,
    // and several hidden ones next to the dock broke its hover handling.
    LazyLoader {
      id: appGroupLoader
      active: root.activeAppGroupId !== "" && root.dockVisible

      DockPopupWindow {
        id: appGroupWindow
        dockRoot: root
        open: true
        centerX: root.activeAppGroupX
        body: appGroupPopupComp
        onDismissed: root.closeAppGroup()

        AppGroupPopup {
          id: appGroupPopupComp
          rootRef: dockRoot   // not `root`: inside the menu that name is its own property
          popupWindow: appGroupWindow
        }
      }
    }

    // ------------------------------------------------------------ context menu
    // Created only while open: idle popup windows cost a QQuickWindow each,
    // and several hidden ones next to the dock broke its hover handling.
    LazyLoader {
      id: contextMenuLoader
      active: root.contextAppId !== ""

      DockPopupWindow {
        id: contextMenuWindow
        dockRoot: root
        open: true
        centerX: root.contextX
        body: contextMenuComp
        onDismissed: root.closeContext()

        DockContextMenu {
          id: contextMenuComp
          rootRef: dockRoot   // not `root`: inside the menu that name is its own property
        }
      }
    }
  }

  // ------------------------------------------------------------ settings panel
  // Built on open and torn down on close, so it always lands on the output the
  // dock is on right now.
  LazyLoader {
    active: root.settingsPanelOpen && root.dockScreen !== null

    SettingsPanel {
      // Not `root`: inside SettingsPanel that name is its own property.
      rootRef: dockRoot
    }
  }
}
