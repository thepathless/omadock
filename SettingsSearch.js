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
  { key: "appsButton", page: "appearance", label: "Omarchy button", terms: ["launcher", "start", "menu", "logo"] },
  { key: "appsButtonAction", page: "appearance", label: "Omarchy button opens", terms: ["launcher", "app grid", "apps", "menu", "drag", "pin"] },
  { key: "removableDrives", page: "appearance", label: "Removable drives", terms: ["usb", "media", "eject"] },
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
  { key: "autohide", page: "behavior", label: "Autohide", terms: ["hide", "reveal", "visibility", "intelligent"] },
  { key: "revealDelay", page: "behavior", label: "Reveal delay", terms: ["autohide", "delay"] },
  { key: "floatingDock", page: "behavior", label: "Floating workspaces", terms: ["omarchy dock", "floating", "layout", "hide", "super l"] },
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
  { key: "warnUnsafeRemoval", page: "appearance", label: "Warn on unsafe removal", terms: ["drive", "usb", "eject", "removal", "unsafe", "notify"] },
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
    if (best >= 0) out.push({ key: e.key, page: e.page, label: shown, score: best })
  }
  out.sort(function (a, b) { return b.score - a.score })
  return out.slice(0, cap)
}
