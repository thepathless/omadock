import QtQuick
import qs.Commons
import qs.Ui

// Section heading for a settings page; can carry a search key so a whole
// section ("Folder color") is reachable from the search box.

Text {
  id: sectionLabel
  // Search key, as on SettingRow: lets a whole section ("Folder color",
  // "Presets") be a search target even though it has no control row.
  property string key: ""
  // Set by SettingsPanel while this section is the picked search target.
  property bool highlighted: false

  Rectangle {
    anchors.fill: parent
    radius: Style.space(8)
    color: sectionLabel.highlighted ? Util.alpha(Color.accent, 0.14) : "transparent"
    Behavior on color {
      ColorAnimation { duration: 350 }
    }
  }

  width: parent ? parent.width : implicitWidth
  topPadding: Style.spacing.xxl
  bottomPadding: Style.spacing.sm
  text: ""
  textFormat: Text.PlainText
  color: Util.alpha(Color.menu.text, 0.55)
  font.family: Style.font.family
  font.pixelSize: Style.font.caption
  font.capitalization: Font.AllUppercase
  font.letterSpacing: 1
}
