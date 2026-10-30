// Settings search index + fuzzy matcher. Moved out of DockModel.js so the
// shared model stays data/parse logic and this stays UI search metadata
// (AGENTS.md "Where Concerns Live"). Plain JS with no Qt globals, like
// DockModel.js, so tests run it in the same vm context.

// ------------------------------------------------------- settings search
// Fuzzy subsequence match for the settings search box. Query characters must
// appear in order, but may skip: typos and initials still score ("pixl"
// matches "pixel", "shad" matches "shadow"). Word starts and runs score
// higher so the tightest meaning wins; -1 means no match.
function fuzzyScore(query, text) {
  var q = String(query == null ? "" : query).toLowerCase().replace(/\s+/g, "")
  var t = String(text == null ? "" : text).toLowerCase()
  if (q === "" || t === "") return -1
  var score = 0
  var ti = 0
  var prev = -2
  for (var qi = 0; qi < q.length; qi++) {
    var found = t.indexOf(q[qi], ti)
    if (found < 0) return -1
    if (found === prev + 1) score += 8
    if (found === 0 || t[found - 1] === " " || t[found - 1] === "-" || t[found - 1] === "/") score += 6
    score += Math.max(0, 4 - (found - ti))
    prev = found
    ti = found + 1
  }
  return score - (t.length - q.length) * 0.1
}

// Every searchable setting row: the key SettingsPanel registers its rows
// under, the page it lives on, its label, and synonyms people may type.
var SETTINGS_SEARCH = [
  { key: "showBackground", page: "appearance", label: "Background", terms: ["fill", "bar", "panel", "off", "hide"] },
  { key: "bgFill", page: "appearance", label: "Fill", terms: ["background", "solid", "gradient"] },
  { key: "bgColor", page: "appearance", label: "Color", terms: ["background", "colour", "swatch", "theme"] },
  { key: "gradientPalette", page: "appearance", label: "Palette", terms: ["gradient", "colours", "theme"] },
  { key: "gradientStrength", page: "appearance", label: "Strength", terms: ["gradient", "blend"] },
  { key: "opacityTheme", page: "appearance", label: "Opacity from theme", terms: ["transparency", "bar"] },
  { key: "opacity", page: "appearance", label: "Opacity", terms: ["transparency", "translucent"] },
  { key: "border", page: "appearance", label: "Border", terms: ["outline", "rim", "stroke"] },
  { key: "borderWidth", page: "appearance", label: "Border width", terms: ["outline", "rim"] },
  { key: "borderOpacityTheme", page: "appearance", label: "Border opacity from theme", terms: ["rim"] },
  { key: "borderOpacity", page: "appearance", label: "Border opacity", terms: ["rim"] },
  { key: "dividerLength", page: "appearance", label: "Divider length style", terms: ["divider", "lines", "classic"] },
  { key: "dividerStyle", page: "appearance", label: "Divider style", terms: ["divider", "lines", "hide", "hidden"] },
  { key: "dividerWidth", page: "appearance", label: "Divider width", terms: ["divider"] },
  { key: "dividerOpacity", page: "appearance", label: "Divider opacity", terms: ["divider"] },
  { key: "dividerHeight", page: "appearance", label: "Divider height", terms: ["divider", "length"] },
  { key: "corners", page: "appearance", label: "Corners", terms: ["shape", "rounded", "pill", "square", "radius"] },
  { key: "cornerRadius", page: "appearance", label: "Corner radius", terms: ["rounding", "shape"] },
  { key: "splitSections", page: "appearance", label: "Split sections", terms: ["panels", "gap"] },
  { key: "panelSpacing", page: "appearance", label: "Panel spacing", terms: ["gap", "split"] },
  { key: "indicators", page: "appearance", label: "Indicators", terms: ["dots", "bars", "running", "shape"] },
  { key: "appsButton", page: "folders", label: "Omarchy button", terms: ["launcher", "start", "menu", "logo"] },
  { key: "appsButtonAction", page: "folders", label: "Omarchy button opens", terms: ["launcher", "app grid", "apps", "menu", "drag", "pin"] },
  { key: "removableDrives", page: "folders", label: "Removable drives", terms: ["usb", "media", "eject"] },
  { key: "iconTheme", page: "icons", label: "Icon theme", terms: ["icons", "theme", "system", "whitesur", "macos", "papirus", "yaru", "apply", "desktop"] },
  { key: "iconStyle", page: "icons", label: "Icon style", terms: ["pixel", "pixel style", "mono", "monochrome", "dots", "dot matrix", "original"] },
  { key: "iconTint", page: "icons", label: "Icon colour", terms: ["color", "tint", "bw", "black", "white", "accent"] },
  { key: "iconGrid", page: "icons", label: "Pixels across", terms: ["grid", "pixel", "dots", "chunky"] },
  { key: "iconContrast", page: "icons", label: "Contrast", terms: ["flatten", "poster"] },
  { key: "iconStrength", page: "icons", label: "Strength", terms: ["effect", "blend"] },
  { key: "iconHoverOriginal", page: "icons", label: "Show original on hover", terms: ["hover", "original", "plain"] },
  { key: "iconHoverReveal", page: "icons", label: "Dithered reveal", terms: ["dither", "reveal"] },
  { key: "iconSize", page: "icons", label: "Icon size", terms: ["big", "small", "scale"] },
  { key: "itemSpacing", page: "icons", label: "Spacing", terms: ["gap", "distance"] },
  { key: "animations", page: "motion", label: "Animations", terms: ["motion", "reduce", "reduced", "off", "speed", "transitions"] },
  { key: "hoverEffect", page: "motion", label: "Hover effect", terms: ["zoom", "wave", "lift", "glow", "glitch", "highlight", "magnify"] },
  { key: "launchBounce", page: "motion", label: "Launch bounce", terms: ["animation", "starting"] },
  { key: "showShadow", page: "motion", label: "Shadow", terms: ["drop", "elevation", "shadow"] },
  { key: "shadowStrength", page: "motion", label: "Shadow strength", terms: ["shadow"] },
  { key: "blurSystem", page: "motion", label: "Blur from system", terms: ["frost", "hyprland"] },
  { key: "blur", page: "motion", label: "Blur", terms: ["frost", "glass", "translucent"] },
  { key: "blurSize", page: "motion", label: "Blur strength", terms: ["frost"] },
  { key: "grain", page: "motion", label: "Grain", terms: ["noise", "film", "texture"] },
  { key: "autohide", page: "placement", label: "Autohide", terms: ["hide", "reveal", "visibility", "intelligent"] },
  { key: "revealDelay", page: "placement", label: "Reveal delay", terms: ["autohide", "delay"] },
  { key: "floatingDock", page: "placement", label: "Floating workspaces", terms: ["omarchy dock", "floating", "layout", "hide", "super l"] },
  { key: "minimizeMode", page: "behavior", label: "Minimize on click", terms: ["park", "click"] },
  { key: "restoreWorkspace", page: "behavior", label: "Restore on", terms: ["minimize", "park", "windows", "origin"] },
  { key: "restoreSlot", page: "behavior", label: "Restore original slot", terms: ["minimize", "park", "position", "layout"] },
  { key: "keepPointer", page: "behavior", label: "Keep pointer in place", terms: ["mouse", "cursor"] },
  { key: "wheelStepDelay", page: "behavior", label: "Wheel step delay", terms: ["scroll", "wheel"] },
  { key: "badges", page: "behavior", label: "Notification badges", terms: ["badge", "notification", "count", "dot"] },
  { key: "badgeStyle", page: "behavior", label: "Badge style", terms: ["badge", "dot", "count", "number", "pill"] },
  { key: "badgePosition", page: "behavior", label: "Badge position", terms: ["badge", "corner", "top", "bottom", "left", "right"] },
  { key: "badgeColor", page: "behavior", label: "Badge color", terms: ["badge", "colour", "accent", "urgent", "red", "neutral"] },
  { key: "urgentHint", page: "behavior", label: "Urgent highlights", terms: ["urgent", "attention", "highlight"] },
  { key: "urgentOnNotification", page: "behavior", label: "Urgent on notification", terms: ["notification", "urgent"] },
  { key: "urgentSound", page: "behavior", label: "Urgent sound", terms: ["bell", "chime", "audio", "alert"] },
  { key: "tooltips", page: "behavior", label: "Tooltips", terms: ["tooltip", "hover", "label"] },
  { key: "tooltipDelay", page: "behavior", label: "Tooltip delay", terms: ["tooltip"] },
  { key: "windowPreviews", page: "behavior", label: "Window previews", terms: ["preview", "thumbnail"] },
  { key: "minimizedTiles", page: "behavior", label: "Minimized window tiles", terms: ["park", "tiles", "preview"] },
  { key: "warnUnsafeRemoval", page: "folders", label: "Warn on unsafe removal", terms: ["drive", "usb", "eject", "removal", "unsafe", "notify"] },
  { key: "labelMode", page: "labels", label: "Labels", terms: ["names", "text", "titles", "beside", "hover", "always", "rename", "custom"] },
  { key: "labelKind", page: "labels", label: "Show on", terms: ["labels", "apps", "groups", "folders", "which"] },
  { key: "labelFont", page: "labels", label: "Font", terms: ["labels", "pixel", "sans", "typeface", "retro"] },
  { key: "labelSize", page: "labels", label: "Size", terms: ["labels", "font", "small", "large"] },
  { key: "labelWeight", page: "labels", label: "Weight", terms: ["labels", "bold", "thick", "font", "readable"] },
  { key: "labelColor", page: "labels", label: "Color", terms: ["labels", "colour", "accent", "contrast", "readable", "auto"] },
  { key: "labelBackground", page: "labels", label: "Background", terms: ["labels", "pill", "plate", "button"] },
  { key: "labelShape", page: "labels", label: "Corners", terms: ["labels", "shape", "square", "sharp", "pill", "rounded", "radius", "nested", "round ends"] },
  { key: "labelIndicators", page: "labels", label: "Indicators", terms: ["labels", "dots", "windows", "running", "plate", "column", "side"] },
  { key: "labelPinned", page: "labels", label: "Pinned apps", terms: ["labels", "pinned", "running", "open", "closed", "hide", "names"] },
  { key: "labelPlateHeight", page: "labels", label: "Plate height", terms: ["labels", "plate", "tall", "full", "stretch", "dock"] },
  { key: "labelReveal", page: "labels", label: "Reveal", terms: ["labels", "animation", "typewriter", "scramble", "slide"] },
  { key: "labelEffect", page: "labels", label: "Effect", terms: ["labels", "glow", "shadow", "outline", "stroke"] },
  { key: "labelMaxWidth", page: "labels", label: "Max width", terms: ["labels", "truncate", "shorten", "long names"] },
  { key: "layout", page: "placement", label: "Layout", terms: ["panel", "taskbar", "dock", "full width", "bar", "edge"] },
  { key: "alignment", page: "placement", label: "Alignment", terms: ["left", "center", "right", "position", "both sides", "spread", "split", "taskbar", "windows", "start", "clock", "tray"] },
  { key: "multiMonitor", page: "placement", label: "Show on all monitors", terms: ["monitor", "display", "multi"] },
  { key: "perMonitorApps", page: "placement", label: "Only this monitor's apps", terms: ["monitor", "display"] },
  { key: "monitorSelect", page: "placement", label: "Monitor", terms: ["display", "output", "screen"] },
  { key: "customFolder", page: "folders", label: "Custom folder", terms: ["add", "directory", "pin"] },
  { key: "folderColor", page: "folders", label: "Folder color", terms: ["folder", "colour", "yaru"] },
  { key: "groupStyle", page: "groups", label: "Tile style", terms: ["group", "tile", "frame"] },
  { key: "groupIconEffects", page: "groups", label: "Icon style", terms: ["group", "icons"] },
  { key: "presets", page: "presets", label: "Presets", terms: ["preset", "look", "save", "restore"] },
  { key: "updateChannel", page: "about", label: "Update channel", terms: ["update", "stable", "experimental", "switch"] }
]

// Old IPC page names remain valid; navigation and search use six categories.
function category(page) {
  if (["icons", "labels", "motion"].indexOf(page) >= 0) return "appearance"
  if (page === "groups") return "folders"
  if (page === "supporters") return "about"
  return ["presets", "appearance", "placement", "behavior", "folders", "about"].indexOf(page) >= 0 ? page : "presets"
}

function entryFor(key) {
  for (var i = 0; i < SETTINGS_SEARCH.length; i++) {
    var e = SETTINGS_SEARCH[i]
    if (e.key === key) return { key: e.key, page: category(e.page), label: e.label }
  }
  return null
}

// Pure dependency descriptions: search never changes configuration to expose
// a result. The row stays readable and links to the first unmet prerequisite.
function dependency(key, r) {
  if (!r) return null
  function needs(condition, target, text) { return condition ? null : { key: target, text: text } }
  var background = ["bgFill", "bgColor", "gradientPalette", "gradientStrength", "opacityTheme", "opacity", "blurSystem", "blur", "blurSize", "grain"]
  if (background.indexOf(key) >= 0 && !r.showBackground)
    return { key: "showBackground", text: "Enable Background to use this setting." }
  if (["gradientPalette", "gradientStrength"].indexOf(key) >= 0)
    return needs(r.bgFill === "gradient", "bgFill", "Choose Gradient fill to use this setting.")
  if (key === "bgColor") return needs(r.bgFill !== "gradient", "bgFill", "Choose Solid fill to use this setting.")
  if (key === "opacity") return needs(r.dockOpacity >= 0, "opacityTheme", "Turn off Opacity from theme to set opacity by hand.")
  if (["borderWidth", "borderOpacityTheme", "borderOpacity"].indexOf(key) >= 0 && !r.showBorder)
    return { key: "border", text: "Enable Border to use this setting." }
  if (key === "borderOpacity") return needs(r.borderOpacity >= 0, "borderOpacityTheme", "Turn off Border opacity from theme to set it by hand.")
  if (key.indexOf("divider") === 0) {
    if (r.placement.split) return { key: "splitSections", text: "Turn off Split sections to use dividers." }
    if (key !== "dividerStyle" && r.dividerStyle === "none") return { key: "dividerStyle", text: "Choose a visible Divider style first." }
    if (key === "dividerWidth" || key === "dividerOpacity") return needs(r.dividerStyle === "custom", "dividerStyle", "Choose Custom divider style to tune this value.")
    if (key === "dividerHeight") return needs(r.dividerGeometry === "long", "dividerLength", "Choose Long divider length to set its height.")
  }
  if (["corners", "cornerRadius", "splitSections"].indexOf(key) >= 0 && r.placement.panel)
    return { key: "layout", text: "Choose Dock layout to use floating dock corners and split sections." }
  if (key === "cornerRadius") return needs(r.dockShape === "rounded", "corners", "Choose Rounded corners to set a radius.")
  if (key === "panelSpacing") return needs(r.placement.split, "splitSections", "Enable Split sections to set panel spacing.")
  if (key === "appsButtonAction") {
    if (!r.sharedState || !r.sharedState.appGrid.available) return { key: "", text: "The app grid requires a compatible Omarchy shell." }
    return needs(r.showAppsButton, "appsButton", "Enable the Omarchy button to choose its action.")
  }
  if (key === "warnUnsafeRemoval") return needs(r.showRemovableDrives, "removableDrives", "Enable Removable drives to use removal warnings.")
  if (["iconTint", "iconContrast", "iconStrength"].indexOf(key) >= 0)
    return needs(r.iconStyle === "mono" || r.iconStyle === "dots", "iconStyle", "Choose Monochrome or Dot matrix icon style first.")
  if (key === "iconGrid") return needs(r.iconStyle === "pixel" || r.iconStyle === "dots", "iconStyle", "Choose Pixel or Dot matrix icon style first.")
  if (key === "iconHoverOriginal") return needs(r.iconStyle !== "original", "iconStyle", "Choose an icon effect before enabling original-on-hover.")
  if (key === "iconHoverReveal") {
    if (r.iconStyle !== "mono" && r.iconStyle !== "dots") return { key: "iconStyle", text: "Choose Monochrome or Dot matrix icon style first." }
    return needs(r.iconHoverOriginal, "iconHoverOriginal", "Enable Show original on hover to use dithered reveal.")
  }
  if (key === "shadowStrength") return needs(r.showShadow, "showShadow", "Enable Shadow to set its strength.")
  if (key === "blur") return needs(r.blurMode !== "system", "blurSystem", "Turn off Blur from system to choose explicit blur.")
  if (key === "blurSize") return needs(r.blurMode === "on", r.blurMode === "system" ? "blurSystem" : "blur", "Enable explicit Blur to set its strength; the size affects all Hyprland windows and panels.")
  if (key === "revealDelay") return needs(r.autohide, "autohide", "Choose Autohide or Intelligent visibility to set a reveal delay.")
  if (key === "floatingDock") return needs(r.floatingWatch.available, "", "Floating workspace integration requires a compatible Omarchy shell.")
  if (["badgeStyle", "badgePosition", "badgeColor"].indexOf(key) >= 0)
    return needs(r.showNotificationBadges, "badges", "Enable Notification badges to change badge styling.")
  if (key === "tooltipDelay" || key === "windowPreviews") return needs(r.showTooltips, "tooltips", "Enable Tooltips to use previews and their delay.")
  if (key === "perMonitorApps") return needs(r.multiMonitor, "multiMonitor", "Enable Show on all monitors to filter each dock by monitor.")
  if (key.indexOf("label") === 0 && key !== "labelMode") {
    if (r.labelMode === "off") return { key: "labelMode", text: "Enable Labels to use name styling." }
    if (key === "labelPinned" && (r.labelMode !== "always" || ["all", "apps"].indexOf(r.labelKind) < 0))
      return { key: r.labelMode !== "always" ? "labelMode" : "labelKind", text: "Show Labels always on apps to choose pinned-name behavior." }
    if (key === "labelWeight") return needs(r.labelFont !== "pixel", "labelFont", "Choose Theme or Sans font to change its weight.")
    if (key === "labelBackground") return needs(r.labelMode !== "hover", "labelMode", "Choose Always labels to set their background.")
    if (key === "labelShape") return needs(r.labelBackground !== "none" || r.labelMode === "hover", "labelBackground", "Choose a label background before setting its corners.")
    if (key === "labelPlateHeight" || key === "labelIndicators") {
      if (r.labelMode !== "always") return { key: "labelMode", text: "Choose Always labels to use plate layout." }
      return needs(r.labelBackground === "plate", "labelBackground", "Choose Plate label background to use plate layout.")
    }
    if (key === "labelReveal") return needs(r.labelMode === "hover", "labelMode", "Choose On hover labels to set their reveal animation.")
  }
  return null
}

// Ranked search over SETTINGS_SEARCH (or any entry list in the same shape).
// Every query character must land in order on some term; the best-scoring
// term of each entry is its score.
// translate(entry), when given, is the label in the dock's language
// (SettingsPanel.searchLabel): a query matches it as well as the English
// label and terms, and the hit carries it.
function searchSettings(query, entries, limit, translate) {
  var list = entries == null ? SETTINGS_SEARCH : entries
  var cap = limit == null ? 8 : limit
  var out = []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    var shown = translate ? translate(e) : e.label
    var best = fuzzyScore(query, e.label)
    if (shown !== e.label) best = Math.max(best, fuzzyScore(query, shown))
    var terms = e.terms || []
    for (var j = 0; j < terms.length; j++) {
      var s = fuzzyScore(query, terms[j])
      if (s > best) best = s
    }
    if (best >= 0) out.push({ key: e.key, page: category(e.page), label: shown, score: best })
  }
  out.sort(function (a, b) { return b.score - a.score })
  return out.slice(0, cap)
}
