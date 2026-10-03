import QtQuick
import qs.Commons
import qs.Ui

// Settings page: background, border, divider, shape and dock-item rows.
// Instantiated by SettingsPanel, which injects root (the Dock, for
// values and setters) and panel (page/edit state).

Column {
  property var root: null
  property var panel: null
  width: parent.width


  SectionLabel { text: "Background" }

  SwitchRow {
    key: "showBackground"
    label: "Background"
    hint: "Fill behind the icons. Off leaves the icons floating."
    checked: root ? root.showBackground : true
    onToggled: root.setOption("showBackground", !root.showBackground)
  }

  Column {
    width: parent.width
    visible: root ? root.showBackground : true

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
      visible: root ? root.bgFill !== "gradient" : true

      SettingRow {
        key: "bgColor"
        label: "Color"
        hint: "Theme, none, or a fixed preset."

        Row {
          spacing: Style.spacing.sm

          Button {
            text: "Theme"
            foreground: Color.menu.text
            bordered: true
            selected: root ? (root.dockBgColor === "theme" || !root.dockBgColor) : true
            onClicked: root.setDockBgColor("theme")
          }
          Button {
            text: "None"
            foreground: Color.menu.text
            bordered: true
            selected: root ? root.dockBgColor === "none" : false
            onClicked: root.setDockBgColor("none")
          }
        }
      }

      Flow {
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
      visible: root ? root.bgFill === "gradient" : false

      SettingRow {
        key: "gradientPalette"
        label: "Palette"
        hint: "Theme builds one from the Omarchy theme's accent and palette."
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.md
        topPadding: Style.spacing.sm
        bottomPadding: Style.spacing.lg

        Repeater {
          model: root ? [{ id: "theme", name: "Theme", colors: root.themeGradientColors }].concat(root.gradientPresets) : []
          delegate: Column {
            id: paletteTile
            required property var modelData
            readonly property bool current: root ? root.gradientPreset === modelData.id : false
            spacing: Style.spacing.xs

            Rectangle {
              width: Style.space(64)
              height: Style.space(30)
              radius: Math.min(Style.space(6), Style.cornerRadius > 0 ? Style.space(6) : 0)
              border.width: paletteTile.current ? 2 : 1
              border.color: paletteTile.current ? Color.accent : Util.alpha(Color.menu.text, 0.3)
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
      visible: root ? root.dockOpacity >= 0 : false
      minimum: 0
      maximum: 1
      step: 0.05
      displayScale: 100
      suffix: "%"
      value: root ? Math.max(0, root.dockOpacity) : 1
      onCommitted: function(v) { root.setDockOpacity(Math.round(v * 100) / 100) }
    }


  }

  SectionLabel { text: "Border" }

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
    visible: root ? root.showBorder : true
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
    visible: root ? root.showBorder : true
    onToggled: root.setBorderOpacity(root.borderOpacity < 0 ? 1.0 : -1.0)
  }
  SliderRow {
    key: "borderOpacity"
    label: "Border opacity"
    visible: root ? (root.showBorder && root.borderOpacity >= 0) : false
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
    visible: root ? !root.splitSections : true
    options: [{ value: "classic", label: "Classic" }, { value: "long", label: "Long" }]
    value: root ? root.dividerGeometry : "classic"
    onPicked: function(v) { root.setOption("dividerGeometry", v) }
  }
  ChoiceRow {
    key: "dividerStyle"
    label: "Divider style"
    hint: "Theme draws the lines like the border, in its colour, opacity and width. Custom sets the width and opacity by hand."
    visible: root ? !root.splitSections : true
    options: (root && !root.showBorder)
      ? [{ value: "simple", label: "Simple" }, { value: "custom", label: "Custom" }]
      : [{ value: "simple", label: "Simple" }, { value: "theme", label: "Theme" }, { value: "custom", label: "Custom" }]
    value: root ? root.dividerStyle : "simple"
    onPicked: function(v) { root.setDividerStyle(v) }
  }
  SliderRow {
    key: "dividerWidth"
    label: "Divider width"
    visible: root ? (!root.splitSections && root.dividerStyle === "custom") : false
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
    visible: root ? (!root.splitSections && root.dividerStyle === "custom") : false
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
    visible: root ? (!root.splitSections && root.dividerGeometry === "long") : false
    minimum: 20
    maximum: 100
    step: 5
    suffix: "%"
    value: root ? root.dividerHeight : 70
    onCommitted: function(v) { root.setOption("dividerHeight", Math.round(v)) }
  }

  SectionLabel { text: "Shape" }

  ChoiceRow {
    key: "corners"
    label: "Corners"
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
    visible: root ? root.dockShape === "rounded" : false
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
    hint: "Each part between the dividers becomes its own panel, with a gap in place of the divider."
    checked: root ? root.splitSections : false
    onToggled: root.setOption("splitSections", !root.splitSections)
  }
  SliderRow {
    key: "panelSpacing"
    label: "Panel spacing"
    hint: "Gap between the panels when sections are split."
    visible: root ? root.splitSections : false
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

  SectionLabel { text: "Dock Items" }

  SwitchRow {
    key: "appsButton"
    label: "Omarchy button"
    hint: "The launcher at the start of the dock. Without it, right-click the dock background to reach these settings."
    checked: root ? root.showAppsButton : true
    onToggled: root.setOption("showAppsButton", !root.showAppsButton)
  }
  SwitchRow {
    key: "removableDrives"
    label: "Removable drives"
    hint: "Show mounted USB drives at the end of the dock."
    checked: root ? root.showRemovableDrives : true
    onToggled: {
      root.setOption("showRemovableDrives", !root.showRemovableDrives)
      root.scanRemovableDrives()
    }
  }
}
