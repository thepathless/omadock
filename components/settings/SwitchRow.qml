import QtQuick
import qs.Commons
import qs.Ui

// SettingRow with a toggle switch.

SettingRow {
  id: switchRow
  property bool checked: false
  signal toggled()

  ToggleSwitch {
    checked: switchRow.checked
    foreground: Color.menu.text
    onToggled: switchRow.toggled()
  }
}
