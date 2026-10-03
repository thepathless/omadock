import QtQuick
import qs.Commons
import qs.Ui

// Settings page: group look rows and the app group list.
// Instantiated by SettingsPanel, which injects root (the Dock, for
// values and setters) and panel (page/edit state).

Column {
  property var root: null
  property var panel: null
  width: parent.width


  SectionLabel { text: "Look" }

  ChoiceRow {
    key: "groupStyle"
    label: "Tile style"
    hint: "Frame drawn around a group's icons in the dock."
    options: [
      { value: "rounded", label: "Rounded" },
      { value: "square", label: "Square" },
      { value: "none", label: "None" }
    ]
    value: root ? root.groupStyle : "rounded"
    onPicked: function(v) { root.setOption("groupStyle", v) }
  }
  ChoiceRow {
    key: "groupIconEffects"
    label: "Icon style"
    hint: "Theme applies the style from the Icons page to the icons of an opened group."
    options: [
      { value: "theme", label: "Theme" },
      { value: "none", label: "None" }
    ]
    value: root ? root.groupIconEffects : "theme"
    onPicked: function(v) { root.setOption("groupIconEffects", v) }
  }

  SectionLabel { text: "Groups" }

  Text {
    width: parent.width
    visible: !root || root.appGroups.length === 0
    topPadding: Style.spacing.lg
    bottomPadding: Style.spacing.lg
    text: "No groups yet. Drag one dock icon onto another, or create one from the apps that are running now."
    textFormat: Text.PlainText
    color: Util.alpha(Color.menu.text, 0.55)
    wrapMode: Text.WordWrap
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Repeater {
    model: root ? root.appGroups : []
    // The group name reads as plain text; clicking it turns it into
    // a field. Enter saves, Esc or clicking elsewhere cancels.
    delegate: Item {
      id: groupRow
      required property var modelData
      readonly property int appCount: modelData.apps ? modelData.apps.length : 0
      readonly property bool editing: panel.editingGroupId === modelData.id

      function startEdit() {
        panel.editingGroupId = groupRow.modelData.id
        nameField.text = groupRow.modelData.name || ""
        nameField.forceActiveFocus()
        nameField.selectAll()
      }

      function finishEdit(save) {
        if (!groupRow.editing) return
        var next = nameField.text.trim()
        panel.editingGroupId = ""
        panel.refocus()
        if (save && next !== "" && next !== groupRow.modelData.name)
          root.renameAppGroup(groupRow.modelData.id, next)
      }

      width: parent ? parent.width : Style.space(420)
      implicitHeight: Math.max(Style.space(52), groupTexts.implicitHeight + Style.spacing.lg * 2)

      Column {
        id: groupTexts
        anchors.left: parent.left
        anchors.right: removeButton.left
        anchors.rightMargin: Style.spacing.xxl
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Item {
          width: parent.width
          height: Math.max(nameLabel.implicitHeight, groupRow.editing ? nameField.implicitHeight : 0)

          Row {
            id: nameLabel
            visible: !groupRow.editing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md

            Text {
              text: groupRow.modelData.name || "Group"
              textFormat: Text.PlainText
              color: nameMouse.containsMouse ? Color.accent : Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: nameMouse.containsMouse
              text: "󰏫"
              textFormat: Text.PlainText
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          MouseArea {
            id: nameMouse
            visible: !groupRow.editing
            anchors.fill: nameLabel
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            onClicked: groupRow.startEdit()
          }

          TextField {
            id: nameField
            visible: groupRow.editing
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width, Style.space(260))
            placeholderText: "Group name"
            maximumLength: 120   // DockModel.MAX_APP_GROUP_NAME
            foreground: Color.menu.text
            Keys.onReturnPressed: groupRow.finishEdit(true)
            Keys.onEnterPressed: groupRow.finishEdit(true)
            Keys.onEscapePressed: groupRow.finishEdit(false)
            onActiveFocusChanged: if (!activeFocus) groupRow.finishEdit(false)
          }
        }

        Text {
          width: parent.width
          text: {
            var names = []
            var apps = groupRow.modelData.apps || []
            for (var i = 0; i < apps.length; i++) {
              var entry = root ? root.entryForId(apps[i]) : null
              names.push(entry && entry.name ? entry.name : String(apps[i]))
            }
            var count = groupRow.appCount + (groupRow.appCount === 1 ? " app" : " apps")
            return names.length > 0 ? count + " · " + names.join(", ") : count
          }
          textFormat: Text.PlainText
          color: Util.alpha(Color.menu.text, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Button {
        id: removeButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Remove"
        foreground: Color.menu.text
        bordered: true
        onClicked: root.removeAppGroup(groupRow.modelData.id)
      }

      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Util.alpha(Color.menu.text, 0.10)
      }
    }
  }

  Item { width: 1; height: Style.spacing.xxl }

  Button {
    text: "Create group from running apps"
    foreground: Color.menu.text
    bordered: true
    onClicked: root.createAppGroupFromRunning()
  }
}
