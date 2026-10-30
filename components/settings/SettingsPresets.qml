import QtQuick 6.11
import qs.Commons
import qs.Ui
import "../strings"

import ".."
import "../../DockPresets.js" as DockPresets

// Settings page: the look preset list and save/rename/delete actions.
// The list holds the shipped looks (DockPresets.js) first, then the ones the
// user saved; only the saved ones can be renamed, updated or deleted.
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
      title: "Presets"
    }
  }

  Text {
    width: parent.width
    topPadding: Style.spacing.xs
    bottomPadding: Style.spacing.lg
    text: (root ? DockPresets.userCount(root.presets) : 0) + " of 6 saved · the shipped looks come with the dock · A preset keeps the look: background, effects, border, dividers, icons, label style, size and spacing."
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
      readonly property bool builtin: modelData.builtin === true

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
        activeFocusOnTab: true
        Keys.onReturnPressed: { panel.endPresetEdit(); root.applyPreset(presetRow.modelData.id) }
        Keys.onSpacePressed: { panel.endPresetEdit(); root.applyPreset(presetRow.modelData.id) }
        Rectangle {
          anchors.fill: parent
          visible: thumbView.activeFocus
          color: "transparent"
          border.width: 2
          border.color: Color.accent
          radius: Style.cornerRadius
        }
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
            text: Tr.t("presets.apply", "Apply")
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
          objectName: "settings-preset-name-" + presetRow.modelData.id
          activeFocusOnTab: !presetRow.builtin && !presetRow.editing
          Keys.onReturnPressed: if (!presetRow.builtin) presetRow.startEdit()
          Keys.onSpacePressed: if (!presetRow.builtin) presetRow.startEdit()
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
            color: presetMouse.containsMouse || parent.activeFocus ? Color.accent : Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
          }
          MouseArea {
            id: presetMouse
            visible: !presetRow.editing
            anchors.fill: presetLabel
            hoverEnabled: true
            cursorShape: presetRow.builtin ? Qt.ArrowCursor : Qt.IBeamCursor
            onClicked: if (!presetRow.builtin) presetRow.startEdit()
          }
          TextField {
            id: presetName
            visible: presetRow.editing
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width, Style.space(220))
            maximumLength: 40
            placeholderText: Tr.t("presets.namePlaceholder", "Preset name")
            foreground: Color.menu.text
            Keys.onReturnPressed: presetRow.finishEdit(true)
            Keys.onEnterPressed: presetRow.finishEdit(true)
            Keys.onEscapePressed: presetRow.finishEdit(false)
            onActiveFocusChanged: if (!activeFocus) presetRow.finishEdit(false)
          }
        }

        Text {
          visible: presetRow.builtin
          text: "shipped with the dock"
          textFormat: Text.PlainText
          color: Util.alpha(Color.menu.text, 0.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: presetActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.md

        Button {
          focusable: true
          visible: !presetRow.confirming
          text: Tr.t("presets.apply", "Apply")
          foreground: Color.accent
          onClicked: { panel.endPresetEdit(); root.applyPreset(presetRow.modelData.id) }
        }
        Button {
          focusable: true
          visible: !presetRow.confirming && !presetRow.builtin
          text: Tr.t("presets.update", "Update")
          foreground: Color.menu.text
          onClicked: { panel.endPresetEdit(); root.updatePreset(presetRow.modelData.id) }
        }
        Button {
          focusable: true
          visible: !presetRow.confirming && !presetRow.builtin
          text: Tr.t("presets.delete", "Delete")
          foreground: Color.menu.text
          onClicked: { panel.endPresetEdit(); panel.confirmDeletePresetId = presetRow.modelData.id }
        }
        Button {
          focusable: true
          visible: presetRow.confirming
          // Button text is not pinned to PlainText: no name here.
          text: Tr.t("presets.deleteConfirm", "Delete?")
          foreground: Color.urgent
          bordered: true
          onClicked: {
            panel.confirmDeletePresetId = ""
            root.deletePreset(presetRow.modelData.id)
          }
        }
        Button {
          focusable: true
          visible: presetRow.confirming
          text: Tr.t("presets.keep", "Keep")
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
    focusable: true
    text: root && root.canSavePreset ? Tr.t("presets.save", "Save current look") : Tr.t("presets.full", "6 of 6 — delete one to save a new look")
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
