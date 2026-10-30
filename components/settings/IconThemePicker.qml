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
// Chips rather than a dropdown: the installed set is small, wrapping keeps the
// whole list visible without a second scroll area inside the page, and every
// chip is a real focus stop.

Column {
  id: picker
  property var root: null
  property var panel: null
  property string query: ""

  width: parent.width
  spacing: Style.spacing.md

  readonly property var library: picker.root ? picker.root.iconThemeRef : null
  readonly property var matches: library ? DockIconTheme.filter(library.themes, picker.query) : []
  readonly property string current: library ? library.iconTheme : ""
  // WhiteSur is the one look worth offering to fetch: the macOS icon set most
  // people install by hand. Once it is installed it is just another chip.
  readonly property bool whiteSur: {
    var list = picker.library ? picker.library.themes : []
    for (var i = 0; i < list.length; i++) if (list[i].id.indexOf("WhiteSur") === 0) return true
    return false
  }

  Component.onCompleted: if (picker.library) picker.library.refreshThemes()

  Text {
    width: parent.width
    text: picker.current === ""
      ? Tr.t("iconTheme.unknown", "Reading the desktop's icon theme…")
      : Tr.t("iconTheme.current", "Every app uses %1.").arg(picker.current)
    textFormat: Text.PlainText
    color: Util.alpha(Color.menu.text, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  TextField {
    id: filter
    width: parent.width
    objectName: "settings-icon-theme-search"
    placeholderText: Tr.t("iconTheme.search", "Search installed icon themes")
    foreground: Color.menu.text
    onTextChanged: picker.query = text
  }

  Flow {
    width: parent.width
    spacing: Style.spacing.sm

    Repeater {
      model: picker.matches
      delegate: Button {
        required property var modelData
        objectName: "settings-icon-theme-" + modelData.id
        text: modelData.name
        tooltipText: DockIconTheme.subtitle(modelData)
        foreground: Color.menu.text
        selected: modelData.id === picker.current
        bordered: true
        focusable: true
        Accessible.role: Accessible.RadioButton
        Accessible.name: modelData.name
        Accessible.description: DockIconTheme.subtitle(modelData)
        onClicked: if (picker.library) picker.library.setIconTheme(modelData.id)
        onActiveFocusChanged: if (activeFocus && picker.panel) picker.panel.keepFocusVisible(this)
      }
    }
  }

  // macOS look, one click: downloads upstream's GPL icon set into
  // ~/.local/share/icons and applies it. Hidden once any WhiteSur variant is
  // installed, because the chips above already carry it.
  Row {
    width: parent.width
    spacing: Style.spacing.md
    visible: picker.library ? !picker.whiteSur : false

    Button {
      focusable: true
      objectName: "settings-icon-theme-whitesur"
      text: picker.library && picker.library.themeInstalling
        ? Tr.t("iconTheme.whiteSurBusy", "Installing WhiteSur…")
        : Tr.t("iconTheme.whiteSur", "Install WhiteSur")
      foreground: Color.menu.text
      bordered: true
      enabled: picker.library ? !picker.library.themeInstalling : false
      onClicked: if (picker.library) picker.library.installWhiteSur()
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - parent.children[0].width - Style.spacing.md
      text: Tr.t("iconTheme.whiteSurHint", "macOS Big Sur icons, downloaded once into your home folder.")
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Text {
    width: parent.width
    visible: picker.matches.length === 0
    text: Tr.t("iconTheme.none", "No installed theme matches. Install one, then reopen this page.")
    textFormat: Text.PlainText
    color: Util.alpha(Color.menu.text, 0.55)
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
  }
}
