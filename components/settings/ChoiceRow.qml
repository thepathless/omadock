import QtQuick
import qs.Commons
import qs.Ui

// SettingRow with a button-group choice.

SettingRow {
  id: choiceRow
  property var options: []
  property string value: ""
  signal picked(string value)

  ButtonGroup {
    options: choiceRow.options
    value: choiceRow.value
    foreground: Color.menu.text
    background: Color.menu.background
    focusable: false
    onChanged: function(v) { choiceRow.picked(v) }
  }
}
