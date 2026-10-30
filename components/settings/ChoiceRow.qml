import QtQuick 6.11
import qs.Commons
import qs.Ui
import "../strings"

// SettingRow with a button-group choice.

SettingRow {
  id: choiceRow
  property var options: []
  property string value: ""
  signal picked(string value)

  ButtonGroup {
    // "setting.<key>.option.<value>"; options built at run time (monitor
    // names) have no entry and keep their label.
    options: choiceRow.options.map(function(o) {
      return choiceRow.key === "" ? o : Object.assign({}, o, { label: Tr.t("setting." + choiceRow.key + ".option." + o.value, o.label) })
    })
    value: choiceRow.value
    foreground: Color.menu.text
    background: Color.menu.background
    focusable: true
    objectName: "settings-choice-" + choiceRow.key
    onActiveFocusChanged: if (activeFocus && choiceRow.settingsPanel) choiceRow.settingsPanel.keepFocusVisible(choiceRow)
    onChanged: function(v) { choiceRow.picked(v) }
  }
}
