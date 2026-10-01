import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Full-screen overlay holding the dock settings: a sidebar of categories and
// a scrollable page of controls. Every control writes straight through the
// dock's setters, so the dock underneath previews each change live.
PanelWindow {
  id: panel

  property var rootRef: null
  readonly property var root: rootRef

  property string page: root ? root.settingsPanelPage : "appearance"

  // Id of the app group whose name is being edited; Esc then cancels the
  // edit instead of closing the panel.
  property string editingGroupId: ""

  // Update channel as reported by `omadock-switch status`; probed on open.
  property string channel: ""

  // Whether Hyprland blur is on at all (decoration:blur:enabled); probed on
  // open so the Blur switch can say when it cannot show anything.
  property bool systemBlurEnabled: true
  // Hyprland's blur size right now (decoration:blur:size), probed on open.
  property int currentBlurSize: 0

  readonly property var pages: [
    { id: "appearance", label: "Appearance", glyph: "󰏘" },
    { id: "placement", label: "Placement", glyph: "󰍹" },
    { id: "behavior", label: "Behavior", glyph: "󰒓" },
    { id: "effects", label: "Effects", glyph: "󰨙" },
    { id: "size", label: "Size & Spacing", glyph: "󰩨" },
    { id: "folders", label: "Folders", glyph: "󰉋" },
    { id: "groups", label: "App Groups", glyph: "󰀻" },
    { id: "supporters", label: "Supporters", glyph: "󰆔" },
    { id: "about", label: "About", glyph: "󰋼" }
  ]


  function close() {
    if (root) root.closeSettingsPanel()
  }

  screen: root ? root.dockScreen : null
  color: "transparent"
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omadock-settings"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  // ------------------------------------------------------------ building blocks

  component SectionLabel: Text {
    width: parent ? parent.width : implicitWidth
    topPadding: Style.spacing.xxl
    bottomPadding: Style.spacing.sm
    text: ""
    textFormat: Text.PlainText
    color: Util.alpha(Color.menu.text, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1
  }

  // Label + optional hint on the left, the control on the right.
  component SettingRow: Item {
    id: settingRow
    property string label: ""
    property string hint: ""
    default property alias control: slot.data

    width: parent ? parent.width : Style.space(420)
    implicitHeight: Math.max(Style.space(44), texts.implicitHeight + Style.spacing.lg * 2, slot.childrenRect.height + Style.spacing.md * 2)

    Column {
      id: texts
      anchors.left: parent.left
      anchors.right: slot.left
      anchors.rightMargin: Style.spacing.xxl
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xxs

      // Folder names, group names and paths reach these two unwrapped: they
      // are always plain text, never markup.
      Text {
        width: parent.width
        text: settingRow.label
        textFormat: Text.PlainText
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: settingRow.hint !== ""
        text: settingRow.hint
        textFormat: Text.PlainText
        color: Util.alpha(Color.menu.text, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    Item {
      id: slot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }

    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: 1
      color: Util.alpha(Color.menu.text, 0.10)
    }
  }

  component SwitchRow: SettingRow {
    id: switchRow
    property bool checked: false
    signal toggled()

    ToggleSwitch {
      checked: switchRow.checked
      foreground: Color.menu.text
      onToggled: switchRow.toggled()
    }
  }

  component ChoiceRow: SettingRow {
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

  component SliderRow: SettingRow {
    id: sliderRow
    property real value: 0

    // A hidden row can lose its mouse grab mid-drag without ever getting a
    // release; drop the drag state so the knob cannot stick to the cursor.
    onVisibleChanged: if (!visible && slider.dragging) slider.dragging = false
    property real minimum: 0
    property real maximum: 1
    property real step: 1
    property string suffix: ""
    property real displayScale: 1
    // Decimals shown next to the slider (0 rounds to whole numbers).
    property int displayDecimals: 0
    signal committed(real value)

    // PanelSlider reads its palette from a bar-shaped object.
    QtObject {
      id: sliderPalette
      property color foreground: Color.menu.text
      property color background: Color.menu.background
    }

    Row {
      spacing: Style.spacing.lg

      PanelSlider {
        id: slider
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(180)
        bar: sliderPalette
        minimum: sliderRow.minimum
        maximum: sliderRow.maximum
        step: sliderRow.step
        integer: sliderRow.step >= 1
        value: sliderRow.value
        onReleased: function(v) {
          sliderRow.committed(v)
          // Belt and braces: if the press was ever canceled (grab stolen or the
          // row hidden mid-drag), PanelSlider never resets its drag state and the
          // knob follows the cursor. Re-assert it on every release/commit.
          slider.dragging = false
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(52)
        horizontalAlignment: Text.AlignRight
        text: (slider.liveValue * sliderRow.displayScale).toFixed(sliderRow.displayDecimals) + sliderRow.suffix
        textFormat: Text.PlainText
        color: Util.alpha(Color.menu.text, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }

  component Swatch: Rectangle {
    id: swatch
    property bool selected: false
    signal picked()

    width: Style.space(26)
    height: Style.space(26)
    radius: Math.min(Style.space(6), Style.cornerRadius > 0 ? Style.space(6) : 0)
    border.width: selected ? 2 : 1
    border.color: selected ? Color.accent : Util.alpha(Color.menu.text, 0.3)

    Rectangle {
      visible: swatch.selected
      anchors.centerIn: parent
      width: Style.space(8)
      height: width
      radius: width / 2
      color: Color.accent
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: swatch.picked()
    }
  }

  // ------------------------------------------------------------ scrim

  Rectangle {
    anchors.fill: parent
    color: Util.alpha("#000000", 0.35)

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: panel.close()
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: panel.close()
  }

  // Focus has to be taken again once the surface is actually mapped.
  onVisibleChanged: if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  Component.onCompleted: {
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    channelProbe.running = true
    blurProbe.running = true
    blurSizeProbe.running = true
  }

  // One-shot channel probe (event-driven, zero idle CPU): reads which profile
  // `omadock-switch` has live so the About page can show the real state.
  Process {
    id: channelProbe
    command: ["omadock-switch", "status"]
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf("Active Mode:") < 0) return
        if (line.indexOf("EXPERIMENT") >= 0) panel.channel = "experiment"
        else if (line.indexOf("STABLE") >= 0) panel.channel = "stable"
      }
    }
  }

  Process {
    id: blurProbe
    command: ["hyprctl", "getoption", "decoration:blur:enabled", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var opt = JSON.parse(this.text)
          // Newer Hyprland reports booleans as "bool", older ones as "int".
          panel.systemBlurEnabled = typeof opt.bool === "boolean" ? opt.bool : opt.int !== 0
        } catch (e) {
          console.warn("[omadock] Failed to parse decoration:blur:enabled option:", e)
        }
      }
    }
  }

  Process {
    id: blurSizeProbe
    command: ["hyprctl", "getoption", "decoration:blur:size", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var opt = JSON.parse(this.text)
          if (typeof opt.int === "number") panel.currentBlurSize = opt.int
        } catch (e) {
          console.warn("[omadock] Failed to parse decoration:blur:size option:", e)
        }
      }
    }
  }

  Shortcut {
    sequence: "Escape"
    context: Qt.WindowShortcut
    enabled: panel.editingGroupId === ""
    onActivated: panel.close()
  }

  // ------------------------------------------------------------ card

  BorderSurface {
    id: card

    width: Math.min(parent.width - Style.space(48), Style.space(820))
    height: Math.min(parent.height - Style.space(48), Style.space(600))
    anchors.centerIn: parent
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
    radius: Style.cornerRadius

    // Swallow clicks so they never reach the scrim. A click on empty space
    // also cancels a group rename, since it would not move focus by itself.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onPressed: {
        if (panel.editingGroupId === "") return
        panel.editingGroupId = ""
        keyCatcher.forceActiveFocus()
      }
    }

    // ---------------------------------------------------------- sidebar
    Rectangle {
      id: sidebar
      x: card.contentLeftInset
      y: card.contentTopInset
      width: Style.space(200)
      height: card.height - card.contentTopInset - card.contentBottomInset
      color: Util.alpha(Color.menu.text, 0.035)
      radius: Math.max(0, Style.cornerRadius - 1)

      Column {
        anchors.fill: parent
        anchors.margins: Style.spacing.xxl
        spacing: Style.spacing.xs

        Text {
          text: "Omadock"
          textFormat: Text.PlainText
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }
        Text {
          text: "Dock settings"
          textFormat: Text.PlainText
          color: Util.alpha(Color.menu.text, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          bottomPadding: Style.spacing.xxl
        }

        Repeater {
          model: panel.pages
          delegate: Rectangle {
            id: navItem
            required property var modelData
            readonly property bool current: panel.page === modelData.id

            width: parent.width
            height: Style.space(34)
            radius: Style.cornerRadius > 0 ? Style.space(6) : 0
            color: current ? Util.alpha(Color.accent, 0.18)
              : (navMouse.containsMouse ? Util.alpha(Color.menu.text, 0.07) : "transparent")

            // Glyph centred on its painted (tight) bounds, not its line box:
            // icon fonts sit low in the line, which left them under the label.
            Item {
              id: navIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.xl
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              height: Style.space(18)

              TextMetrics {
                id: navGlyphMetrics
                font: navGlyph.font
                text: navGlyph.text
              }

              Text {
                id: navGlyph
                text: navItem.modelData.glyph
                textFormat: Text.PlainText
                color: navItem.current ? Color.accent : Util.alpha(Color.menu.text, 0.55)
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
                x: Math.round(navIcon.width / 2 - (navGlyphMetrics.tightBoundingRect.x + navGlyphMetrics.tightBoundingRect.width / 2))
                y: Math.round(navIcon.height / 2 - (navGlyph.baselineOffset + navGlyphMetrics.tightBoundingRect.y + navGlyphMetrics.tightBoundingRect.height / 2))
              }
            }

            Text {
              anchors.left: navIcon.right
              anchors.leftMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: navItem.modelData.label
              textFormat: Text.PlainText
              color: navItem.current ? Color.accent : Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
            }

            MouseArea {
              id: navMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root) root.settingsPanelPage = navItem.modelData.id
                pageFlick.contentY = 0
              }
            }
          }
        }
      }
    }

    // ---------------------------------------------------------- header
    Item {
      id: header
      anchors.left: sidebar.right
      anchors.leftMargin: Style.spacing.huge
      anchors.right: parent.right
      anchors.rightMargin: card.contentRightInset + Style.spacing.xxl
      y: card.contentTopInset + Style.spacing.xxl
      height: Style.space(32)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: {
          for (var i = 0; i < panel.pages.length; i++)
            if (panel.pages[i].id === panel.page) return panel.pages[i].label
          return ""
        }
        textFormat: Text.PlainText
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.display
      }

      Button {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅖"
        foreground: Color.menu.text
        tooltipText: "Close (Esc)"
        onClicked: panel.close()
      }
    }

    // ---------------------------------------------------------- page
    // The wheel is handled on this plain container rather than inside the
    // Flickable: with interactive off (below) the Flickable ignores wheel
    // events, and a handler parented into it never saw them either.
    Item {
      id: pageViewport
      anchors.left: header.left
      anchors.right: header.right
      anchors.top: header.bottom
      anchors.topMargin: Style.spacing.md
      anchors.bottom: parent.bottom
      anchors.bottomMargin: card.contentBottomInset + Style.spacing.xxl

      WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
          // Touchpads report pixels; wheels report notches of 120.
          var dy = event.pixelDelta.y !== 0
            ? -event.pixelDelta.y
            : -event.angleDelta.y / 120 * Style.space(48)
          if (dy === 0) return
          var maxY = Math.max(0, pageFlick.contentHeight - pageFlick.height)
          pageFlick.contentY = Math.max(0, Math.min(maxY, pageFlick.contentY + dy))
        }
      }

      Flickable {
        id: pageFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Scrolling is wheel-only (WheelHandler on pageViewport). Drag-flicking
        // is off so the Flickable never steals the grab from slider/toggle
        // drags mid-gesture.
        interactive: false

        Column {
          id: pageColumn
          width: pageFlick.width

          // ================================================= Appearance
          Column {
            width: parent.width
            visible: panel.page === "appearance"

            SectionLabel { text: "Background" }

            SwitchRow {
              label: "Background"
              hint: "Fill behind the icons. Off leaves the icons floating."
              checked: root ? root.showBackground : true
              onToggled: root.setOption("showBackground", !root.showBackground)
            }

            Column {
              width: parent.width
              visible: root ? root.showBackground : true

              ChoiceRow {
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
                label: "Opacity from theme"
                hint: "Follow the bar opacity of the current Omarchy theme."
                checked: root ? root.dockOpacity < 0 : true
                onToggled: root.setDockOpacity(root.dockOpacity < 0 ? 1.0 : -1.0)
              }
              SliderRow {
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

              SwitchRow {
                label: "Blur from system"
                hint: "Leave blur behind the dock to your Hyprland layer rules."
                checked: root ? root.blurMode === "system" : true
                onToggled: root.setBlurMode(root.blurMode === "system" ? "on" : "system")
              }
              SwitchRow {
                label: "Blur"
                hint: panel.systemBlurEnabled
                  ? "Frosted glass behind the dock."
                  : "Hyprland blur is off (decoration:blur:enabled), so this has no visible effect."
                visible: root ? root.blurMode !== "system" : false
                checked: root ? root.blurMode === "on" : false
                onToggled: root.setBlurMode(root.blurMode === "on" ? "off" : "on")
              }
              SliderRow {
                label: "Blur strength"
                hint: "Hyprland has one blur size for everything, so this also changes it for windows and other panels. Back to your own value when blur leaves this mode."
                visible: root ? root.blurMode === "on" : false
                minimum: 1
                maximum: 20
                step: 1
                value: root ? (root.blurSize > 0 ? root.blurSize : (panel.currentBlurSize > 0 ? panel.currentBlurSize : 6)) : 6
                onCommitted: function(v) { root.setBlurSize(v, panel.currentBlurSize) }
              }
              SliderRow {
                label: "Grain"
                hint: "Film grain over the background. Works on solid, translucent and blurred backgrounds alike."
                minimum: 0
                maximum: 1
                step: 0.05
                displayScale: 100
                suffix: "%"
                value: root ? root.grain : 0
                onCommitted: function(v) { root.setOption("grain", Math.round(v * 100) / 100) }
              }

            }

            SectionLabel { text: "Shadow" }

            SwitchRow {
              label: "Shadow"
              hint: "Under the dock; with the background off, under each icon."
              checked: root ? root.showShadow : true
              onToggled: root.setOption("showShadow", !root.showShadow)
            }
            SliderRow {
              label: "Strength"
              visible: root ? root.showShadow : true
              minimum: 0
              maximum: 1
              step: 0.05
              displayScale: 100
              suffix: "%"
              value: root ? root.shadowStrength : 0.4
              onCommitted: function(v) { root.setOption("shadowStrength", Math.round(v * 100) / 100) }
            }

            SectionLabel { text: "Border" }

            SwitchRow {
              label: "Border"
              hint: "Thin rim around the dock."
              checked: root ? root.showBorder : true
              onToggled: root.setOption("showBorder", !root.showBorder)
            }
            SliderRow {
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
              label: "Border opacity from theme"
              hint: "Derive the rim opacity from the dock's opacity, as themes expect. Turn off to set it by hand."
              checked: root ? root.borderOpacity < 0 : true
              visible: root ? root.showBorder : true
              onToggled: root.setBorderOpacity(root.borderOpacity < 0 ? 1.0 : -1.0)
            }
            SliderRow {
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

            SectionLabel { text: "Shape" }

            ChoiceRow {
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
              label: "Split sections"
              hint: "Each part between the dividers becomes its own panel, with a gap in place of the divider."
              checked: root ? root.splitSections : false
              onToggled: root.setOption("splitSections", !root.splitSections)
            }
            ChoiceRow {
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
              label: "Omarchy button"
              hint: "The launcher at the start of the dock. Without it, right-click the dock background to reach these settings."
              checked: root ? root.showAppsButton : true
              onToggled: root.setOption("showAppsButton", !root.showAppsButton)
            }
            SwitchRow {
              label: "Removable drives"
              hint: "Show mounted USB drives at the end of the dock."
              checked: root ? root.showRemovableDrives : true
              onToggled: {
                root.setOption("showRemovableDrives", !root.showRemovableDrives)
                root.scanRemovableDrives()
              }
            }
          }

          // ================================================= Placement
          Column {
            width: parent.width
            visible: panel.page === "placement"

            SectionLabel { text: "Position" }

            ChoiceRow {
              label: "Alignment"
              options: [
                { value: "left", label: "Left" },
                { value: "center", label: "Center" },
                { value: "right", label: "Right" }
              ]
              value: root ? (root.alignment || "center") : "center"
              onPicked: function(v) { root.setDockAlignment(v) }
            }

            SectionLabel { text: "Monitors" }

            SwitchRow {
              label: "Show on all monitors"
              hint: "One dock per connected monitor."
              checked: root ? root.multiMonitor : false
              onToggled: root.setOption("multiMonitor", !root.multiMonitor)
            }
            SwitchRow {
              label: "Only this monitor's apps"
              hint: "Each dock lists the windows on its own monitor; pinned apps show everywhere."
              visible: root ? root.multiMonitor : false
              checked: root ? root.perMonitorApps : true
              onToggled: root.setOption("perMonitorApps", !root.perMonitorApps)
            }
            SettingRow {
              label: root && root.multiMonitor ? "Primary monitor" : "Monitor"
              hint: root && root.multiMonitor
                ? "Plays the alert sounds."
                : "Automatic picks the first connected output."

              Dropdown {
                width: Style.space(200)
                showLabel: false
                options: {
                  var list = [{ value: "", label: "Automatic" }]
                  var screens = root ? root.realScreens : []
                  for (var i = 0; i < screens.length; i++)
                    list.push({ value: screens[i].name, label: screens[i].name + (screens[i].model ? " — " + screens[i].model : "") })
                  if (root && root.screenName && !root.screenForName(root.screenName))
                    list.push({ value: root.screenName, label: root.screenName + " (disconnected)" })
                  return list
                }
                value: root ? root.screenName : ""
                onChanged: function(v) { root.setDockScreen(v) }
              }
            }
          }

          // ================================================= Behavior
          Column {
            width: parent.width
            visible: panel.page === "behavior"

            SectionLabel { text: "Visibility" }

            ChoiceRow {
              label: "Autohide"
              hint: "Intelligent hides only when a window overlaps the dock."
              options: [
                { value: "always", label: "Always show" },
                { value: "intelligent", label: "Intelligent" },
                { value: "autohide", label: "Autohide" }
              ]
              value: root ? (!root.autohide ? "always" : (root.intelligentAutohide ? "intelligent" : "autohide")) : "always"
              onPicked: function(v) { root.setAutohideMode(v) }
            }
            SliderRow {
              label: "Reveal delay"
              hint: "How long the pointer rests on the edge before the dock slides in."
              enabled: root ? root.autohide : false
              opacity: enabled ? 1 : 0.45
              minimum: 0
              maximum: 1000
              step: 10
              suffix: " ms"
              value: root ? root.revealDelay : 160
              onCommitted: function(v) { root.setOption("revealDelay", Math.round(v)) }
            }

            SectionLabel { text: "Clicking an app" }

            ChoiceRow {
              label: "Minimize on click"
              hint: "Clicking the focused app's icon parks its windows."
              options: [
                { value: "off", label: "Off" },
                { value: "active", label: "Active window" },
                { value: "all", label: "All windows" }
              ]
              value: root ? root.minimizeMode : "active"
              onPicked: function(v) { root.setOption("minimizeMode", v) }
            }

            SectionLabel { text: "Attention" }

            SwitchRow {
              label: "Urgent highlights"
              hint: "Mark apps whose windows ask for attention."
              checked: root ? root.showUrgentHint : true
              onToggled: root.setOption("showUrgentHint", !root.showUrgentHint)
            }
            SwitchRow {
              label: "Urgent on notification"
              hint: "A notification from an app marks its icon."
              checked: root ? root.urgentOnNotification : true
              onToggled: root.setOption("urgentOnNotification", !root.urgentOnNotification)
            }
            SettingRow {
              label: "Urgent sound"

              Dropdown {
                width: Style.space(200)
                showLabel: false
                options: [
                  { value: "bell", label: "Bell" },
                  { value: "message-new-instant", label: "Message chime" },
                  { value: "complete", label: "Complete ding" },
                  { value: "dialog-information", label: "Information pop" },
                  { value: "dialog-warning", label: "Warning alert" },
                  { value: "phone-incoming-call", label: "Phone ring" },
                  { value: "alarm-clock-elapsed", label: "Alarm beeps" },
                  { value: "none", label: "Mute" }
                ]
                value: root ? (root.urgentSound ? root.urgentSoundName : "none") : "bell"
                onChanged: function(v) { root.setUrgentSoundName(v) }
              }
            }

            SectionLabel { text: "Previews & Tooltips" }

            SwitchRow {
              label: "Tooltips"
              checked: root ? root.showTooltips : true
              onToggled: root.setOption("showTooltips", !root.showTooltips)
            }
            SliderRow {
              label: "Tooltip delay"
              enabled: root ? root.showTooltips : true
              opacity: enabled ? 1 : 0.45
              minimum: 0
              maximum: 2000
              step: 50
              suffix: " ms"
              value: root ? root.tooltipDelay : 450
              onCommitted: function(v) { root.setOption("tooltipDelay", Math.round(v)) }
            }
            SwitchRow {
              label: "Window previews"
              hint: "Live thumbnails of an app's windows in its tooltip."
              checked: root ? root.advancedTooltips : true
              onToggled: root.setOption("advancedTooltips", !root.advancedTooltips)
            }
            SwitchRow {
              label: "Minimized window tiles"
              hint: "Show parked windows as preview tiles in the dock."
              checked: root ? root.showMinimizedTiles : true
              onToggled: root.setOption("showMinimizedTiles", !root.showMinimizedTiles)
            }
          }

          // ================================================= Effects
          Column {
            width: parent.width
            visible: panel.page === "effects"

            SectionLabel { text: "Icons" }

            ChoiceRow {
              label: "Icon style"
              hint: "Monochrome and dot matrix take one colour from the theme."
              options: [
                { value: "original", label: "Original" },
                { value: "mono", label: "Monochrome" },
                { value: "pixel", label: "Pixel" },
                { value: "dots", label: "Dot matrix" }
              ]
              value: root ? root.iconStyle : "original"
              onPicked: function(v) { root.setOption("iconStyle", v) }
            }
            ChoiceRow {
              label: "Icon colour"
              visible: root ? (root.iconStyle === "mono" || root.iconStyle === "dots") : false
              options: [
                { value: "text", label: "Text" },
                { value: "accent", label: "Accent" },
                { value: "bw", label: "B/W" }
              ]
              value: root ? root.iconTint : "text"
              onPicked: function(v) { root.setOption("iconTint", v) }
            }
            SliderRow {
              label: root && root.iconStyle === "dots" ? "Dots across" : "Pixels across"
              hint: "Fewer is chunkier."
              visible: root ? (root.iconStyle === "pixel" || root.iconStyle === "dots") : false
              minimum: 8
              maximum: 32
              step: 1
              value: root ? root.iconGrid : 16
              onCommitted: function(v) { root.setOption("iconGrid", Math.round(v)) }
            }
            SliderRow {
              label: "Contrast"
              hint: "Separates the symbol from its backdrop; high values flatten icons to a simple, poster-like shape."
              visible: root ? (root.iconStyle === "mono" || root.iconStyle === "dots") : false
              minimum: 0
              maximum: 1
              step: 0.05
              displayScale: 100
              suffix: "%"
              value: root ? root.iconContrast : 0
              onCommitted: function(v) { root.setOption("iconContrast", Math.round(v * 100) / 100) }
            }
            SliderRow {
              label: "Strength"
              hint: "How much of the effect covers the original icon."
              visible: root ? (root.iconStyle === "mono" || root.iconStyle === "dots") : false
              minimum: 0
              maximum: 1
              step: 0.05
              displayScale: 100
              suffix: "%"
              value: root ? root.iconStrength : 1
              onCommitted: function(v) { root.setOption("iconStrength", Math.round(v * 100) / 100) }
            }
            SwitchRow {
              label: "Show original on hover"
              hint: "The icon under the pointer drops the style and shows as shipped. Icons in an opened group follow this too."
              visible: root ? root.iconStyle !== "original" : false
              checked: root ? root.iconHoverOriginal : false
              onToggled: root.setOption("iconHoverOriginal", !root.iconHoverOriginal)
            }

            SectionLabel { text: "Motion" }

            ChoiceRow {
              label: "Hover effect"
              options: [
                { value: "zoom", label: "Zoom" },
                { value: "wave", label: "Wave" },
                { value: "off", label: "None" }
              ]
              value: root ? root.hoverEffect : "zoom"
              onPicked: function(v) { root.setHoverEffect(v) }
            }
            SwitchRow {
              label: "Launch bounce"
              hint: "Bounce the icon while an app is starting."
              checked: root ? root.launchBounce : true
              onToggled: root.setOption("launchBounce", !root.launchBounce)
            }
          }

          // ================================================= Size & spacing
          Column {
            width: parent.width
            visible: panel.page === "size"

            SectionLabel { text: "Icons" }

            SliderRow {
              label: "Icon size"
              minimum: 24
              maximum: 64
              step: 2
              suffix: " px"
              value: root ? root.iconSize : 36
              onCommitted: function(v) { root.setIconSize(Math.round(v)) }
            }
            SliderRow {
              label: "Spacing"
              hint: "Gap between icons."
              minimum: 0
              maximum: 16
              step: 1
              suffix: " px"
              value: root ? root.itemSpacing : 4
              onCommitted: function(v) { root.setItemSpacing(Math.round(v)) }
            }
            SliderRow {
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
          }

          // ================================================= Folders
          Column {
            width: parent.width
            visible: panel.page === "folders"

            SectionLabel { text: "Pinned folders" }

            Repeater {
              model: [
                { path: "~/Downloads", name: "Downloads", icon: "folder-download" },
                { path: "~/Documents", name: "Documents", icon: "folder-documents" },
                { path: "~/Pictures", name: "Pictures", icon: "folder-pictures" },
                { path: "~/Projects", name: "Projects", icon: "folder-development" },
                { path: "~/Music", name: "Music", icon: "folder-music" },
                { path: "~/Videos", name: "Videos", icon: "folder-videos" },
                { path: "~", name: "Home", icon: "user-home" }
              ]
              delegate: SwitchRow {
                required property var modelData
                label: modelData.name
                hint: modelData.path
                checked: root ? (root.pinnedFolders, root.isFolderPinned(modelData.path)) : false
                onToggled: root.toggleFolderPin(modelData.path, modelData.name, modelData.icon)
              }
            }

            Repeater {
              model: {
                if (!root) return []
                var presets = ["~/Downloads", "~/Documents", "~/Pictures", "~/Projects", "~/Music", "~/Videos", "~"]
                var out = []
                for (var i = 0; i < root.pinnedFolders.length; i++)
                  if (presets.indexOf(root.pinnedFolders[i].path) < 0) out.push(root.pinnedFolders[i])
                return out
              }
              delegate: SettingRow {
                required property var modelData
                label: modelData.name || "Folder"
                hint: modelData.path

                Button {
                  text: "Remove"
                  foreground: Color.menu.text
                  bordered: true
                  onClicked: root.toggleFolderPin(modelData.path, modelData.name, modelData.icon)
                }
              }
            }

            SettingRow {
              label: "Custom folder"
              hint: "Pick any directory to pin as a stack."

              Button {
                text: "Add folder…"
                foreground: Color.menu.text
                bordered: true
                onClicked: {
                  panel.close()
                  root.pickCustomFolder()
                }
              }
            }

            SectionLabel { text: "Folder color" }

            Flow {
              width: parent.width
              spacing: Style.spacing.md
              bottomPadding: Style.spacing.lg

              Button {
                text: "Theme"
                foreground: Color.menu.text
                bordered: true
                selected: root ? (root.folderColor === "theme" || !root.folderColor) : true
                onClicked: root.setFolderColor("theme")
              }

              // Monochrome outlines in black or white, whichever reads
              // better on what is behind them: the dock, or a stack popup.
              Button {
                text: "Auto B/W"
                foreground: Color.menu.text
                bordered: true
                selected: root ? root.folderColor === "bw" : false
                onClicked: root.setFolderColor("bw")
              }

              Repeater {
                model: [
                  { id: "white", color: "#ffffff" },
                  { id: "black", color: "#111111" },
                  { id: "Yaru-sage", color: "#61895a" },
                  { id: "Yaru-olive", color: "#878846" },
                  { id: "Yaru-blue", color: "#3d7ab8" },
                  { id: "Yaru-purple", color: "#775aa6" },
                  { id: "Yaru-magenta", color: "#b3497d" },
                  { id: "Yaru-red", color: "#c73838" },
                  { id: "Yaru-yellow", color: "#d9a13b" },
                  { id: "Yaru-wartybrown", color: "#8a583e" },
                  { id: "Yaru-prussiangreen", color: "#2d7f7b" },
                  { id: "Yaru-dark", color: "#3c3b37" }
                ]
                delegate: Swatch {
                  required property var modelData
                  color: modelData.color
                  selected: root ? root.folderColor === modelData.id : false
                  onPicked: root.setFolderColor(modelData.id)
                }
              }
            }
          }

          // ================================================= App groups
          Column {
            width: parent.width
            visible: panel.page === "groups"

            SectionLabel { text: "Look" }

            ChoiceRow {
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
              label: "Icon style"
              hint: "Theme applies the style from Effects to the icons of an opened group."
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
                  keyCatcher.forceActiveFocus()
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

          // ================================================= Supporters
          Column {
            width: parent.width
            visible: panel.page === "supporters"

            SectionLabel { text: "Made with love" }

            Text {
              width: parent.width
              topPadding: Style.spacing.lg
              bottomPadding: Style.spacing.lg
              text: "Omadock is built with love by thepathless — a medical student, between classes and clinics. It is free, and it always will be.\n\nIf it earns a place on your desktop, you can give some love back to its maker. No tiers, no perks — just support returned."
              textFormat: Text.PlainText
              color: Color.menu.text
              wrapMode: Text.WordWrap
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            SettingRow {
              label: "Supporter #1 — thepathless"
              hint: "The maker. Its first and forever supporter."

              Button {
                text: "Support ❤"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/sponsors/thepathless"))
              }
            }

            SettingRow {
              label: "Supporters wall"
              hint: "Everyone who has supported Omadock, honored in the repository."

              Button {
                text: "View wall"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/thepathless/omadock/blob/main/SPONSORS.md"))
              }
            }

            SectionLabel { text: "Code Contributors" }

            SettingRow {
              label: "@priard (Lukasz)"
              hint: "macOS folder stacks, icon shaders, gradients, grain, drop-to-open"

              Button {
                text: "GitHub ↗"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/priard"))
              }
            }

            SettingRow {
              label: "@G-Pappas (George P.)"
              hint: "Multi-monitor docks & per-output instance management"

              Button {
                text: "GitHub ↗"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/G-Pappas"))
              }
            }

            SettingRow {
              label: "@NothingManTR (Taha Can)"
              hint: "Removable media drives & safe eject, smart app matching, jump lists"

              Button {
                text: "GitHub ↗"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/NothingManTR"))
              }
            }

            SettingRow {
              label: "@assada"
              hint: "Window focus dispatch & Hyprland layout awareness"

              Button {
                text: "GitHub ↗"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/assada"))
              }
            }

            SettingRow {
              label: "@tdslot"
              hint: "Desktop entry launch suffix validation fix for pinned apps"

              Button {
                text: "GitHub ↗"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/tdslot"))
              }
            }

            SettingRow {
              label: "@Tech0001"
              hint: "Application matching restoration"

              Button {
                text: "GitHub ↗"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/Tech0001"))
              }
            }

            SectionLabel { text: "Bug Hunters & Diagnostics" }

            SettingRow {
              label: "@justinlharter"
              hint: "Suspend/resume screen null recovery diagnostics"

              Button {
                text: "GitHub ↗"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/justinlharter"))
              }
            }

            SettingRow {
              label: "@maugustoldo (Marcos Augusto)"
              hint: "GTK icon resolving, launcher matching, and theme accent"

              Button {
                text: "GitHub ↗"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/maugustoldo"))
              }
            }

            SettingRow {
              label: "@m-bowden (Michael Bowden)"
              hint: "Webapp Exec-URL .execString desktop entry investigation"

              Button {
                text: "GitHub ↗"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/m-bowden"))
              }
            }

            SettingRow {
              label: "@herman6888"
              hint: "Omarchy 4.x overlay plugin appLibrary diagnostic"

              Button {
                text: "GitHub ↗"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/herman6888"))
              }
            }
          }

          // ================================================= About
          Column {
            width: parent.width
            visible: panel.page === "about"

            SectionLabel { text: "Updates" }

            ChoiceRow {
              label: "Update channel"
              hint: "Stable receives verified releases; Experimental gets features early. Switching reloads the shell immediately."
              options: [
                { value: "stable", label: "Stable" },
                { value: "experiment", label: "Experimental" }
              ]
              value: panel.channel !== "" ? panel.channel : "stable"
              onPicked: function(v) {
                if (panel.channel === "" || v === panel.channel) return
                Quickshell.execDetached(["omadock-switch", v === "stable" ? "stable" : "experiment"])
              }
            }

            SectionLabel { text: "Project" }

            SettingRow {
              label: "Version"
              hint: "The Omadock release this dock is running."

              Text {
                text: (root && root.manifest && root.manifest.version) ? "v" + root.manifest.version : "unknown"
                textFormat: Text.PlainText
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
              }
            }

            SettingRow {
              label: "Omadock"
              hint: "A fluid, zero-CPU dock for Omarchy. Report bugs, follow development, or star the repository."

              Button {
                text: "GitHub"
                foreground: Color.menu.text
                bordered: true
                onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/thepathless/omadock"))
              }
            }
          }
        }
      }
    }
  }
}
