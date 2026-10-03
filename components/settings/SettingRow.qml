import QtQuick
import qs.Commons
import qs.Ui

// Base settings row: label + optional hint on the left, control slot on
// the right. A non-empty key makes the row a search target; SettingsPanel
// registers it and sets highlighted when its search hit is picked.

Item {
  id: settingRow
  property string label: ""
  property string hint: ""
  // Search key: the SETTINGS_SEARCH entry whose hit jumps here. Rows
  // without one are not reachable from the search box.
  property string key: ""
  // Set by SettingsPanel while this row is the picked search target.
  property bool highlighted: false
  default property alias control: slot.data

  Rectangle {
    anchors.fill: parent
    radius: Style.space(8)
    color: settingRow.highlighted ? Util.alpha(Color.accent, 0.14) : "transparent"
    Behavior on color {
      ColorAnimation { duration: 350 }
    }
  }

  width: parent ? parent.width : Style.space(420)
  implicitHeight: Math.max(Style.space(44), texts.implicitHeight + Style.spacing.lg * 2, slot.childrenRect.height + Style.spacing.md * 2)

  Column {
    id: texts
    anchors.left: parent.left
    anchors.right: slot.left
    anchors.rightMargin: Style.spacing.xxl
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xxs

    // Folder names, group names and paths reach these two unwrapped: they
    // are always plain text, never markup.
    Text {
      width: parent.width
      text: settingRow.label
      textFormat: Text.PlainText
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: settingRow.hint !== ""
      text: settingRow.hint
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Item {
    id: slot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width
    height: childrenRect.height
  }

  Rectangle {
    anchors.bottom: parent.bottom
    width: parent.width
    height: 1
    color: Util.alpha(Color.menu.text, 0.10)
  }
}
