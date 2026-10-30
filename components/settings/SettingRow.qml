import QtQuick 6.11
import qs.Commons
import qs.Ui
import "../strings"

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
  property var settingsPanel: null
  property bool available: true
  readonly property bool targeted: !!settingsPanel && settingsPanel.targetKey === key
  readonly property var dependency: settingsPanel ? settingsPanel.dependencyFor(key) : null
  visible: available || targeted
  Accessible.role: Accessible.Grouping
  Accessible.name: shownLabel
  Accessible.description: shownHint
  // A row with a key translates its own texts ("setting.<key>.label" and
  // ".hint"); a page passes a row whose text changes already translated.
  readonly property string shownLabel: settingRow.key !== "" ? Tr.t("setting." + settingRow.key + ".label", settingRow.label) : settingRow.label
  readonly property string shownHint: {
    var ordinary = settingRow.key !== "" && settingRow.hint !== "" ? Tr.t("setting." + settingRow.key + ".hint", settingRow.hint) : settingRow.hint
    return ordinary + (settingRow.dependency ? (ordinary ? "\n" : "") + Tr.t("dependency." + settingRow.key, settingRow.dependency.text) : "")
  }
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
      text: settingRow.shownLabel
      textFormat: Text.PlainText
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: settingRow.shownHint !== ""
      text: settingRow.shownHint
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
    Button {
      objectName: "settings-prerequisite-" + settingRow.key
      visible: !!settingRow.dependency && settingRow.dependency.key !== ""
      text: Tr.t("settings.prerequisite", "Go to prerequisite")
      foreground: Color.menu.text
      focusable: true
      bordered: true
      onClicked: settingRow.settingsPanel.gotoSetting(settingRow.dependency.key)
    }
  }

  Item {
    id: slot
    enabled: settingRow.available && !settingRow.dependency
    opacity: enabled ? 1 : 0.45
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
