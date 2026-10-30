// Icon resolution: the icon name a folder path maps to, the icon a removable
// drive resolves to, what a file item in a folder stack shows, and the icon
// index the shell scan writes out.
//
// Extracted verbatim from DockModel.js, which owned these: they are the icon
// side of the model and nothing else in DockModel.js called them. The module
// imports nothing (root JS modules in this repo never import each other; QML
// is the composition layer) and holds no state.
//
// Every function here reads as a pure function of its arguments: the caller
// passes the active theme, the folder colour mode and the app library, so this
// module never reaches into dock state.

// Icon name -> file from the icon scan's output, one path per line. The
// name is the file name without its extension; the first path for a name
// wins (the scan lists SVGs before PNGs).
function parseIconIndex(text) {
  var index = {}
  var lines = String(text == null ? "" : text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var value = lines[i].trim()
    if (!value) continue
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name && index[name] === undefined) index[name] = value
  }
  return index
}


function folderIconFor(path, explicitIcon) {
  if (explicitIcon) return explicitIcon
  var clean = String(path || "").trim().replace(/\/+$/, "")
  var norm = clean.toLowerCase()
  if (norm === "~" || (norm.indexOf("/home/") === 0 && norm.split("/").length <= 3)) return "user-home"
  var baseName = norm.split("/").pop() || ""
  if (baseName.indexOf("download") >= 0) return "folder-download"
  if (baseName.indexOf("document") >= 0) return "folder-documents"
  if (baseName.indexOf("picture") >= 0) return "folder-pictures"
  if (baseName.indexOf("music") >= 0) return "folder-music"
  if (baseName.indexOf("video") >= 0) return "folder-videos"
  if (baseName.indexOf("desktop") >= 0) return "user-desktop"
  if (baseName.indexOf("template") >= 0) return "folder-templates"
  if (baseName.indexOf("public") >= 0) return "folder-publicshare"
  if (baseName.indexOf("trash") >= 0) return "user-trash"
  return "folder"
}


function resolveDriveIcon(iconName, themeName, appLibrary, folderColorMode) {
  var name = String(iconName || "drive-removable-media-usb").trim()
  if (name.indexOf("/") === 0 || name.indexOf("file://") === 0) return name

  // Drives follow the folder colour, so they sit next to the folders in the
  // same style: wherever folders use Adwaita's monochrome outlines (white,
  // black, black-or-white or symbolic, or a theme with no Yaru colour),
  // drives do too.
  var theme = String(themeName || "").trim()
  var yaruTheme = theme === "Yaru" || (theme.indexOf("Yaru-") === 0 && theme !== "Yaru-gray" && theme !== "Yaru-grey")
  var mode = String(folderColorMode || "theme")
  if (mode === "white" || mode === "black" || mode === "bw" || mode === "symbolic"
      || ((mode === "theme" || mode === "auto") && !yaruTheme)) {
    var symbolicMap = {
      "drive-removable-media-usb": "media-removable",
      "usb-pendrive": "media-removable",
      "drive-removable-media": "drive-removable-media",
      "media-removable": "media-removable",
      "drive-harddisk-usb": "drive-harddisk-usb",
      "media-optical": "media-optical"
    }
    return "file:///usr/share/icons/Adwaita/symbolic/devices/" + (symbolicMap[name] || "drive-removable-media") + "-symbolic.svg"
  }

  // Known device icons come from Yaru itself, as the folders do -- but only
  // while Yaru is the desktop's theme. Any other theme asks the library, whose
  // index reads the active theme first.
  var devMap = {
    "drive-removable-media-usb": "/usr/share/icons/Yaru/256x256/devices/drive-removable-media-usb.png",
    "usb-pendrive": "/usr/share/icons/Yaru/256x256/devices/drive-removable-media-usb.png",
    "drive-removable-media": "/usr/share/icons/Yaru/256x256/devices/drive-removable-media.png",
    "media-removable": "/usr/share/icons/Yaru/256x256/devices/drive-removable-media.png",
    "drive-harddisk-usb": "/usr/share/icons/Yaru/256x256/devices/drive-harddisk-usb.png",
    "media-optical": "/usr/share/icons/Yaru/256x256/devices/media-optical.png"
  }

  if (devMap[name] && yaruTheme) {
    return "file://" + devMap[name]
  }

  // Anything else: whatever the icon index or the theme resolves.
  if (appLibrary) {
    var src = appLibrary.iconSource(name)
    if (src && src.length > 0) return src
  }

  return "file:///usr/share/icons/Yaru/256x256/devices/drive-removable-media-usb.png"
}


function resolveThemedFolderIcon(iconName, themeName, folderColorMode, appLibrary) {
  var name = String(iconName || "folder").trim()
  if (name.indexOf("/") === 0 || name.indexOf("file://") === 0) return name

  // Standardize known place aliases that don't have dedicated icons in Adwaita/Yaru
  var placeAliases = {
    "folder-development": "folder",
    "folder-projects": "folder",
    "folder-code": "folder",
    "folder-git": "folder",
    "folder-github": "folder",
    "folder-src": "folder",
    "folder-source": "folder",
    "folder-build": "folder"
  }
  if (placeAliases[name]) {
    name = placeAliases[name]
  }

  // Whitelist of valid place icons guaranteed to exist in Adwaita / Yaru place icon themes
  var validPlaces = [
    "folder", "folder-documents", "folder-download", "folder-music",
    "folder-pictures", "folder-publicshare", "folder-remote",
    "folder-templates", "folder-videos", "user-home", "user-desktop", "user-trash"
  ]
  if (validPlaces.indexOf(name) < 0) {
    name = "folder"
  }

  // Explicit white, black, or symbolic mode — deliberately monochrome Adwaita outlines.
  // These are intentionally hardcoded for B&W Omarchy themes (vantablack, white, etc.)
  // and must NOT be intercepted by the iconIndex which may return colored variants.
  if (folderColorMode === "white" || folderColorMode === "black" || folderColorMode === "bw" || folderColorMode === "symbolic") {
    return "file:///usr/share/icons/Adwaita/symbolic/places/" + name + "-symbolic.svg"
  }

  // Explicit custom Yaru color preset (user chose a specific variant):
  if (folderColorMode && folderColorMode !== "theme" && folderColorMode !== "auto") {
    var customTheme = folderColorMode
    if (customTheme.indexOf("Yaru") === 0) {
      return "file:///usr/share/icons/" + customTheme + "/256x256/places/" + name + ".png"
    }
  }

  // Automatic theme mode:
  var theme = String(themeName || "").trim()

  // 1. If valid Yaru variant theme (user's active icon theme):
  if (theme.indexOf("Yaru-") === 0 && theme !== "Yaru-gray" && theme !== "Yaru-grey") {
    return "file:///usr/share/icons/" + theme + "/256x256/places/" + name + ".png"
  }
  if (theme === "Yaru") {
    return "file:///usr/share/icons/Yaru/256x256/places/" + name + ".png"
  }

  // 2. Any other installed theme (Papirus, WhiteSur, Tela...): the library's
  // index reads the active theme first, so its answer is that theme's folder.
  // Yaru-gray and Yaru-grey are the B&W markers Omarchy's dark themes name
  // (and yaru-icon-theme no longer ships): those keep the monochrome outline
  // the aesthetic depends on, so they are excluded here rather than resolved.
  var bwTheme = theme === "" || theme === "Yaru-gray" || theme === "Yaru-grey"
  if (!bwTheme && appLibrary) {
    var src = appLibrary.iconSource(name)
    if (src && src.length > 0) return src
  }

  // 3. No theme artwork at all: Adwaita's monochrome outline, which reads on
  // any backdrop. Only reached when the library cannot resolve a path.
  return "file:///usr/share/icons/Adwaita/symbolic/places/" + name + "-symbolic.svg"
}

function resolveFileItemIcon(iconName, themeName, folderColorMode, appLibrary) {
  var name = String(iconName || "text-x-generic").trim()
  if (name.indexOf("/") === 0 || name.indexOf("file://") === 0) return name

  // If it is a folder / place icon:
  if (name === "folder" || name.indexOf("folder-") === 0 || name.indexOf("user-") === 0) {
    return resolveThemedFolderIcon(name, themeName, folderColorMode, appLibrary)
  }

  // Resolve mimetypes through iconIndex for theme resilience
  if (appLibrary) {
    var src = appLibrary.iconSource(name)
    if (src && src.length > 0) return src
  }

  // Known mimetypes — hardcoded Yaru fallback only if iconIndex missed
  var knownMimetypes = [
    "image-x-generic", "video-x-generic", "audio-x-generic",
    "package-x-generic", "application-pdf", "text-x-generic",
    "application-x-executable"
  ]
  if (knownMimetypes.indexOf(name) >= 0) {
    return "file:///usr/share/icons/Yaru/256x256/mimetypes/" + name + ".png"
  }

  return appLibrary ? appLibrary.iconSource("text-x-generic") : "file:///usr/share/icons/Yaru/256x256/mimetypes/text-x-generic.png"
}
