import QtQuick 6.11
import qs.Commons
import qs.Ui
import "../strings"

// Settings page: background, border, divider, shape and dock-item rows.
// Instantiated by SettingsPanel, which injects root (the Dock, for
// values and setters) and panel (page/edit state).

Column {
  property var root: null
  property var panel: null
  width: parent.width


  SectionLabel { title: "Background" }

  SwitchRow {
    key: "showBackground"
    label: "Background"
    hint: "Fill behind the icons. Off leaves the icons floating."
    checked: root ? root.showBackground : true
    onToggled: root.setOption("showBackground", !root.showBackground)
  }

  Column {
    width: parent.width
    visible: (root ? root.showBackground : true) || panel.revealGroup(["bgFill", "bgColor", "gradientPalette", "gradientStrength", "opacityTheme", "opacity"])

    ChoiceRow {
      key: "bgFill"
      label: "Fill"
      hint: "A solid colour, or colours melting into each other like Zen / Arc themes."
      options: [
        { value: "solid", label: "Solid" },
        { value: "gradient", label: "Gradient" }
      ]
      value: root ? root.bgFill : "solid"
      onPicked: function(v) { root.setOption("bgFill", v) }
    }

    Column {
      width: parent.width
      visible: (root ? root.bgFill !== "gradient" : true) || panel.revealGroup(["bgColor"])

      SettingRow {
        key: "bgColor"
        label: "Color"
        hint: "Theme, none, or a fixed preset."

        Row {
          spacing: Style.spacing.sm

          Button {
            focusable: true
            text: Tr.t("setting.gradient.theme", "Theme")
            foreground: Color.menu.text
            bordered: true
            selected: root ? (root.dockBgColor === "theme" || !root.dockBgColor) : true
            onClicked: root.setDockBgColor("theme")
          }
          Button {
            focusable: true
            text: Tr.t("setting.gradient.none", "None")
            foreground: Color.menu.text
            bordered: true
            selected: root ? root.dockBgColor === "none" : false
            onClicked: root.setDockBgColor("none")
          }
        }
      }

      Flow {
        enabled: !!root && root.showBackground && root.bgFill !== "gradient"
        opacity: enabled ? 1 : 0.45
        width: parent.width
        spacing: Style.spacing.md
        topPadding: Style.spacing.lg
        bottomPadding: Style.spacing.lg

        Repeater {
          model: [
            "#000000", "#181825", "#1e1e2e", "#0f172a", "#111827",
            "#062e24", "#1c1917", "#2c0b16", "#1e102d", "#334155"
          ]
          delegate: Swatch {
            required property string modelData
            color: modelData
            selected: root ? root.dockBgColor === modelData : false
            onPicked: root.setDockBgColor(modelData)
          }
        }
      }
    }

    Column {
      width: parent.width
      visible: (root ? root.bgFill === "gradient" : false) || panel.revealGroup(["gradientPalette", "gradientStrength"])

      SettingRow {
        key: "gradientPalette"
        label: "Palette"
        hint: "Theme builds one from the Omarchy theme's accent and palette."
      }

      Flow {
        enabled: !!root && root.showBackground && root.bgFill === "gradient"
        opacity: enabled ? 1 : 0.45
        width: parent.width
        spacing: Style.spacing.md
        topPadding: Style.spacing.sm
        bottomPadding: Style.spacing.lg

        Repeater {
          model: root ? [{ id: "theme", name: Tr.t("setting.gradient.theme", "Theme"), colors: root.themeGradientColors }].concat(root.gradientPresets) : []
          delegate: Column {
            id: paletteTile
            required property var modelData
            readonly property bool current: root ? root.gradientPreset === modelData.id : false
            activeFocusOnTab: true
            Keys.onReturnPressed: root.setOption("gradientPreset", modelData.id)
            Keys.onSpacePressed: root.setOption("gradientPreset", modelData.id)
            spacing: Style.spacing.xs

            Rectangle {
              width: Style.space(64)
              height: Style.space(30)
              radius: Math.min(Style.space(6), Style.cornerRadius > 0 ? Style.space(6) : 0)
              border.width: paletteTile.current || paletteTile.activeFocus ? 2 : 1
              border.color: paletteTile.current || paletteTile.activeFocus ? Color.accent : Util.alpha(Color.menu.text, 0.3)
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: paletteTile.modelData.colors[0] }
                GradientStop { position: 0.5; color: paletteTile.modelData.colors[1] }
                GradientStop { position: 1.0; color: paletteTile.modelData.colors[2] }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setOption("gradientPreset", paletteTile.modelData.id)
              }
            }

            Text {
              width: Style.space(64)
              horizontalAlignment: Text.AlignHCenter
              text: paletteTile.modelData.name
              textFormat: Text.PlainText
              color: paletteTile.current ? Color.accent : Util.alpha(Color.menu.text, 0.7)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      SliderRow {
        key: "gradientStrength"
        label: "Strength"
        hint: "How strongly the colours show over the theme background."
        minimum: 0
        maximum: 1
        step: 0.05
        displayScale: 100
        suffix: "%"
        value: root ? root.gradientStrength : 0.6
        onCommitted: function(v) { root.setOption("gradientStrength", Math.round(v * 100) / 100) }
      }
    }

    SwitchRow {
      key: "opacityTheme"
      label: "Opacity from theme"
      hint: "Follow the bar opacity of the current Omarchy theme."
      checked: root ? root.dockOpacity < 0 : true
      onToggled: root.setDockOpacity(root.dockOpacity < 0 ? 1.0 : -1.0)
    }
    SliderRow {
      key: "opacity"
      label: "Opacity"
      available: root ? root.dockOpacity >= 0 : false
      minimum: 0
      maximum: 1
      step: 0.05
      displayScale: 100
      suffix: "%"
      value: root ? Math.max(0, root.dockOpacity) : 1
      onCommitted: function(v) { root.setDockOpacity(Math.round(v * 100) / 100) }
    }


  }

  SettingsSection {
    title: Tr.t("settings.surfaceTuning", "Advanced surface, border & dividers")
  SectionLabel { title: "Border" }

  SwitchRow {
    key: "border"
    label: "Border"
    hint: "Thin rim around the dock."
    checked: root ? root.showBorder : true
    onToggled: root.setShowBorder(!root.showBorder)
  }
  SliderRow {
    key: "borderWidth"
    label: "Border width"
    available: root ? root.showBorder : true
    minimum: 1
    maximum: 6
    step: 0.5
    suffix: " px"
    displayDecimals: 1
    value: root ? root.borderWidth : 1.5
    onCommitted: function(v) { root.setOption("borderWidth", Math.round(v * 2) / 2) }
  }
  SwitchRow {
    key: "borderOpacityTheme"
    label: "Border opacity from theme"
    hint: "Derive the rim opacity from the dock's opacity, as themes expect. Turn off to set it by hand."
    checked: root ? root.borderOpacity < 0 : true
    available: root ? root.showBorder : true
    onToggled: root.setBorderOpacity(root.borderOpacity < 0 ? 1.0 : -1.0)
  }
  SliderRow {
    key: "borderOpacity"
    label: "Border opacity"
    available: root ? (root.showBorder && root.borderOpacity >= 0) : false
    minimum: 0
    maximum: 1
    step: 0.05
    displayScale: 100
    suffix: "%"
    value: root ? Math.max(0, root.borderOpacity) : 1
    onCommitted: function(v) { root.setBorderOpacity(Math.round(v * 100) / 100) }
  }
  ChoiceRow {
    key: "dividerLength"
    label: "Divider length style"
    hint: "Classic preserves the original icon-height lines. Long uses an adjustable share of the dock height."
    available: root ? (!root.placement.split && root.dividerStyle !== "none") : true
    options: [{ value: "classic", label: "Classic" }, { value: "long", label: "Long" }]
    value: root ? root.dividerGeometry : "classic"
    onPicked: function(v) { root.setOption("dividerGeometry", v) }
  }
  ChoiceRow {
    key: "dividerStyle"
    label: "Divider style"
    hint: "Theme draws the lines like the border, in its colour, opacity and width. Custom sets the width and opacity by hand. Hidden drops the lines and the room around them, for docks whose plates already show the sections."
    available: root ? !root.placement.split : true
    options: (root && !root.showBorder)
      ? [{ value: "simple", label: "Simple" }, { value: "custom", label: "Custom" }, { value: "none", label: "Hidden" }]
      : [{ value: "simple", label: "Simple" }, { value: "theme", label: "Theme" }, { value: "custom", label: "Custom" }, { value: "none", label: "Hidden" }]
    value: root ? root.dividerStyle : "simple"
    onPicked: function(v) { root.setDividerStyle(v) }
  }
  SliderRow {
    key: "dividerWidth"
    label: "Divider width"
    available: root ? (!root.placement.split && root.dividerStyle === "custom") : false
    minimum: 1
    maximum: 6
    step: 0.5
    suffix: " px"
    displayDecimals: 1
    value: root ? root.dividerWidth : 1.5
    onCommitted: function(v) { root.setOption("dividerWidth", Math.round(v * 2) / 2) }
  }
  SliderRow {
    key: "dividerOpacity"
    label: "Divider opacity"
    available: root ? (!root.placement.split && root.dividerStyle === "custom") : false
    minimum: 0
    maximum: 1
    step: 0.05
    displayScale: 100
    suffix: "%"
    value: root ? root.dividerOpacity : 0.4
    onCommitted: function(v) { root.setOption("dividerOpacity", Math.round(v * 100) / 100) }
  }
  SliderRow {
    key: "dividerHeight"
    label: "Divider height"
    hint: "Length of the lines between sections, as a share of the dock's height."
    available: root ? (!root.placement.split && root.dividerGeometry === "long" && root.dividerStyle !== "none") : false
    minimum: 20
    maximum: 100
    step: 5
    suffix: "%"
    value: root ? root.dividerHeight : 70
    onCommitted: function(v) { root.setOption("dividerHeight", Math.round(v)) }
  }

  SectionLabel { title: "Shape" }

  ChoiceRow {
    key: "corners"
    label: "Corners"
    available: root ? !root.placement.panel : true
    options: [
      { value: "theme", label: "Theme" },
      { value: "rounded", label: "Rounded" },
      { value: "round", label: "Pill" },
      { value: "square", label: "Square" }
    ]
    value: {
      if (!root) return "theme"
      var s = root.dockShape
      if (s === "auto") return "theme"
      if (s === "pill") return "round"
      return s
    }
    onPicked: function(v) { root.setDockShape(v) }
  }
  SliderRow {
    key: "cornerRadius"
    label: "Corner radius"
    available: root ? (!root.placement.panel && root.dockShape === "rounded") : false
    minimum: 2
    maximum: root ? root.maxRoundedRadius : 24
    step: 1
    suffix: " px"
    value: root ? root.roundedRadius : 14
    onCommitted: function(v) { root.setOption("cornerRadius", Math.round(v)) }
  }
  SwitchRow {
    key: "splitSections"
    label: "Split sections"
    available: root ? !root.placement.panel : true
    hint: "Each part between the dividers becomes its own panel, with a gap in place of the divider."
    checked: root ? root.splitSections : false
    onToggled: root.setOption("splitSections", !root.splitSections)
  }
  SliderRow {
    key: "panelSpacing"
    label: "Panel spacing"
    hint: "Gap between the panels when sections are split."
    available: root ? root.placement.split : false
    minimum: 0
    maximum: 48
    step: 1
    suffix: " px"
    value: root ? root.sectionSpacing : 18
    onCommitted: function(v) { root.setOption("sectionSpacing", Math.round(v)) }
  }
  ChoiceRow {
    key: "indicators"
    label: "Indicators"
    hint: "The dots and bars under icons. Theme follows the corners above."
    options: [
      { value: "theme", label: "Theme" },
      { value: "rounded", label: "Rounded" },
      { value: "square", label: "Square" }
    ]
    value: root ? root.indicatorShape : "theme"
    onPicked: function(v) { root.setOption("indicatorShape", v) }
  }

  }

}
