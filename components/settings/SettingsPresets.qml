import QtQuick
import qs.Commons
import qs.Ui

import ".."

// Settings page: the look preset list and save/rename/delete actions.
// Instantiated by SettingsPanel, which injects root (the Dock, for
// values and setters) and panel (page/edit state).

Column {
  property var root: null
  property var panel: null
  width: parent.width


  Row {
    width: parent.width
    SectionLabel {
      key: "presets"
      text: "Presets"
    }
  }

  Text {
    width: parent.width
    topPadding: Style.spacing.xs
    bottomPadding: Style.spacing.lg
    text: (root ? root.presets.length : 0) + " of 6 · A preset keeps the look: background, effects, border, dividers, icons, size and spacing."
    textFormat: Text.PlainText
    color: Util.alpha(Color.menu.text, 0.55)
    wrapMode: Text.WordWrap
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: root ? root.presets : []
    delegate: Item {
      id: presetRow
      required property var modelData
      readonly property bool editing: panel.editingPresetId === modelData.id
      readonly property bool confirming: panel.confirmDeletePresetId === modelData.id

      function startEdit() {
        panel.editingPresetId = presetRow.modelData.id
        presetName.text = presetRow.modelData.name || ""
        presetName.forceActiveFocus()
        presetName.selectAll()
      }
      function finishEdit(save) {
        if (!presetRow.editing) return
        var next = presetName.text
        panel.editingPresetId = ""
        panel.refocus()
        if (save) root.renamePreset(presetRow.modelData.id, next)
      }

      Connections {
        target: panel
        function onPresetEditRequested(id) { if (id === presetRow.modelData.id) presetRow.startEdit() }
      }

      width: parent ? parent.width : Style.space(420)
      implicitHeight: Math.max(thumbView.implicitHeight, presetTexts.implicitHeight) + Style.spacing.lg * 2

      // The thumbnail is the Apply button: an accent ring marks the
      // preset in use, hovering another one offers to apply it.
      Item {
        id: thumbView
        readonly property bool active: presetRow.modelData.id === root.activePresetId
        implicitWidth: thumbArt.implicitWidth
        implicitHeight: thumbArt.implicitHeight
        width: implicitWidth
        height: implicitHeight
        anchors.left: parent.left
        anchors.leftMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter

        PresetThumb {
          id: thumbArt
          anchors.fill: parent
          rootRef: root
          look: presetRow.modelData.look
        }

        Rectangle {
          anchors.fill: parent
          radius: Style.space(8)
          visible: thumbMouse.containsMouse && !thumbView.active
          color: Qt.rgba(0, 0, 0, 0.45)
          Text {
            anchors.centerIn: parent
            text: "Apply"
            textFormat: Text.PlainText
            color: "#ffffff"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: -Style.space(3)
          radius: Style.space(11)
          color: "transparent"
          visible: thumbView.active || thumbMouse.containsMouse
          border.width: Style.space(2)
          border.color: thumbView.active ? Color.accent : Util.alpha(Color.accent, 0.4)
        }

        MouseArea {
          id: thumbMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: thumbView.active ? Qt.ArrowCursor : Qt.PointingHandCursor
          onClicked: {
            panel.endPresetEdit()
            root.applyPreset(presetRow.modelData.id)
          }
        }
      }

      Column {
        id: presetTexts
        anchors.left: thumbView.right
        anchors.leftMargin: Style.spacing.xl + Style.space(3)
        anchors.right: presetActions.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Item {
          width: parent.width
          height: Math.max(presetLabel.implicitHeight, presetRow.editing ? presetName.implicitHeight : 0)

          Text {
            id: presetLabel
            visible: !presetRow.editing
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            text: (presetRow.modelData.id === root.activePresetId ? "✓ " : "") + presetRow.modelData.name
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: presetMouse.containsMouse ? Color.accent : Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
          }
          MouseArea {
            id: presetMouse
            visible: !presetRow.editing
            anchors.fill: presetLabel
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
            onClicked: presetRow.startEdit()
          }
          TextField {
            id: presetName
            visible: presetRow.editing
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width, Style.space(220))
            maximumLength: 40
            placeholderText: "Preset name"
            foreground: Color.menu.text
            Keys.onReturnPressed: presetRow.finishEdit(true)
            Keys.onEnterPressed: presetRow.finishEdit(true)
            Keys.onEscapePressed: presetRow.finishEdit(false)
            onActiveFocusChanged: if (!activeFocus) presetRow.finishEdit(false)
          }
        }
      }

      Row {
        id: presetActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.md

        Button {
          visible: !presetRow.confirming
          text: "Apply"
          foreground: Color.accent
          onClicked: { panel.endPresetEdit(); root.applyPreset(presetRow.modelData.id) }
        }
        Button {
          visible: !presetRow.confirming
          text: "Update"
          foreground: Color.menu.text
          onClicked: { panel.endPresetEdit(); root.updatePreset(presetRow.modelData.id) }
        }
        Button {
          visible: !presetRow.confirming
          text: "Delete"
          foreground: Color.menu.text
          onClicked: { panel.endPresetEdit(); panel.confirmDeletePresetId = presetRow.modelData.id }
        }
        Button {
          visible: presetRow.confirming
          // Button text is not pinned to PlainText: no name here.
          text: "Delete?"
          foreground: Color.urgent
          bordered: true
          onClicked: {
            panel.confirmDeletePresetId = ""
            root.deletePreset(presetRow.modelData.id)
          }
        }
        Button {
          visible: presetRow.confirming
          text: "Keep"
          foreground: Color.menu.text
          onClicked: panel.confirmDeletePresetId = ""
        }
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
    text: root && root.canSavePreset ? "Save current look" : "6 of 6 — delete one to save a new look"
    foreground: Color.menu.text
    bordered: true
    enabled: root ? root.canSavePreset : false
    opacity: enabled ? 1 : 0.5
    onClicked: {
      panel.endPresetEdit()
      var id = root.savePreset("")
      if (id !== "") Qt.callLater(function() { panel.startPresetEdit(id) })
    }
  }
}
