import QtQuick 6.11
import qs.Commons
import qs.Ui

// SettingRow with a toggle switch.

SettingRow {
  id: switchRow
  property bool checked: false
  signal toggled()

  ToggleSwitch {
    objectName: "settings-switch-" + switchRow.key
    checked: switchRow.checked
    activeFocusOnTab: true
    hasCursor: activeFocus
    Keys.onSpacePressed: switchRow.toggled()
    Keys.onReturnPressed: switchRow.toggled()
    onActiveFocusChanged: if (activeFocus && switchRow.settingsPanel) switchRow.settingsPanel.keepFocusVisible(switchRow)
    foreground: Color.menu.text
    onToggled: switchRow.toggled()
  }
}
