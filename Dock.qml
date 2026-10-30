import QtQuick 6.11
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel
import "DockLabels.js" as DockLabels
import "DockLayout.js" as DockLayout
import "DockMotion.js" as DockMotion
import "components"
import "components/logic"
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
  // Sticky badge counts and their dedupe keys, persisted so a shell restart
  // resumes the same badges (README: counts stay until the app is focused).
  readonly property string badgePath: Quickshell.env("HOME") + "/.local/state/omarchy/omadock-badges.json"
  property bool _savingBadges: false

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

  function pickScreen() { return screenLogic.pickScreen(root) }

  readonly property var dockScreen: root.pickScreen()

  // The output's own scale (Hyprland's monitor scale, e.g. 1.5): the pixel
  // grid that pixel-exact drawing snaps to. Screen.devicePixelRatio reports
  // the rounded ratio (2 at 1.5), not the grid the window raster lands on,
  // so it cannot stand in for this number. HyprlandMonitor.scale reads 0
  // until the monitor list has been fetched, hence the refresh
  // (Component.onCompleted) and the fallback.
  //
  // HyprlandMonitor.scale also updates in place without notifying, Hyprland
  // emits no event when a monitor's scale changes, and Qt's rounded
  // Screen.devicePixelRatio carries no change signal at all — so the lookup
  // is driven from the things that do fire: the screen object quickshell
  // re-advertises on any output change (dockScreen) and Hyprland's monitor
  // events. The refresh's IPC reply lands asynchronously and silently, so
  // recheckOutputScale re-runs the lookup in a short burst until it has had
  // time to land.
  property int monitorRev: 0
  readonly property real outputScale: root.lookupOutputScale(root.monitorRev)
  onDockScreenChanged: root.recheckOutputScale()

  function lookupOutputScale(_rev) { return screenLogic.lookupOutputScale(root, _rev) }
  function recheckOutputScale() { return screenLogic.recheckOutputScale(root) }

  // Bounded burst, not a poll: stops on its own after two seconds.
  Timer {
    id: scaleRevBump
    interval: 250
    repeat: true
    property int ticks: 0
    onTriggered: {
      root.monitorRev++
      ticks++
      if (ticks >= 8) {
        stop()
        ticks = 0
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded" || event.name.startsWith("monitor")) {
        root.recheckOutputScale()
      }
    }
  }

  // ------------------------------------------------- multi-monitor
  // DockHost sets forcedScreenName to pin this dock to a monitor, isPrimary on
  // the one owning global side effects, and sharedState for a tile's origin monitor.
  property string forcedScreenName: ""
  property bool isPrimary: true
  property bool ipcEnabled: true
  property QtObject sharedState: null
  // Task status has one owner - the host's shared store; this is a read-only view of it.
  readonly property var taskMap: (root.sharedState ? root.sharedState.taskStatus : null) || ({})
  property bool multiMonitor: false
  property bool perMonitorApps: true
  readonly property bool filterByMonitor: root.perMonitorApps && root.forcedScreenName !== ""

  function monitorNameForWorkspace(target) { return screenLogic.monitorNameForWorkspace(root, target) }
  function monitorNameForHypr(h) { return screenLogic.monitorNameForHypr(root, h) }
  function isHyprOnThisMonitor(h) { return screenLogic.isHyprOnThisMonitor(root, h) }
  function isToplevelOnThisMonitor(top) { return screenLogic.isToplevelOnThisMonitor(root, top) }

  onFilterByMonitorChanged: modelTimer.restart()

  property bool _syncingShared: false
  onMinimizedOriginsChanged: root.pushSharedState()
  onParkedAtChanged: root.pushSharedState()
  onParkSlotsChanged: root.pushSharedState()
  onSharedStateChanged: root.pullSharedState()

  function pushSharedState() { return screenLogic.pushSharedState(root) }
  function pullSharedState() { return screenLogic.pullSharedState(root) }

  Connections {
    target: root.sharedState
    function onMinimizedOriginsChanged() { root.pullSharedState() }
    function onParkedAtChanged() { root.pullSharedState() }
    function onParkSlotsChanged() { root.pullSharedState() }
  }

  function screenForName(name) { return screenLogic.screenForName(root, name) }

  readonly property var appLibrary: (shell && shell.appLibrary) ? shell.appLibrary : localAppLibrary

  // <id>Ref aliases expose this file's ids to extracted logic modules
  // (dockWindowRef above is the same mechanism, declared as an alias).
  readonly property var appDropCheckRef: appDropCheck
  readonly property var customFolderPickerProcRef: customFolderPickerProc
  readonly property var dockFileRef: dockFile
  readonly property var dropFolderCheckRef: dropFolderCheck
  readonly property var dropFolderProbeRef: dropFolderProbe
  readonly property var ejectProcRef: ejectProc
  readonly property var folderStackScannerRef: folderStackScanner
  readonly property var launchPruneTimerRef: launchPruneTimer
  readonly property var modelTimerRef: modelTimer
  readonly property var urgentSettleTimerRef: urgentSettleTimer
  readonly property var removableDrivesScannerRef: removableDrivesScanner
  readonly property var scaleRevBumpRef: scaleRevBump
  readonly property var terminalHostDebounceRef: terminalHostDebounce
  readonly property var themeChangeTimerRef: themeChangeTimer
  readonly property var themeIconsFileRef: themeIconsFile
  readonly property var debounceOverlapTimerRef: debounceOverlapTimer
  readonly property var hideTimerRef: hideTimer
  readonly property var menuPresetTimerRef: menuPresetTimer
  readonly property var noWarpProcRef: noWarpProc
  readonly property var notificationBadgeTimerRef: notificationBadgeTimer
  readonly property var revealHoverRef: revealHover
  readonly property var revealTimerRef: revealTimer
  readonly property var themeFileReloadRef: themeFileReload
  readonly property var badgeFileRef: badgeFile
  readonly property var badgeSaveDebounceRef: badgeSaveDebounce
  readonly property var configFileRef: configFile
  // ------------------------------------------------------ logic modules
  DockConfigLogic { id: configLogic }
  DockWindowLogic { id: windowLogic }
  DockSlotLogic { id: slotLogic }
  DockEventLogic { id: eventLogic }
  DockGroupsLogic { id: groupsLogic }
  DockNotifLogic { id: notifLogic }
  DockFolderLogic { id: folderLogic }
  DockSettingsLogic { id: settingsLogic }
  DockPinLogic { id: pinLogic }
  DockContextLogic { id: contextLogic }
  DockScreenLogic { id: screenLogic }
  DockStyleLogic { id: styleLogic }
  DockStateLogic { id: stateLogic }
  DockPersistLogic { id: persistLogic }
  DockGroupCycleLogic { id: groupCycleLogic }
  DockLabelLogic { id: labelLogic }
  DockFitHost { id: fitHost; dockRoot: root; rivals: [stackLife, groupLife, contextLife] }
  readonly property var fitHostRef: fitHost

  // Fallback standalone application library for host capability gates (e.g. Omarchy 4.x scoped plugins)

  LocalAppLibrary {
    id: localAppLibrary
    rootRef: root
  }

  // Launch wrapper: one-shot, event-driven (a failed gtk-launch probe exits
  // in milliseconds), so this adds zero idle CPU. A non-zero exit means the
  // desktop file no longer resolves and the user gets told about it.
  Process {
    id: launchProc
    property string pendingName: ""
    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0 && launchProc.pendingName !== "")
        root.notifyAppMissing(launchProc.pendingName, "launch")
      launchProc.pendingName = ""
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
    if (root.appLibrary === localAppLibrary) localAppLibrary.refreshIcons()
    // Fills HyprlandMonitor.scale for outputScale.
    root.recheckOutputScale()
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
  // On always-on label plates the zoom stays inside the plate's margin.
  readonly property real zoomPeak: root.labelPlates ? 1.1 : 1.22
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
  // Art and indicators sit this much above the band's centring, so the
  // art's top margin matches the room under the indicators.
  readonly property real indicatorLift: Style.spaceReal(1.5)
  // Distance from the slot's bottom edge to the bottom of the artwork.
  // With indicators beside the art on label plates, the art is centred.
  readonly property real iconArtBottom: root.labelSideMarks ? Math.round((root.iconSlot - root.baseIconArt) / 2)
    : Math.round(root.indicatorBand + (root.iconSlot - root.indicatorBand - root.baseIconArt) / 2) + root.indicatorLift
  // Vertical offset of the artwork's centre from the slot's centre, for
  // things centred on the row (separators, preview tiles).
  readonly property real iconCenterOffset: -root.indicatorBand / 2

  // The card's own handler in dockCard-local coordinates.
  readonly property real pointerX: cardHover.hovered
    ? cardHover.point.position.x - dockCardComp.rowOffset
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
  function visibleRunningSlotBefore(idx) { return styleLogic.visibleRunningSlotBefore(root, idx) }
  // Pinned-group | running divider. Sits after the tile section when tiles
  // exist, so it doubles as the right tile divider.
  readonly property bool hasSeparator: (root.pinnedSection.length > 0 || root.hasTiles) && root.visibleRunningCount > 0
  readonly property real gapWidth: fitHost.plan.t < 1 ? fitHost.plan.gap : (root.labelPlates ? root.plateSpacing.gap : Style.space(root.itemSpacing))
  // Split sections turn each separator into the gap between two panels. Each
  // panel reaches the card padding past its outer icons, so the separator
  // slot is sized to leave the chosen visible gap between the panels.
  readonly property real sectionGap: Style.space(root.sectionSpacing) * Math.min(1, fitHost.plan.t)
  // Without the split, a divider's slot gets half the margin an icon has
  // inside its own slot on each side. Squeezed against its neighbours, the
  // line made every difference in icon width show; with the full margin it
  // stood too far apart. Half sits between the two. Hidden takes the slot
  // and its spacing out (-gapWidth): the sections meet one gap apart.
  readonly property real separatorWidth: root.placement.split ? Math.max(Style.space(1), root.sectionGap + 2 * root.baseRowLeft - 2 * root.gapWidth)
    : root.dividerStyle === "none" ? -root.gapWidth : root.labelPlates ? root.plateSpacing.separator : Style.space(1) + Math.round((root.iconSlot - root.baseIconArt) / 2)
  readonly property int groupSlots: (root.appGroups && DockModel.isList(root.appGroups)) ? root.appGroups.length : 0
  // Folders and buttons share the folder section, so they share its slot count.
  readonly property int folderSlots: (root.pinnedFolders ? root.pinnedFolders.length : 0)
    + (root.pinnedButtons ? root.pinnedButtons.length : 0)
  readonly property int driveSlots: (root.showRemovableDrives && root.mountedDrives) ? root.mountedDrives.length : 0
  readonly property bool hasFolderSeparator: (root.folderSlots > 0 || root.driveSlots > 0) && (root.pinnedSection.length > 0 || root.groupSlots > 0 || root.hasTiles || root.visibleRunningCount > 0)
  // Folders | drives divider: drives come and go with the hardware, so they
  // get a section of their own instead of trailing the pinned folders.
  readonly property bool hasDriveSeparator: root.folderSlots > 0 && root.driveSlots > 0

  // Minimized-window preview tiles (DockStyleLogic.tileModel).
  readonly property var tileModel: styleLogic.tileModel(root)
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

  function slotHomeCenter(elementIndex, slotsBefore, sepCount, extraLeftWidth, ownLabel) { return styleLogic.slotHomeCenter(root, elementIndex, slotsBefore, sepCount, extraLeftWidth, ownLabel) }

  // Width the tile section consumes ahead of elements that follow it,
  // including its left divider.
  readonly property real tilesFixedWidth: root.hasTiles
    ? (root.hasLeftTileSeparator ? root.separatorWidth : 0) + root.tileCount * root.tileWidth
    : 0
  readonly property int tileElements: root.hasTiles ? root.tileCount : 0

  function magnifyAt(homeCenter) { return styleLogic.magnifyAt(root, homeCenter) }
  function magnifyScaleAt(homeCenter) { return styleLogic.magnifyScaleAt(root, homeCenter) }
  function waveOffsetAt(homeCenter) { return styleLogic.waveOffsetAt(root, homeCenter) }

  // ------------------------------------------------- contrast

  function isLight(value) { return styleLogic.isLight(root, value) }

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
    if (root.placement.panel) return 0
    if (root.dockShape === "round" || root.dockShape === "pill") return Math.round(h / 2)
    if (root.dockShape === "square") return 0
    if (root.dockShape === "theme" || root.dockShape === "auto") {
      var n = Style.cornerRadius
      return (typeof n === "number" && isFinite(n) && n >= 0) ? n : Math.max(14, Style.space(14))
    }
    return root.roundedRadius
  }

  function cardRadius(height) { return styleLogic.cardRadius(root, height) }

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
  readonly property int baseIconSize: root.configuredIconSize > 0 ? root.configuredIconSize : Math.max(28, Math.round(Style.bar.sizeHorizontal * 0.9))
  readonly property int iconSize: fitHost.plan.iconSize > 0 ? Math.min(root.baseIconSize, fitHost.plan.iconSize) : root.baseIconSize
  readonly property int iconSlot: root.labelPlates ? DockLabels.gridInt(root.iconSize + Style.space(10), root.outputScale) : root.iconSize + Style.space(10)

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
    - root.edgeGap - (dockCardComp ? dockCardComp.dockCard.height : 0) - Style.space(16))
  // Live scan of parked windows for the preview-tile section. Built straight
  // off Hyprland's own toplevel list, so it cannot go stale the way cached
  // model primitives can.
  property var minimizedWindows: []
  property string _minimizedSig: ""
  readonly property var pinnedSection: root.dockModel.pinned || []
  // Pinned apps and app groups in dock order (DockModel.pinnedRow).
  readonly property var pinnedRow: DockModel.pinnedRow(root.pinnedSection, root.appGroups)

  function pinnedRowKey(item) { return styleLogic.pinnedRowKey(root, item) }
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
  // Every entry a notification may be attributed to: pinned, unpinned
  // running, and foldered (grouped) apps alike.
  readonly property var notifEntries: root.pinnedSection.concat(root.runningSection).concat(root.groupedSection || [])

  // Model rebuilds are also the moment to re-read window rectangles: the tiling
  // places are computed from them.
  function refreshDock() {
    var result = stateLogic.refreshDock(root)
    root.refreshClientRects()
    return result
  }
  function rescanMinimizedWindows() { return stateLogic.rescanMinimizedWindows(root) }

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
  onActiveWindowAddressChanged: {
    if (root.activeWindowAddress) root.clearUrgentApp(root.activeId, root.activeWindowAddress)
    root.rememberFocus(root.activeWindowAddress)
  }

  // Window addresses by recency of focus, newest first. Parking hands focus to
  // the newest entry still standing, so a park can never leave the keyboard
  // inside the parking lot. Bounded; addresses vanish when their windows do.
  property var focusOrder: []

  function rememberFocus(addr) { return stateLogic.rememberFocus(root, addr) }

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
  // Where each parked window sat, and the queue of windows still waiting to win
  // their place back. See DockSlotLogic.
  property var parkSlots: ({})
  property var pendingSlotFixes: []
  // The window the user restored: focus returns to it once the layout work is
  // done, since reshaping has to focus other windows on the way.
  property string slotFixFocus: ""
  // Window rectangles, read from Hyprland in one shot: Quickshell's per-toplevel
  // ipc object only carries at/size for windows that existed at shell start.
  property var clientRects: ({})
  property var urgentMap: ({})
  property var pendingUrgent: ({}) // held by urgentSettleTimer (DockEventLogic)
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

  // Pinned slots that run a command instead of opening a folder (Buttons.js):
  // rendered by the folder section, after the folders.
  property var pinnedButtons: []
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
  // The last scan stopped at its entry budget (the folder holds more), or
  // could not read the folder at all (timeout, unreadable).
  property bool activeStackTruncated: false
  property bool activeStackFailed: false
  property real activeStackX: 0
  property string contextFolderPath: ""
  property string contextFolderName: ""
  // The folder-section menu opened from a command button: a button has no path
  // to rename, list or open, so the menu keeps only the rows that apply.
  property bool contextIsButton: false
  property string contextButtonCommand: ""

  // ------------------------------------------------- removable drives state
  property bool showRemovableDrives: true
  // Warn when a drive is pulled out while still mounted.
  property bool warnUnsafeRemoval: true
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
  property bool contextRenaming: false     // a context-menu name field has the keyboard

  // ------------------------------------------------- configuration options

  property string alignment: "center" // "center" | "left" | "right" | "spread"
  property string layout: "dock"      // "dock" | "panel" (DockLayout.js)
  // What the dock draws: { panel, split, align } (DockLayout.placement).
  readonly property var placement: DockLayout.placement(root.layout, root.alignment, root.splitSections, root.folderSlots + root.driveSlots > 0)
  // Margin between the card and the screen edge; the panel sits on it.
  readonly property real edgeGap: root.placement.panel ? 0 : Style.gapsOut
  // The shell's own gap to the screen edge (Hyprland's gaps_out / 2), 0 on a
  // desktop that runs edge to edge. Read-only, reported by `state` so the live
  // tests can tell what the panel had to gain over the dock.
  readonly property real outerGap: Style.gapsOut

  property bool autohide: true
  property bool intelligentAutohide: true
  readonly property FloatingDockWatch floatingWatch: FloatingDockWatch { dockRoot: root }
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
    motion: root.motion,
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
  readonly property var themeGradientColors: styleLogic.themeGradientColors(root, themeColorsFile.text)

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
  // same accent would otherwise vanish into it. On a label plate: the same against the plate.
  readonly property color iconTintColor: root.tintFor(root.iconTint, root.dockForeground, root.iconBackdropColor)
  readonly property color plateIconTintColor: labelLogic.plateIconTint(root)

  function tintFor(mode, textColor, backdrop) { return styleLogic.tintFor(root, mode, textColor, backdrop) }
  function blackOrWhiteOn(backdrop) { return styleLogic.blackOrWhiteOn(root, backdrop) }

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

  function luminance(c) { return styleLogic.luminance(root, c) }
  function contrastRatio(a, b) { return styleLogic.contrastRatio(root, a, b) }
  function readableOn(color, backdrop) { return styleLogic.readableOn(root, color, backdrop) }
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

  function symbolicColorOn(backdrop) { return styleLogic.symbolicColorOn(root, backdrop) }
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
  // Where a parked window comes back: the workspace you are on, or the one it was
  // parked from. Windows puts a minimized window back where it was.
  property string restoreWorkspace: "current"
  // Whether the window also wins back the place it held in the tiling layout.
  property bool restoreSlot: false
  // Hyprland warps the pointer into a window it activates (and on workspace
  // switches); keepPointer suppresses that for focus changes the dock makes.
  property bool keepPointer: true
  property string animations: "full"      // full | reduced | off (DockMotion)
  readonly property var motion: DockMotion.plan(root.animations)
  readonly property bool clickToMinimize: root.minimizeMode !== "off"
  property bool showUrgentHint: true
  property bool urgentOnNotification: true
  // ---- name labels beside the icons (DockLabelLogic, DockLabels.js)
  property string labelMode: "off"        // off | always | hover
  property string labelKind: "all"        // all | apps | groups | folders
  property string labelFont: "theme"      // theme | sans | pixel
  property string labelSize: "medium"     // small | medium | large
  property string labelWeight: "medium"   // regular | medium | bold
  property string labelColor: "auto"      // auto | theme | accent
  property string labelBackground: "none" // none | pill | plate
  property string labelShape: "dock"      // dock | pill | rounded | square
  property string labelIndicators: "before" // before | after | under (always-on plates)
  property string labelPlateHeight: "icon"  // icon | dock (always-on plates)
  property string labelPinned: "always"     // always | running (always-on names of pinned apps)
  readonly property bool labelPlates: root.labelMode === "always" && root.labelBackground === "plate"
  readonly property var plateSpacing: labelLogic.plateSpacing(root)
  readonly property bool labelSideMarks: DockLabels.sideMarks(root.labelMode, root.labelBackground, root.labelIndicators)
  property string labelReveal: "slide"    // slide | typewriter | scramble
  property string labelEffect: "none"     // none | glow | outline
  property int labelMaxWidth: 140
  property var labelNames: ({})           // appId -> the user's label text
  property var labelExtras: ({})          // slot -> { owner, width } (DockLabels.withExtra)
  property int labelsOpen: 0              // hover-mode labels open or closing

  property bool showNotificationBadges: true
  // Badge look: what the pill carries, which corner it sits on, its colour.
  property string badgeStyle: "count"
  property string badgePosition: "top-right"
  property string badgeColor: "accent"
  readonly property color badgeFill: root.badgeColor === "urgent" ? Color.urgent
    : root.badgeColor === "neutral" ? Color.bar.text
    : Color.accent
  readonly property color badgeInk: root.badgeColor === "neutral" ? Color.bar.background
    : (root.isLight(root.badgeFill) ? "#12100f" : "#f2efec")
  property var notificationBadges: ({})
  property var notificationPopupRows: []
  // Sticky-badge dedupe: row keys already counted, oldest evicted at 512.
  property var _notifSeenKeys: ({})
  property var _notifSeenOrder: []
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
  Timer { id: urgentSettleTimer; interval: 150; onTriggered: eventLogic.commitUrgent(root) }

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
          if (stateLogic.applyTerminalIdentities(root, text)) modelTimer.restart()
        } catch (e) {
          console.warn("[omadock] Failed resolving terminal and CLI identities:", e)
        }
      }
    }
  }

  readonly property var modelSettleTimerRef: modelSettleTimer

  // One-shot deferred rebuild after park/restore moves and configreloaded events,
  // so model state is re-frozen once Hyprland handles settle.
  Timer {
    id: modelSettleTimer
    interval: 300
    onTriggered: root.refreshDock()
  }

  // Slot recovery after a restore: Hyprland inserts the window home as a new tiling
  // window, so its recorded place is won back with a swap. The layout settles a beat
  // after the move, hence the delay; every window gets a few passes, then the dock
  // stops rather than fight a layout the user changed while the window was parked.
  Timer {
    id: slotFixTimer
    interval: 180
    repeat: false
    onTriggered: {
      if (slotLogic.runSlotFixes(root) > 0) restart()
    }
  }

  // One shot, on demand: window rectangles for the tiling-place bookkeeping.
  Process {
    id: clientRectsProc
    command: ["hyprctl", "-j", "clients"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: root.clientRects = slotLogic.parseClientRects(root, this.text)
    }
  }

  function refreshClientRects() {
    if (clientRectsProc.running) return
    clientRectsProc.running = true
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

        var cardW = (dockCard && dockCard.width > 0) ? (dockCard.width + root.edgeGap * 2) : 320
        var cardH = (dockCard && dockCard.height > 0) ? (dockCard.height + root.edgeGap * 2) : 60
        var monX = (mon && typeof mon.x === "number") ? mon.x : 0
        var monY = (mon && typeof mon.y === "number") ? mon.y : 0
        var cardX = dockCardComp ? dockCardComp.x : ((screenLogicalW - cardW) / 2)
        var dockLeft = monX + cardX
        var dockRight = dockLeft + cardW
        var dockTop = monY + screenLogicalH - cardH - root.edgeGap
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
          root.applyStackScan(parsed.items || [], parsed.count || 0, parsed.truncated === true, false)
        } catch (e) {
          console.warn("[omadock] Failed parsing folder scan:", e)
          // Empty output: the helper timed out or died (a stalled mount).
          root.applyStackScan([], 0, false, true)
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
          root.toggleFolderPin(relPath, baseName, "")
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

  function pickCustomFolder() { return folderLogic.pickCustomFolder(root) }
  function scanRemovableDrives() { return folderLogic.scanRemovableDrives(root) }
  function openDriveContext(dev, mp, name, space, cx, cy) { return folderLogic.openDriveContext(root, dev, mp, name, space, cx, cy) }
  function ejectDrive(dev, mountpoint, name) { return folderLogic.ejectDrive(root, dev, mountpoint, name) }
  function setDockAlignment(align) { return stateLogic.setDockAlignment(root, align) }
  function setDockPosition(pos) { return stateLogic.setDockPosition(root, pos) }
  function setDockLayout(l) { return stateLogic.setDockLayout(root, l) }

  function openAppGroup(gdata, cx, cy) { return groupsLogic.openAppGroup(root, gdata, cx, cy) }

  function closeAppGroup() { return groupsLogic.closeAppGroup(root) }

  function openAppGroupContext(gdata, cx, cy) { return groupsLogic.openAppGroupContext(root, gdata, cx, cy) }

  function createAppGroupFromRunning() { return groupsLogic.createAppGroupFromRunning(root) }

  function createAppGroupFromDrop(targetAppId, draggedAppId) { return groupsLogic.createAppGroupFromDrop(root, targetAppId, draggedAppId) }

  function addAppToGroup(groupId, appId) { return groupsLogic.addAppToGroup(root, groupId, appId) }

  function updateAppGroupName(groupId, newName) { return groupsLogic.updateAppGroupName(root, groupId, newName) }

  function renameAppGroup(groupId, newName) { return groupsLogic.renameAppGroup(root, groupId, newName) }

  function updateAppGroupColumns(groupId, cols) { return groupsLogic.updateAppGroupColumns(root, groupId, cols) }

  function removeAppFromGroup(groupId, appId, insertBeforeId) { return groupsLogic.removeAppFromGroup(root, groupId, appId, insertBeforeId) }

  function ungroupAppGroup(groupId) { return groupsLogic.ungroupAppGroup(root, groupId) }

  function removeAppGroup(groupId) { return groupsLogic.removeAppGroup(root, groupId) }

  function syncVisibility() { return stateLogic.syncVisibility(root) }

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
  // depth on the accepted slice. Reload cycles are debounced (a rename from
  // our own atomic write wakes the watcher too, so the debounce coalesces it
  // with outside edits; _savingConfig skips a read landing mid-save, and a
  // read older than a write is CappedFileView's to hold back).

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

  // Own written state, loaded once at startup; nothing external edits it, so
  // it is not watched (our own writes cannot echo back as reloads).
  CappedFileView {
    id: badgeFile
    path: root.badgePath
    maxBytes: DockModel.MAX_BADGE_BYTES
    watchChanges: false
    onLoaded: root.loadBadgeState()
  }

  // Bumps and clears can arrive in bursts; one save settles them.
  Timer {
    id: badgeSaveDebounce
    interval: 400
    repeat: false
    onTriggered: root.flushBadgeState()
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
    function onShellValuesChanged() { root.handleShellThemeChanged() }
    function onForegroundChanged() { root.handleShellThemeChanged() }
    function onAccentChanged() { root.handleShellThemeChanged() }
  }

  function handleShellThemeChanged() { return stateLogic.handleShellThemeChanged(root) }

  Timer {
    id: themeFileReload
    interval: 50
    onTriggered: {
      themeIconsFile.reload()
      themeColorsFile.reload()
    }
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
      return eventLogic.handleRawEvent(root, event)
    }
  }

  function updateNotifService() { return notifLogic.updateNotifService(root) }

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

  function loadBadgeState() { return persistLogic.loadBadgeState(root) }

  function scheduleBadgeSave() { return persistLogic.scheduleBadgeSave(root) }

  function flushBadgeState() { return persistLogic.flushBadgeState(root) }

  function processNotifRowSticky(row) { return notifLogic.processNotifRowSticky(root, row) }

  function refreshNotificationBadges() { return notifLogic.refreshNotificationBadges(root) }

  // Overlay plugins may not receive the first-party notification service.
  // The shell's active-popup files offer a read-only, event-driven fallback,
  // for the badges and for urgency on a new notification.
  property bool _popupWatchPrimed: false
  Process {
    id: notificationPopupWatch
    running: (root.showNotificationBadges || (root.showUrgentHint && root.urgentOnNotification)) && !root.notifService
    // The first snapshot after (re)start only records what is already up,
    // so a shell restart does not bounce apps for old popups.
    onRunningChanged: if (!running) root._popupWatchPrimed = false
    command: ["python3", decodeURIComponent(Qt.resolvedUrl("scripts/notification-popups.py").toString().replace(/^file:\/\//, ""))]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        try {
          var rows = JSON.parse(line)
          var next = Array.isArray(rows) ? rows : []
          var fresh = root._popupWatchPrimed ? DockModel.newPopupRows(root.notificationPopupRows, next) : []
          root._popupWatchPrimed = true
          root.notificationPopupRows = next
          notificationBadgeTimer.restart()
          if (root.showUrgentHint && root.urgentOnNotification)
            for (var i = 0; i < fresh.length; i++) root.handleNotificationReceived(fresh[i])
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

  function handleNotificationReceived(row) { return notifLogic.handleNotificationReceived(root, row) }

  Connections {
    target: root.notifService ? root.notifService.popupModel : null
    function onRowsInserted(parent, first, last) {
      notificationBadgeTimer.restart()
      var wantUrgent = root.showUrgentHint && root.urgentOnNotification
      for (var i = first; i <= last; i++) {
        var row = root.notifService.popupModel.get(i)
        if (!row) continue
        // Counted here, not on the timer: a popup that expires before the
        // debounce still leaves its sticky badge.
        root.processNotifRowSticky(row)
        if (wantUrgent) root.handleNotificationReceived(row)
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
        if (row) {
          root.processNotifRowSticky(row)
          root.handleNotificationReceived(row)
        }
      }
    }
  }

  onShellChanged: {
    root.updateNotifService()
    root.rescanApps()
  }
  onPinnedIdsChanged: root.refreshDock()

  // ------------------------------------------------- functions

  function loadPinned() { return persistLogic.loadPinned(root) }

  function applyLook(parsed) { configLogic.applyLook(root, parsed) }

  function loadConfig() { configLogic.loadConfig(root, configFile.text) }

  function rescanApps() { return contextLogic.rescanApps(root) }

  // Up to five sources report one theme switch (three Color signals, the
  // icon theme file, the colors file); each used to rescan apps and rebuild
  // the dock. After the first load they coalesce into one run once the
  // burst is over; the first load applies at once so icons do not flash.
  property bool _themeApplied: false
  function handleThemeChanged() { return contextLogic.handleThemeChanged(root) }

  Timer {
    id: themeChangeTimer
    interval: 100
    onTriggered: root.applyThemeChange()
  }

  function applyThemeChange() { return contextLogic.applyThemeChange(root) }

  function folderColorLabel(colorId) { return contextLogic.folderColorLabel(root, colorId) }

  function setFolderColor(color) { return contextLogic.setFolderColor(root, color) }

  function openDockSettingsMenu(x, y) { return contextLogic.openDockSettingsMenu(root, x, y) }

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

  function applyBlurRule(force) { return settingsLogic.applyBlurRule(root, force) }

  // Global blur size the dock asks for while blur is "on"; 0 leaves it alone.
  property int blurSize: 0
  // Hyprland's own blur size, captured before the first override so it can be
  // restored; persisted, since the override outlives a shell restart.
  property int systemBlurSize: 0
  property int _appliedBlurSize: 0

  function setHyprBlurSize(size) { return settingsLogic.setHyprBlurSize(root, size) }

  function applyBlurSize(force) { return settingsLogic.applyBlurSize(root, force) }

  function setBlurSize(size, currentSize) { return settingsLogic.setBlurSize(root, size, currentSize) }

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

  function previewDraggedFolder(urls) { return pinLogic.previewDraggedFolder(root, urls) }

  Process {
    id: dropFolderProbe
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        if (root.externalDragOver && line) root.dropCandidatePath = String(line)
      }
    }
  }

  function insertFolderPin(path, name, icon, index) { return pinLogic.insertFolderPin(root, path, name, icon, index) }

  // Local filesystem path of a helper in scripts/.
  function scriptPath(name) {
    return decodeURIComponent(Qt.resolvedUrl("scripts/" + name).toString().replace(/^file:\/\//, ""))
  }

  function localPathsFromUrls(urls) { return pinLogic.localPathsFromUrls(root, urls) }

  function pinDroppedFolders(urls) { return pinLogic.pinDroppedFolders(root, urls) }

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
        root.insertFolderPin(relPath, chosen.split("/").pop() || "Folder", "", dropFolderCheck.insertAt)
        if (dropFolderCheck.insertAt >= 0) dropFolderCheck.insertAt++
      }
    }
  }

  function mediaPlayerFor(appId) { return pinLogic.mediaPlayerFor(root, appId) }
  function isMicActiveFor(appId) { return pinLogic.isMicActiveFor(root, appId) }
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

  function desktopIdFor(appId) { return pinLogic.desktopIdFor(root, appId) }

  function beginAppDrop(appId, urls) { return pinLogic.beginAppDrop(root, appId, urls) }

  function endAppDrop(appId) { return pinLogic.endAppDrop(root, appId) }

  function dropOnApp(appId) { return pinLogic.dropOnApp(root, appId) }

  function openFilesWith(appId, paths) { return pinLogic.openFilesWith(root, appId, paths) }

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

  function setBlurMode(mode) { return settingsLogic.setBlurMode(root, mode) }

  function openSettingsPanel() { return stateLogic.openSettingsPanel(root) }

  function closeSettingsPanel() { return stateLogic.closeSettingsPanel(root) }

  function setOption(key, value) { return settingsLogic.setOption(root, key, value) }
  function setDividerStyle(style) { return settingsLogic.setDividerStyle(root, style) }
  function setShowBorder(show) { return settingsLogic.setShowBorder(root, show) }
  function setDockScreen(name) { return settingsLogic.setDockScreen(root, name) }
  function setAutohideMode(mode) { return settingsLogic.setAutohideMode(root, mode) }
  function setDockOpacity(val) { return settingsLogic.setDockOpacity(root, val) }
  function setBorderOpacity(val) { return settingsLogic.setBorderOpacity(root, val) }
  function setHoverEffect(mode) { return settingsLogic.setHoverEffect(root, mode) }
  function setDockShape(shape) { return settingsLogic.setDockShape(root, shape) }
  function setDockBgColor(col) { return settingsLogic.setDockBgColor(root, col) }
  function setIconSize(sz) { return settingsLogic.setIconSize(root, sz) }
  function setItemSpacing(sp) { return settingsLogic.setItemSpacing(root, sp) }
  function setUrgentSoundName(name) { return settingsLogic.setUrgentSoundName(root, name) }

  // ------------------------------------------------- window plumbing

  function hyprToplevelFor(toplevel) { return windowLogic.hyprToplevelFor(root, toplevel) }
  function windowAddress(handle) { return windowLogic.windowAddress(root, handle) }
  function luaString(value) { return windowLogic.luaString(root, value) }
  function hyprDispatch(lua, legacy) { return windowLogic.hyprDispatch(root, lua, legacy) }

  // Runs action with Hyprland's pointer warps switched off. Activation goes
  // over Wayland and workspace switches over the IPC socket, so the setting
  // has to land first: the actions wait for hyprctl to exit. The compositor
  // restores the user's no_warps value on its own timer, which survives a
  // shell crash; repeated calls extend the window instead of saving "true".
  property var pendingNoWarpActions: []

  // modelTimer lives in this file; extracted logic modules rebuild the model
  // through this indirection instead of referencing the timer id directly.
  function modelTimerRestart() { modelTimer.restart() }

  // App-group member preview: scroll cycling + click-to-focus (hover bubble)
  function groupCycleFront(key, windows, frontIndex, angleDelta) { return groupCycleLogic.cycleFront(root, key, windows, frontIndex, angleDelta) }
  function focusPreviewedWindow(windows, frontIndex) { return groupCycleLogic.focusPreviewed(root, windows, frontIndex) }

  // Name labels: rendering policy and the per-slot width registry
  function labelStyle(kind) { return labelLogic.style(root, kind) }
  function labelFillFor(ink, hover) { return labelLogic.fillFor(root, ink, hover) }
  function labelPlateBox(tileH) { return labelLogic.plateBox(root, tileH) }
  function labelName(appId, name) { return labelLogic.displayName(root, appId, name) }
  function labelTooltipNeeded(kind, wins, hint, shortened) { return labelLogic.tooltipNeeded(root, kind, wins, hint, shortened) }
  function labelExtraBefore(slot, ownLabel) { return labelLogic.extraBefore(root, slot, ownLabel) }
  function setLabelExtra(slot, owner, width, before) { labelLogic.setExtra(root, slot, owner, width, before) }
  function setLabelName(appId, name) { labelLogic.setName(root, appId, name) }
  function labelNameRows() { return labelLogic.nameRows(root) }

  function withoutPointerWarp(action) { return stateLogic.withoutPointerWarp(root, action) }

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

  function workspaceTarget(workspace) { return windowLogic.workspaceTarget(root, workspace) }

  function liveToplevelForAddress(addr) { return windowLogic.liveToplevelForAddress(root, addr) }

  function liveHyprToplevelForAddress(addr) { return windowLogic.liveHyprToplevelForAddress(root, addr) }

  function focusWindowByAddress(addr, appId) { return windowLogic.focusWindowByAddress(root, addr, appId) }

  function focusToplevel(toplevel, appId) { return windowLogic.focusToplevel(root, toplevel, appId) }

  function minimizeToplevel(topOrAddr, focusNext, appId) { return windowLogic.minimizeToplevel(root, topOrAddr, focusNext, appId) }

  function standingWindowAfterPark(exceptAddress) { return windowLogic.standingWindowAfterPark(root, exceptAddress) }

  function handoffFocusAfterPark(address, focusNext, appId) { return slotLogic.handoffFocusAfterPark(root, address, focusNext, appId) }

  function restoreWindow(targetRef, appId, useOrigin) { return windowLogic.restoreWindow(root, targetRef, appId, useOrigin) }

  // One specific parked window: the minimize toggle's second press restores exactly
  // what its first press parked. Always the recorded origin.
  function restoreAddress(address) { return windowLogic.restoreWindow(root, address, "", true) }

  // Recorded-place bookkeeping: the timer stays here, the logic in
  // DockSlotLogic (which other modules reach through these).
  function scheduleSlotFix(address) { return slotLogic.scheduleSlotFix(root, address, slotFixTimer) }

  function dropParkSlot(address) { return slotLogic.dropParkSlot(root, address) }

  function recordParkSlot(address, origin) { return slotLogic.recordParkSlot(root, address, origin) }

  function restoreWindowBatch(wins, primaryAddress, useOrigin) { return windowLogic.restoreWindowBatch(root, wins, primaryAddress, useOrigin) }

  function liveWsNameOf(win) { return windowLogic.liveWsNameOf(root, win) }

  function isWinParkedLive(win) { return windowLogic.isWinParkedLive(root, win) }

  function windowByAddress(windows, address) { return windowLogic.windowByAddress(root, windows, address) }

  function visibleWindows(windows) { return windowLogic.visibleWindows(root, windows) }

  function focusedIndex(windows) { return windowLogic.focusedIndex(root, windows) }

  function windowHere(windows) { return windowLogic.windowHere(root, windows) }

  // Turns wheel events into steps: -1 (up), 1 (down) or 0. High-resolution
  // wheels send many small deltas per notch, so deltas add up to a full notch
  // (120) first, and a step needs wheelStepDelay since the previous one,
  // which also tames free-spinning wheels. Leftovers are dropped rather than
  // queued. Each wheel target keeps its own state under key.
  property var wheelState: ({})

  function wheelStep(key, angleDelta) { return windowLogic.wheelStep(root, key, angleDelta) }

  function stepWindow(windows, direction) { return windowLogic.stepWindow(root, windows, direction) }

  function parkedWindows(windows) { return windowLogic.parkedWindows(root, windows) }

  function recentParked(parked) { return windowLogic.recentParked(root, parked) }

  function oldestParked(parked) { return windowLogic.oldestParked(root, parked) }

  function recentWindow(appId, windows) { return windowLogic.recentWindow(root, appId, windows) }

  function minimizeAllWindows(entry) { return windowLogic.minimizeAllWindows(root, entry) }

  function minimizeOneWindow(entry) { return windowLogic.minimizeOneWindow(root, entry) }

  function minimizeApp(entry) { return windowLogic.minimizeApp(root, entry) }

  function pruneWindowState() { return notifLogic.pruneWindowState(root) }

  function keepUrgentLive(map, live) { return notifLogic.keepUrgentLive(root, map, live) }

  function clearNotificationBadgesFor(appId, address) { return notifLogic.clearNotificationBadgesFor(root, appId, address) }

  function clearUrgentApp(appId, address) { return notifLogic.clearUrgentApp(root, appId, address) }

  function keepLive(map, live, byValue) { return notifLogic.keepLive(root, map, live, byValue) }

  function minimizeActive() { return windowLogic.minimizeActive(root) }

  function restoreLast() { return windowLogic.restoreLast(root) }

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

    // Brings back one specific parked window: the minimize/restore key toggle
    // restores exactly the window its first press parked. Always the recorded
    // origin, so the window also wins its tiling place back.
    function restoreAddress(address: string): void {
      root.restoreAddress(address)
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

  function launchApp(appId, entry) { return contextLogic.launchApp(root, appId, entry) }

  function markLaunching(appId, windowsBefore) { return contextLogic.markLaunching(root, appId, windowsBefore) }

  function pruneLaunching() { return contextLogic.pruneLaunching(root) }

  function buildConfig(base) { return configLogic.buildConfig(root, base) }

  // The current look as a preset stores it.
  readonly property var currentLook: DockModel.pickLook(root.buildConfig({}))

  function saveConfig() { return persistLogic.saveConfig(root) }

  // ------------------------------------------------- appearance presets
  // Named copies of the look (DockModel.LOOK_KEYS), at most six, kept in the
  // config. Applying one goes through applyLook, like loading the config.
  property var presets: []
  readonly property bool canSavePreset: configLogic.savedCount(root) < DockModel.MAX_PRESETS
  // Which row is the active preset; DockPresets.activeId picks it.
  readonly property string activePresetId: configLogic.activePresetId(root)

  function presetIndex(id) { return configLogic.presetIndex(root, id) }

  function presetIdByName(name) { return configLogic.presetIdByName(root, name) }

  function itemGeometry() { return contextLogic.itemGeometry(root) }

  function presetNameTaken(name, exceptId) { return configLogic.presetNameTaken(root, name, exceptId) }

  function nextPresetName() { return configLogic.nextPresetName(root) }

  function replacePreset(i, preset) { configLogic.replacePreset(root, i, preset) }

  function savePreset(name) { return configLogic.savePreset(root, name) }

  function renamePreset(id, name) { return configLogic.renamePreset(root, id, name) }

  function updatePreset(id) { return configLogic.updatePreset(root, id) }

  function deletePreset(id) { return configLogic.deletePreset(root, id) }

  // The context menu is a layer popup that Hyprland fades out over ~200 ms.
  // Restyling the dock under it (a border changes the card height and the
  // popup's anchor) makes the fading menu jump over the new look, so a pick
  // from the menu waits until the fade is over.
  Timer {
    id: menuPresetTimer
    property string presetId: ""
    interval: 250
    onTriggered: root.applyPreset(presetId)
  }

  function applyPresetAfterMenu(id) { return stateLogic.applyPresetAfterMenu(root, id) }

  function applyPreset(id) { return configLogic.applyPreset(root, id) }

  function activate(appId) { return windowLogic.activate(root, appId) }

  function windowRowLabel(window) { return windowLogic.windowRowLabel(root, window) }

  function entryForId(appId) { return pinLogic.entryForId(root, appId) }

  function setPinned(next) { return pinLogic.setPinned(root, next) }

  function applyPinnedRow(row) { return pinLogic.applyPinnedRow(root, row) }

  function togglePin(appId) { return pinLogic.togglePin(root, appId) }

  function resolveDesktopEntry(appId) { return pinLogic.resolveDesktopEntry(root, appId) }

  function notifyUnsafeRemoval(name) { return contextLogic.notifyUnsafeRemoval(root, name) }

  // Event driven: the script blocks on kernel uevents and mount-table
  // changes, so it adds no idle CPU. One dock (the primary) reports.
  Process {
    id: driveRemovalWatch
    command: ["python3", root.scriptPath("drive-removal-watch.py")]
    running: root.isPrimary && root.showRemovableDrives && root.warnUnsafeRemoval
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        try {
          var ev = JSON.parse(line)
          var drives = root.mountedDrives || []
          var name = ""
          for (var i = 0; i < drives.length; i++) {
            if (drives[i] && (drives[i].dev === ev.dev || drives[i].mountpoint === ev.mountpoint)) {
              name = drives[i].name
              break
            }
          }
          root.notifyUnsafeRemoval(name || String(ev.mountpoint || "").split("/").pop())
        } catch (e) {
          console.warn("[omadock] Failed reading drive removal event:", e)
        }
      }
    }
  }

  function notifyAppMissing(name, reason) { return contextLogic.notifyAppMissing(root, name, reason) }

  function launchDesktopAction(action, appName) { return contextLogic.launchDesktopAction(root, action, appName) }

  function isWindowFocused(win) { return styleLogic.isWindowFocused(root, win) }

  function isWindowParked(win) { return styleLogic.isWindowParked(root, win) }

  function syncContextWindows() { return contextLogic.syncContextWindows(root) }

  function openContext(appId, x, y, group) { return contextLogic.openContext(root, appId, x, y, group) }

  function closeContext() { return contextLogic.closeContext(root) }

  // ------------------------------------------------- minimized tile context
  property var contextTileWins: []
  property string contextTileAppId: ""
  property string contextTileName: ""
  property bool contextTilePinned: false

  function openTileContext(wins, appId, cx) { return contextLogic.openTileContext(root, wins, appId, cx) }

  function restoreContextTile() { return contextLogic.restoreContextTile(root) }

  function restoreContextTileOriginal() { return contextLogic.restoreContextTileOriginal(root) }

  function closeContextTile() { return contextLogic.closeContextTile(root) }

  function openFolderStack(path, name, cx) { return folderLogic.openFolderStack(root, path, name, cx) }

  function applyStackScan(items, count, truncated, failed) { return folderLogic.applyStackScan(root, items, count, truncated, failed) }

  function showStackDir(dir, name) { return folderLogic.showStackDir(root, dir, name) }

  function enterStackDir(dir, name) { return folderLogic.enterStackDir(root, dir, name) }

  function stackBack() { return folderLogic.stackBack(root) }

  function closeFolderStack() { return folderLogic.closeFolderStack(root) }

  function openFolderContext(path, name, cx, cy, command) { return folderLogic.openFolderContext(root, path, name, cx, cy, command) }

  // Per-folder stack order, stored on the pinned entry (see list-folder.py).
  readonly property var folderSortLabels: ({
    name: "Name",
    kind: "Kind",
    modified: "Date Modified",
    added: "Date Added",
    size: "Size"
  })

  function folderSortFor(path) { return folderLogic.folderSortFor(root, path) }

  function folderViewFor(path) { return folderLogic.folderViewFor(root, path) }

  function setFolderOption(path, key, value) { return folderLogic.setFolderOption(root, path, key, value) }

  function setFolderSort(path, sort) { return folderLogic.setFolderSort(root, path, sort) }

  function setFolderView(path, view) { return folderLogic.setFolderView(root, path, view) }

  function isFolderPinned(path) { return folderLogic.isFolderPinned(root, path) }

  function toggleFolderPin(path, name, icon) { return folderLogic.toggleFolderPin(root, path, name, icon) }
  function renamePinnedFolder(path, name) { folderLogic.renamePinnedFolder(root, path, name) }

  function unpinButton(name, command) { return folderLogic.unpinButton(root, name, command) }

  function moveAppGroup(groupId, insertIndex) { return groupsLogic.moveAppGroup(root, groupId, insertIndex) }

  function moveFolder(path, insertIndex) { return folderLogic.moveFolder(root, path, insertIndex) }

  function menuContentWidth(item) { return contextLogic.menuContentWidth(root, item) }

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

  function recoverDockSurface() { return contextLogic.recoverDockSurface(root) }

  // ------------------------------------------------- panel window

  PanelWindow {
    id: dockWindow

    screen: root.dockScreen
    color: "transparent"
    WlrLayershell.namespace: "omadock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: (root.contextRenaming || (appGroupLoader.item && appGroupLoader.item.body.isEditingName))
      ? WlrKeyboardFocus.OnDemand
      : WlrKeyboardFocus.None
    exclusionMode: (!root.autohide && !root.floatingWatch.yieldDock) ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: (!root.autohide && !root.floatingWatch.yieldDock) ? Math.round((dockCardComp ? dockCardComp.dockCard.height + dockCardComp.shadowRoom : 0) + root.edgeGap * 2) : 0
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
      var h = Math.ceil((dockCardComp ? dockCardComp.dockCard.height : 64) + root.edgeGap + dockWindow.dockHeadroom)
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
        if (dockCardComp && dockCardComp.stretch) return 0
        var cardW = (dockCardComp && dockCardComp.dockCard.width > 0) ? dockCardComp.dockCard.width : Style.space(320)
        var targetW = Math.min(parent.width, cardW + Style.space(96))
        if (root.placement.align === "left") return Style.gapsOut
        if (root.placement.align === "right") return parent.width - targetW - Style.gapsOut
        return Math.round((parent.width - targetW) / 2)
      }
      width: {
        if (dockCardComp && dockCardComp.stretch) return parent.width
        var cardW = (dockCardComp && dockCardComp.dockCard.width > 0) ? dockCardComp.dockCard.width : Style.space(320)
        return Math.min(parent.width, cardW + Style.space(96))
      }
      height: (root.autohide && !root.dockVisible && !root.floatingWatch.yieldDock) ? root.revealHeight : 0
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
          NumberAnimation { duration: root.motion.slow; easing.type: Easing.OutCubic }
        }
        width: revealHover.hovered ? Style.space(48) : Style.space(24)
        height: Style.space(3)
        radius: height / 2
        color: Util.alpha(Color.bar.text, revealHover.hovered ? 0.6 : 0.25)
        Behavior on width { NumberAnimation { duration: root.motion.fast; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: root.motion.fast } }
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
    PopupLife { id: stackLife; dockRoot: root; rivals: [groupLife, contextLife, fitHost.overflowLife]; want: root.activeStackFolder !== "" && root.dockVisible }
    LazyLoader {
      id: folderStackLoader
      active: stackLife.alive

      DockPopupWindow {
        id: folderStackWindow
        life: stackLife
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
    PopupLife { id: groupLife; dockRoot: root; rivals: [stackLife, contextLife, fitHost.overflowLife]; want: root.activeAppGroupId !== "" && root.dockVisible }
    LazyLoader {
      id: appGroupLoader
      active: groupLife.alive

      DockPopupWindow {
        id: appGroupWindow
        life: groupLife
        dockRoot: root
        open: true
        centerX: root.activeAppGroupX
        body: appGroupPopupComp
        // The opened group's inline name field (its title row) edits on this
        // popup's surface, so it needs the keyboard there, like the menu's
        // name field does.
        holdsKeyboard: appGroupPopupComp.isEditingName
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
    PopupLife { id: contextLife; dockRoot: root; rivals: [stackLife, groupLife, fitHost.overflowLife]; want: root.contextAppId !== "" }
    LazyLoader {
      id: contextMenuLoader
      active: contextLife.alive

      DockPopupWindow {
        id: contextMenuWindow
        life: contextLife
        dockRoot: root
        open: true
        centerX: root.contextX
        body: contextMenuComp
        // A name field in the menu (ContextRenameRow) needs the keyboard on
        // this popup's surface, not on the dock's layer surface.
        holdsKeyboard: root.contextRenaming
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
