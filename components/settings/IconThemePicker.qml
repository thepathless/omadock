import QtQuick 6.11
import qs.Commons
import qs.Ui
import "../strings"
import "../../DockIconTheme.js" as DockIconTheme

// The desktop's icon theme (Settings > Look > Icons). One owner for the list
// and the apply: the theme is shared by every app, so this is not a dock
// option - scripts/icon-theme.sh writes gsettings, both GTK settings files,
// ~/.icons/default and the KDE/Qt files when they exist.
//
// One searchable dropdown, not a wall of chips: it opens from the theme in
// use, filters as you type and works entirely from the keyboard (type,
// arrows, Enter applies, Escape closes without applying). The shell's own
// SearchableDropdown is the reference control, so it behaves like every other
// Omarchy picker; its colours come from the active theme's menu tokens.

Column {
  id: picker
  property var root: null
  property var panel: null

  width: parent.width
  spacing: Style.spacing.md

  readonly property var library: picker.root ? picker.root.iconThemeRef : null
  readonly property string current: picker.library ? picker.library.iconTheme : ""
  readonly property var installed: picker.library ? picker.library.themes : []
  readonly property bool installing: picker.library ? picker.library.themeInstalling : false
  // WhiteSur is the one look worth offering to fetch: the macOS icon set most
  // people install by hand. Once it is on disk it is just another theme.
  readonly property bool whiteSurInstalled: {
    for (var i = 0; i < picker.installed.length; i++)
      if (picker.installed[i].id.indexOf("WhiteSur") === 0) return true
    return false
  }
  // DockIconTheme.safeId only accepts ids that start with a letter or digit,
  // so this can never name an installed theme.
  readonly property string installId: "__install_whitesur__"
  // The install action leads the list while the macOS set is absent, so it is
  // the first thing the dropdown shows rather than a row past 25 themes; then
  // the installed themes (id, display name, what it builds on).
  readonly property var options: {
    var out = []
    if (!picker.whiteSurInstalled)
      out.push({
        value: picker.installId,
        label: Tr.t("iconTheme.installWhiteSur", "Install WhiteSur…"),
        description: Tr.t("iconTheme.installWhiteSurHint", "macOS Big Sur icons, downloaded once into your home folder and applied.")
      })
    for (var i = 0; i < picker.installed.length; i++)
      out.push({
        value: picker.installed[i].id,
        label: picker.installed[i].name,
        description: DockIconTheme.subtitle(picker.installed[i])
      })
    return out
  }

  Component.onCompleted: if (picker.library) picker.library.refreshThemes()

  // The chosen value goes through the existing system-wide path; the install
  // entry is an action, not a theme, so it never reaches setIconTheme.
  function choose(value) {
    if (!picker.library) return
    if (value === picker.installId) {
      dropdown.value = picker.current
      picker.library.installWhiteSur()
      return
    }
    picker.library.setIconTheme(value)
  }

  SearchableDropdown {
    id: dropdown
    objectName: "settings-icon-theme-dropdown"
    width: Style.space(340)
    options: picker.options
    showLabel: false
    enabled: !picker.installing
    foreground: Color.menu.text
    background: Color.menu.background
    popupBorder: Color.menu.border
    fontFamily: Style.font.family
    placeholderText: Tr.t("iconTheme.search", "Search installed icon themes")
    emptyText: Tr.t("iconTheme.none", "No icon theme matches that search.")
    onChanged: function(value) { picker.choose(value) }
    // The panel's own Escape shortcut must stand down while the list is open,
    // or dismissing the dropdown would dismiss the whole panel with it.
    onPopupOpenChanged: if (picker.panel) picker.panel.iconThemeDropdownOpen = dropdown.popupOpen
  }

  // The dropdown writes its own value when a row is picked; keep it on the
  // theme the desktop actually uses, including after a failed apply.
  Binding {
    target: dropdown
    property: "value"
    value: picker.current
    restoreMode: Binding.RestoreNone
  }

  Text {
    width: parent.width
    visible: picker.installing
    text: Tr.t("iconTheme.whiteSurBusy", "Installing WhiteSur…")
    textFormat: Text.PlainText
    color: Util.alpha(Color.menu.text, 0.7)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Text {
    width: parent.width
    visible: picker.library ? picker.library.themeError !== "" : false
    text: picker.library ? picker.library.themeError : ""
    textFormat: Text.PlainText
    color: Color.urgent
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Text {
    width: parent.width
    text: Tr.t("iconTheme.note", "Applies to the whole desktop. Apps that are already open pick it up when they restart.")
    textFormat: Text.PlainText
    color: Util.alpha(Color.menu.text, 0.4)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  // Off-screen helper: announce a finished apply through the panel's own
  // flash, so the row that changed is visible even if the list moved.
  Connections {
    target: picker.library
    function onIconThemeChanged() { if (picker.panel) picker.panel.setFlash("iconTheme") }
    function onThemeErrorChanged() {
      if (picker.library && picker.library.themeError !== "") dropdown.value = picker.current
    }
  }
}
