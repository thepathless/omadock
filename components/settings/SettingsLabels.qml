import QtQuick 6.11
import qs.Commons
import qs.Ui
import "../../DockLabels.js" as DockLabels
import "../strings"

// Settings page: name labels beside the dock icons — when they show, how
// they look, and per-app names. Instantiated by SettingsPanel, which injects
// root (the Dock) and panel. Renaming also works in place from an app's
// right-click menu (ContextRenameRow).

Column {
  id: labelsPage
  property var root: null
  property var panel: null
  width: parent.width

  // Name rows rebuild only when the listed apps change: the dock model is
  // replaced on every window-title event, which would drop the focus of a
  // field being typed in.
  property var nameRows: []
  function refreshNameRows() {
    var rows = labelsPage.root ? labelsPage.root.labelNameRows() : []
    if (DockLabels.nameRowsKey(rows) !== DockLabels.nameRowsKey(labelsPage.nameRows)) labelsPage.nameRows = rows
  }
  Connections {
    target: labelsPage.root
    function onDockModelChanged() { labelsPage.refreshNameRows() }
  }
  Component.onCompleted: labelsPage.refreshNameRows()

  SectionLabel { title: "Labels" }

  ChoiceRow {
    key: "labelMode"
    label: "Labels"
    hint: "Names beside the icons: always, or slid out while the pointer rests on an icon."
    options: [
      { value: "off", label: "Off" },
      { value: "always", label: "Always" },
      { value: "hover", label: "On hover" }
    ]
    value: root ? root.labelMode : "off"
    onPicked: function(v) { root.setOption("labelMode", v) }
  }

  Column {
    width: parent.width
    visible: (root ? root.labelMode !== "off" : false) || (panel ? panel.targetKey.indexOf("label") === 0 : false)

    ChoiceRow {
      key: "labelKind"
      label: "Show on"
      options: [
        { value: "all", label: "All" },
        { value: "apps", label: "Apps" },
        { value: "groups", label: "App groups" },
        { value: "folders", label: "Folders" }
      ]
      value: root ? root.labelKind : "all"
      onPicked: function(v) { root.setOption("labelKind", v) }
    }
    ChoiceRow {
      key: "labelPinned"
      label: "Pinned apps"
      hint: "When running shows a pinned app's name only while it has a window; a closed one keeps just its icon."
      available: root ? (root.labelMode === "always" && (root.labelKind === "all" || root.labelKind === "apps")) : false
      options: [
        { value: "always", label: "Always" },
        { value: "running", label: "When running" }
      ]
      value: root ? root.labelPinned : "always"
      onPicked: function(v) { root.setOption("labelPinned", v) }
    }

    SettingsSection {
      title: Tr.t("settings.labelTuning", "Advanced label styling")
    SectionLabel { title: "Look" }

    ChoiceRow {
      key: "labelFont"
      label: "Font"
      options: [
        { value: "theme", label: "Theme" },
        { value: "sans", label: "Sans" },
        { value: "pixel", label: "Pixel" }
      ]
      value: root ? root.labelFont : "theme"
      onPicked: function(v) { root.setOption("labelFont", v) }
    }
    ChoiceRow {
      key: "labelSize"
      label: "Size"
      options: [
        { value: "small", label: "Small" },
        { value: "medium", label: "Medium" },
        { value: "large", label: "Large" }
      ]
      value: root ? root.labelSize : "medium"
      onPicked: function(v) { root.setOption("labelSize", v) }
    }
    ChoiceRow {
      key: "labelWeight"
      label: "Weight"
      available: root ? root.labelFont !== "pixel" : true
      options: [
        { value: "regular", label: "Regular" },
        { value: "medium", label: "Medium" },
        { value: "bold", label: "Bold" }
      ]
      value: root ? root.labelWeight : "medium"
      onPicked: function(v) { root.setOption("labelWeight", v) }
    }
    ChoiceRow {
      key: "labelColor"
      label: "Color"
      hint: "Auto picks black or white for what is behind the icons; Theme uses the bar's text colour."
      options: [
        { value: "auto", label: "Auto" },
        { value: "theme", label: "Theme" },
        { value: "accent", label: "Accent" }
      ]
      value: root ? root.labelColor : "auto"
      onPicked: function(v) { root.setOption("labelColor", v) }
    }
    ChoiceRow {
      key: "labelBackground"
      label: "Background"
      hint: "Plate puts icon and name on one surface, like a button."
      available: root ? root.labelMode !== "hover" : true
      options: [
        { value: "none", label: "None" },
        { value: "pill", label: "Pill" },
        { value: "plate", label: "Plate" }
      ]
      value: root ? root.labelBackground : "none"
      onPicked: function(v) { root.setOption("labelBackground", v) }
    }
    ChoiceRow {
      key: "labelShape"
      label: "Corners"
      hint: "Dock follows the dock's own corners. Square meets between plates and rounds the outer ones along the dock's edge; Pill gives every plate round ends."
      available: root ? (root.labelBackground !== "none" || root.labelMode === "hover") : true
      options: [
        { value: "dock", label: "Dock" },
        { value: "pill", label: "Pill" },
        { value: "rounded", label: "Rounded" },
        { value: "square", label: "Square" }
      ]
      value: root ? root.labelShape : "dock"
      onPicked: function(v) { root.setOption("labelShape", v) }
    }
    ChoiceRow {
      key: "labelPlateHeight"
      label: "Plate height"
      hint: "Dock stretches plates to the dock's top and bottom, the same gap away as from each other."
      available: root ? (root.labelBackground === "plate" && root.labelMode === "always") : false
      options: [
        { value: "icon", label: "Icon" },
        { value: "dock", label: "Dock" }
      ]
      value: root ? root.labelPlateHeight : "icon"
      onPicked: function(v) { root.setOption("labelPlateHeight", v) }
    }
    ChoiceRow {
      key: "labelIndicators"
      label: "Indicators"
      hint: "Window marks as a column at the plate's edge, so every plate lines up."
      available: root ? (root.labelBackground === "plate" && root.labelMode === "always") : false
      options: [
        { value: "before", label: "Before icon" },
        { value: "after", label: "After name" },
        { value: "under", label: "Under icon" }
      ]
      value: root ? root.labelIndicators : "before"
      onPicked: function(v) { root.setOption("labelIndicators", v) }
    }
    ChoiceRow {
      key: "labelReveal"
      label: "Reveal"
      hint: "How a name appears when the pointer rests on an icon."
      available: root ? root.labelMode === "hover" : false
      options: [
        { value: "slide", label: "Slide" },
        { value: "typewriter", label: "Typewriter" },
        { value: "scramble", label: "Scramble" }
      ]
      value: root ? root.labelReveal : "slide"
      onPicked: function(v) { root.setOption("labelReveal", v) }
    }
    ChoiceRow {
      key: "labelEffect"
      label: "Effect"
      options: [
        { value: "none", label: "None" },
        { value: "glow", label: "Glow" },
        { value: "outline", label: "Outline" }
      ]
      value: root ? root.labelEffect : "none"
      onPicked: function(v) { root.setOption("labelEffect", v) }
    }
    SliderRow {
      key: "labelMaxWidth"
      label: "Max width"
      hint: "Longer names drop subtitles, then trailing words, then end in an ellipsis."
      minimum: DockLabels.LABEL_MAX_WIDTH_MIN
      maximum: DockLabels.LABEL_MAX_WIDTH_MAX
      step: 10
      suffix: " px"
      value: root ? root.labelMaxWidth : 140
      onCommitted: function(v) { root.setOption("labelMaxWidth", Math.round(v)) }
    }

    }
    SectionLabel { title: "Names"; visible: root ? root.labelKind === "all" || root.labelKind === "apps" : false }

    Repeater {
      model: (root && (root.labelKind === "all" || root.labelKind === "apps")) ? labelsPage.nameRows : []
      delegate: Item {
        id: nameRow
        required property var modelData
        // The stored name, read live (own keys only: an app id can be any string).
        readonly property string storedName: (labelsPage.root && Object.prototype.hasOwnProperty.call(labelsPage.root.labelNames, nameRow.modelData.appId))
          ? labelsPage.root.labelNames[nameRow.modelData.appId] : ""
        width: labelsPage.width
        implicitHeight: Style.space(44)

        Text {
          anchors.left: parent.left
          anchors.right: nameField.left
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          text: nameRow.modelData.auto
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        TextField {
          id: nameField
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(220)
          text: nameRow.storedName
          placeholderText: nameRow.modelData.auto
          maximumLength: DockLabels.MAX_LABEL_NAME
          foreground: Color.menu.text
          function commit() {
            if (text !== nameRow.storedName) labelsPage.root.setLabelName(nameRow.modelData.appId, text)
          }
          Keys.onReturnPressed: { commit(); labelsPage.panel.refocus() }
          Keys.onEnterPressed: { commit(); labelsPage.panel.refocus() }
          onActiveFocusChanged: if (!activeFocus) commit()
        }
      }
    }
  }
}
