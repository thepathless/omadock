import QtQuick
import "../strings"
import "../../DockModel.js" as DockModel
import "../../DockPresets.js" as DockPresets
import "../../Buttons.js" as Buttons
import "../../DockLabels.js" as DockLabels
import "../../DockLayout.js" as DockLayout
import "../../DockMotion.js" as DockMotion
import "../../DockFloating.js" as DockFloating

// Config and preset logic, extracted from Dock.qml so the root file only
// declares state and wiring. Every function is stateless: the dock root is
// passed in and owns all state. Bodies are transcribed from Dock.qml — the
// behavior contract is the unit tests plus the live smoke test.

QtObject {
  // ------------------------------------------------------- the look
  // The look: every value a preset holds, parsed and clamped exactly as the
  // config file is. Used when the config loads and when a preset applies.
  // Sets properties only; callers save and update the blur rule.
  function applyLook(root, parsed) {
    // Migrates the old boolean: an explicit magnification:false meant no growth.
    root.hoverEffect = parsed && ["zoom", "wave", "lift", "glow", "glitch", "off"].indexOf(parsed.hoverEffect) >= 0
      ? parsed.hoverEffect
      : ((parsed && parsed.magnification === false) ? "off" : "zoom")
    root.launchBounce = parsed && parsed.launchBounce !== false
    // Label looks (a preset's, or the file's before readLabelConfig runs).
    var labelLook = DockLabels.pickLabelLook(parsed, root)
    for (var llk in labelLook) root[llk] = labelLook[llk]
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
    // Stored as written down to 0: a square look draws at 0 and would
    // otherwise never match its own preset key for key. The 2px floor belongs
    // to a drawn rounded radius (Dock.qml roundedRadius), not to this value.
    root.cornerRadius = parsed && typeof parsed.cornerRadius === "number" && isFinite(parsed.cornerRadius) && parsed.cornerRadius >= 0
      ? Math.max(0, Math.round(parsed.cornerRadius)) : -1
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
    // Blur size the dock asks the compositor for while blur is "on"; 0 leaves
    // the compositor's own size alone.
    root.blurSize = parsed && typeof parsed.blurSize === "number" && isFinite(parsed.blurSize)
      ? Math.max(0, Math.min(20, Math.round(parsed.blurSize))) : 0
    root.iconStyle = (parsed && ["mono", "pixel", "dots"].indexOf(parsed.iconStyle) >= 0) ? parsed.iconStyle : "original"
    root.iconTint = (parsed && (parsed.iconTint === "accent" || parsed.iconTint === "bw")) ? parsed.iconTint : "text"
    root.iconHoverOriginal = parsed ? parsed.iconHoverOriginal === true : false
    root.iconHoverReveal = parsed ? parsed.iconHoverReveal === true : false
    root.iconContrast = parsed && typeof parsed.iconContrast === "number" ? Math.max(0, Math.min(1, parsed.iconContrast)) : 0
    root.iconStrength = parsed && typeof parsed.iconStrength === "number" ? Math.max(0, Math.min(1, parsed.iconStrength)) : 1
    root.iconGrid = parsed && typeof parsed.iconGrid === "number"
      ? Math.max(8, Math.min(32, Math.round(parsed.iconGrid)))
      : 16
    // Card padding and the artwork's place in its slot: "dock" keeps the
    // classic lift above the indicator band, "center" centres the artwork in
    // the slot so the bar carries equal room above and below.
    root.dockPadding = parsed && typeof parsed.dockPadding === "number" && isFinite(parsed.dockPadding)
      ? Math.max(0, Math.min(40, Math.round(parsed.dockPadding))) : 5
    // The padding in pixels, for a look whose measurement is in pixels and
    // cannot be expressed on the theme's spacing scale; -1 follows dockPadding.
    root.dockPaddingPx = parsed && typeof parsed.dockPaddingPx === "number" && isFinite(parsed.dockPaddingPx) && parsed.dockPaddingPx >= 0
      ? Math.min(40, Math.round(parsed.dockPaddingPx)) : -1
    root.iconBaseline = (parsed && parsed.iconBaseline === "center") ? "center" : "dock"
    // Spacing units of margin a slot adds around the artwork; the artwork plus
    // this margin is the icon's pitch (before itemSpacing). Kept to half units:
    // the scale quantises whole units to whole pixels, and a look that measured
    // its pitch off a real dock needs the half step to land on it.
    root.iconMargin = parsed && typeof parsed.iconMargin === "number" && isFinite(parsed.iconMargin)
      ? Math.max(0, Math.min(24, Math.round(parsed.iconMargin * 2) / 2)) : 10
    // Specular sheen painted over the card fill: 0 leaves the flat surface.
    root.surfaceGlass = parsed && typeof parsed.surfaceGlass === "number"
      ? Math.max(0, Math.min(1, parsed.surfaceGlass)) : 0
    // The material's body: its own lightness (-1 keeps the fill's), how far its
    // chroma is pulled to neutral, and how much of the card it is rather than
    // the backdrop. All three at rest leave the surface exactly as it was.
    root.surfaceLift = parsed && typeof parsed.surfaceLift === "number" && isFinite(parsed.surfaceLift) && parsed.surfaceLift >= 0
      ? Math.min(1, parsed.surfaceLift) : -1
    root.surfaceDesaturate = parsed && typeof parsed.surfaceDesaturate === "number" && isFinite(parsed.surfaceDesaturate)
      ? Math.max(0, Math.min(1, parsed.surfaceDesaturate)) : 0
    root.surfaceStability = parsed && typeof parsed.surfaceStability === "number" && isFinite(parsed.surfaceStability)
      ? Math.max(0, Math.min(1, parsed.surfaceStability)) : 0
    // Running marks: "windows" draws one per window (the classic dock),
    // "app" draws one dot per running app whatever its windows do.
    root.indicatorMode = (parsed && parsed.indicatorMode === "app") ? "app" : "windows"
    root.indicatorSize = parsed && typeof parsed.indicatorSize === "number" && isFinite(parsed.indicatorSize)
      ? Math.max(2, Math.min(12, Math.round(parsed.indicatorSize))) : 5
    // Distance from the card's bottom edge to the marks; negative is the
    // classic slot-relative placement.
    root.indicatorInset = parsed && typeof parsed.indicatorInset === "number" && isFinite(parsed.indicatorInset) && parsed.indicatorInset >= 0
      ? Math.min(20, Math.round(parsed.indicatorInset)) : -1
    // Hover magnification: the scale under the pointer and how far the wave
    // reaches, in slot widths.
    root.magnifyPeak = parsed && typeof parsed.magnifyPeak === "number" && isFinite(parsed.magnifyPeak)
      ? Math.max(1, Math.min(2.2, parsed.magnifyPeak)) : 1.4
    root.magnifyReach = parsed && typeof parsed.magnifyReach === "number" && isFinite(parsed.magnifyReach)
      ? Math.max(1, Math.min(4, parsed.magnifyReach)) : 2.2
    root.showBorder = parsed ? parsed.showBorder !== false : true
    root.indicatorShape = (parsed && (parsed.indicatorShape === "rounded" || parsed.indicatorShape === "square")) ? parsed.indicatorShape : "theme"
    root.borderWidth = parsed && typeof parsed.borderWidth === "number"
      ? Math.max(0.5, Math.min(6, parsed.borderWidth))
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
    root.dividerStyle = parsed && ["theme", "custom", "none"].indexOf(parsed.dividerStyle) >= 0 ? parsed.dividerStyle : "simple"
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

  // ------------------------------------------------- the config file
  // Parses and applies omadock.json text. The caller owns the file access.
  function loadConfig(root, rawText) {
    var raw = DockModel.readCapped(rawText, DockModel.MAX_CONFIG_BYTES).trim()
    var parsed = {}
    if (raw) {
      try {
        parsed = JSON.parse(raw)
      } catch (e) {
        console.warn("[omadock] Failed parsing omadock.json, using defaults:", e)
        parsed = {}
      }
    }
    root.alignment = DockLayout.normalizeAlignment(parsed ? (parsed.alignment || parsed.position) : "")
    root.layout = DockLayout.normalizeLayout(parsed ? parsed.layout : "")
    root.showRemovableDrives = parsed ? parsed.showRemovableDrives !== false : true
    root.warnUnsafeRemoval = parsed ? parsed.warnUnsafeRemoval !== false : true
    if (parsed && DockModel.isList(parsed.appGroups)) {
      // Persisted collections are shape- and size-bounded before reaching the
      // long-lived shell (see DockModel boundAppGroups / boundPinnedFolders).
      root.appGroups = DockModel.boundAppGroups(parsed.appGroups)
    } else {
      root.appGroups = []
    }
    // The shipped looks lead the list, then whatever the user saved: a fresh
    // install has no config at all and still offers every shipped preset.
    root.presets = DockPresets.merge(parsed ? DockModel.boundPresets(parsed.presets) : [], DockModel.pickLook)
    root.autohide = parsed && parsed.autohide !== false
    root.intelligentAutohide = parsed && parsed.intelligentAutohide !== false
    root.showAppsButton = parsed && parsed.showAppsButton !== false
    if (root.sharedState) root.sharedState.appGrid.mode = (parsed && parsed.appsButtonAction === "grid") ? "grid" : "menu"
    root.showTooltips = parsed && parsed.showTooltips !== false
    root.showMinimizedTiles = parsed ? parsed.showMinimizedTiles !== false : true
    root.advancedTooltips = parsed && parsed.advancedTooltips !== false
    root.screenName = parsed && typeof parsed.screen === "string" ? parsed.screen : ""
    root.multiMonitor = parsed ? parsed.multiMonitor === true : false
    root.perMonitorApps = parsed ? parsed.perMonitorApps !== false : true
    applyLook(root, parsed)
    root.systemBlurSize = DockModel.boundSystemBlurSize(parsed ? parsed.systemBlurSize : 0)
    root.applyBlurRule(false)
    if (parsed && typeof parsed.minimizeMode === "string") {
      root.minimizeMode = parsed.minimizeMode
    } else if (parsed && parsed.clickToMinimize === true) {
      root.minimizeMode = "active"
    } else {
      root.minimizeMode = "active"
    }
    root.restoreWorkspace = (parsed && parsed.restoreWorkspace === "origin") ? "origin" : "current"
    root.floatingWatch.choice = DockFloating.normalizeChoice(parsed ? parsed.floatingDock : "")
    root.restoreSlot = !!(parsed && parsed.restoreSlot === true)
    root.keepPointer = parsed ? parsed.keepPointer !== false : true
    root.animations = DockMotion.normalizeLevel(parsed ? parsed.animations : "full")
    root.showUrgentHint = parsed ? parsed.showUrgentHint !== false : true
    root.urgentOnNotification = parsed ? parsed.urgentOnNotification !== false : true
    root.showNotificationBadges = parsed ? parsed.showNotificationBadges !== false : true
    // Bounded spellings: anything else falls back to the classic badge.
    root.badgeStyle = (parsed && parsed.badgeStyle === "dot") ? "dot" : "count"
    root.badgePosition = (parsed && ["top-left", "top-right", "bottom-left", "bottom-right"].indexOf(parsed.badgePosition) >= 0) ? parsed.badgePosition : "top-right"
    root.badgeColor = (parsed && ["accent", "urgent", "neutral"].indexOf(parsed.badgeColor) >= 0) ? parsed.badgeColor : "accent"
    // Name labels (DockLabels.readLabelConfig), including the first release's
    // showLabels / labelPlacement / labelContrast spellings.
    var labels = DockLabels.readLabelConfig(parsed)
    for (var lk in labels) root[lk] = labels[lk]
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
    root.pinnedButtons = parsed ? Buttons.boundPinnedButtons(parsed.pinnedButtons) : []
    if (parsed && DockModel.isList(parsed.pinnedFolders)) {
      root.pinnedFolders = DockModel.boundPinnedFolders(parsed.pinnedFolders)
    } else {
      root.pinnedFolders = [
        { path: "~/Downloads", name: "Downloads", icon: "folder-download" }
      ]
    }
  }

  // Reads no file, so bindings can use the current configuration.
  function buildConfig(root, base) {
    var conf = base && typeof base === "object" && !Array.isArray(base) ? base : {}
    conf.alignment = root.alignment || "center"
    conf.layout = root.layout
    delete conf.position
    conf.showRemovableDrives = root.showRemovableDrives
    conf.warnUnsafeRemoval = root.warnUnsafeRemoval
    conf.appGroups = DockModel.boundAppGroups(root.appGroups)
    conf.autohide = root.autohide
    conf.intelligentAutohide = root.intelligentAutohide
    conf.showAppsButton = root.showAppsButton
    if (root.sharedState) conf.appsButtonAction = root.sharedState.appGrid.mode
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
    conf.dockPadding = root.dockPadding
    if (root.dockPaddingPx >= 0) conf.dockPaddingPx = root.dockPaddingPx
    else delete conf.dockPaddingPx
    conf.iconMargin = root.iconMargin
    conf.iconBaseline = root.iconBaseline
    conf.surfaceGlass = root.surfaceGlass
    if (root.surfaceLift >= 0) conf.surfaceLift = root.surfaceLift
    else delete conf.surfaceLift
    if (root.surfaceDesaturate > 0) conf.surfaceDesaturate = root.surfaceDesaturate
    else delete conf.surfaceDesaturate
    if (root.surfaceStability > 0) conf.surfaceStability = root.surfaceStability
    else delete conf.surfaceStability
    conf.indicatorMode = root.indicatorMode
    conf.indicatorSize = root.indicatorSize
    conf.indicatorInset = root.indicatorInset
    conf.magnifyPeak = root.magnifyPeak
    conf.magnifyReach = root.magnifyReach
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
    conf.restoreWorkspace = root.restoreWorkspace
    conf.floatingDock = root.floatingWatch.choice
    conf.restoreSlot = root.restoreSlot
    conf.keepPointer = root.keepPointer
    conf.animations = root.animations
    conf.showUrgentHint = root.showUrgentHint
    conf.urgentOnNotification = root.urgentOnNotification
    conf.showNotificationBadges = root.showNotificationBadges
    conf.badgeStyle = root.badgeStyle
    conf.badgePosition = root.badgePosition
    conf.badgeColor = root.badgeColor
    DockLabels.writeLabelConfig(conf, root)
    conf.urgentSound = root.urgentSound
    conf.urgentSoundName = root.urgentSoundName
    conf.revealDelay = root.revealDelay
    conf.tooltipDelay = root.tooltipDelay
    conf.wheelStepDelay = root.wheelStepDelay
    conf.pinnedFolders = DockModel.boundPinnedFolders(root.pinnedFolders)
    conf.pinnedButtons = Buttons.boundPinnedButtons(root.pinnedButtons)
    // Only the saved presets reach the file: a shipped look is code, not state.
    conf.presets = DockModel.boundPresets(DockPresets.userOnly(root.presets))
    return conf
  }

  // ------------------------------------------------- appearance presets
  // Named copies of the look (DockModel.LOOK_KEYS), at most six, kept in the
  // config. Applying one goes through applyLook, like loading the config.

  function presetIndex(root, id) {
    var list = root.presets || []
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === id) return i
    return -1
  }

  // A preset the dock ships cannot be renamed, updated or removed -- the next
  // load would bring it back -- so every mutation refuses its index here.
  function presetEditable(root, i) {
    var list = root.presets || []
    return i >= 0 && list[i] && list[i].builtin !== true
  }

  // The saved presets, against DockModel.MAX_PRESETS (shipped ones are free).
  function savedCount(root) {
    return DockPresets.userCount(root.presets)
  }

  // The preset the look on screen matches, for the "active" mark.
  // DockPresets.activeId settles which row that is when a saved preset and a
  // shipped look are key-for-key equal: the row the user saved keeps it.
  function activePresetId(root) {
    return DockPresets.activeId(root.presets, root.currentLook, DockModel.lookIncludes)
  }

  // The preset with this name, ignoring case; "" when none or the name is
  // longer than a preset name can be.
  function presetIdByName(root, name) {
    var raw = String(name == null ? "" : name).trim()
    if (raw === "" || raw.length > DockModel.MAX_PRESET_NAME) return ""
    var want = DockModel.cleanPresetName(raw).toLowerCase()
    var list = root.presets || []
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].name.toLowerCase() === want) return list[i].id
    return ""
  }

  function presetNameTaken(root, name, exceptId) {
    var id = presetIdByName(root, name)
    return id !== "" && id !== exceptId
  }

  function nextPresetName(root) {
    for (var n = 1; n <= DockModel.MAX_PRESETS + 1; n++)
      if (!presetNameTaken(root, Tr.t("presets.numbered", "Preset %1").arg(n), "")) return Tr.t("presets.numbered", "Preset %1").arg(n)
    return Tr.t("presets.default", "Preset")
  }

  function replacePreset(root, i, preset) {
    var next = root.presets.slice()
    next[i] = preset
    root.presets = next
    root.saveConfig()
  }

  // A new preset from the current look; returns its id, or "" when the list
  // is full. A missing or taken name becomes "Preset N".
  function savePreset(root, name) {
    if (!root.canSavePreset) return ""
    var clean = DockModel.cleanPresetName(name)
    if (clean === "" || presetNameTaken(root, clean, "")) clean = nextPresetName(root)
    var id = "preset_" + Date.now()
    while (presetIndex(root, id) >= 0) id += "0"
    root.presets = (root.presets || []).concat([{ id: id, name: clean, look: root.currentLook }])
    root.saveConfig()
    return id
  }

  // Refuses an empty name or one another preset has.
  function renamePreset(root, id, name) {
    var i = presetIndex(root, id)
    var clean = DockModel.cleanPresetName(name)
    if (!presetEditable(root, i) || clean === "" || presetNameTaken(root, clean, id)) return false
    var p = root.presets[i]
    replacePreset(root, i, { id: p.id, name: clean, look: p.look })
    return true
  }

  function updatePreset(root, id) {
    var i = presetIndex(root, id)
    if (!presetEditable(root, i)) return false
    var p = root.presets[i]
    replacePreset(root, i, { id: p.id, name: p.name, look: root.currentLook })
    return true
  }

  function deletePreset(root, id) {
    var i = presetIndex(root, id)
    if (!presetEditable(root, i)) return false
    var next = root.presets.slice()
    next.splice(i, 1)
    root.presets = next
    root.saveConfig()
    return true
  }

  // A preset holds every look key: those it was saved without (they did not
  // exist yet) were filled with their defaults when it was read
  // (DockModel.pickLook), so applying it sets them back too.
  function applyPreset(root, id) {
    var i = presetIndex(root, id)
    if (i < 0) return false
    var preset = root.presets[i]
    applyLook(root, preset.look)
    // A shipped look may carry the setup its shape needs (the Windows
    // taskbar's full-width, always-visible panel, and one tile per app). Only
    // a shipped entry can: a saved preset is read back with id/name/look, so
    // this never moves the dock for one the user made.
    var setup = preset.setup
    if (setup && typeof setup === "object") {
      if (setup.layout) root.layout = DockLayout.normalizeLayout(setup.layout)
      if (setup.alignment) root.alignment = DockLayout.normalizeAlignment(setup.alignment)
      if (typeof setup.autohide === "boolean") {
        root.autohide = setup.autohide
        root.intelligentAutohide = setup.autohide ? setup.intelligentAutohide === true : false
      }
      if (typeof setup.showMinimizedTiles === "boolean") root.showMinimizedTiles = setup.showMinimizedTiles
      root.syncVisibility()
    }
    root.applyBlurRule(false)
    root.saveConfig()
    return true
  }
}
