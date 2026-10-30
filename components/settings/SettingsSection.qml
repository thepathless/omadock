import QtQuick 6.11
import qs.Commons
import qs.Ui
import "../strings"

Column {
  id: section
  property string title: ""
  property bool expanded: false
  default property alias content: body.data
  width: parent.width

  Button {
    objectName: "settings-disclosure-" + section.title
    width: parent.width
    leftAlign: true
    text: (section.expanded ? "▾ " : "▸ ") + section.title
    foreground: Color.menu.text
    focusable: true
    bordered: true
    onClicked: section.expanded = !section.expanded
    Accessible.role: Accessible.Button
    Accessible.name: section.title
    Accessible.expanded: section.expanded
  }
  Column {
    id: body
    width: parent.width
    visible: section.expanded
  }
}
