import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel
import "settings"

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
  property string editingPresetId: ""
  property string confirmDeletePresetId: ""
  // The row of a just-saved preset opens its name for editing.
  signal presetEditRequested(string id)
  function startPresetEdit(id) { panel.presetEditRequested(id) }
  // Leaves a preset rename without saving it. Called before any action that
  // rebuilds the preset rows, which would drop the field but not the state
  // (and the Escape shortcut stays off while a rename is open).
  function endPresetEdit() {
    if (panel.editingPresetId === "") return
    panel.editingPresetId = ""
    keyCatcher.forceActiveFocus()
  }

  // Update channel as reported by `omadock-switch status`; probed on open.
  property string channel: ""

  // Whether Hyprland blur is on at all (decoration:blur:enabled); probed on
  // open so the Blur switch can say when it cannot show anything.
  property bool systemBlurEnabled: true
  // Hyprland's blur size right now (decoration:blur:size), probed on open.
  property int currentBlurSize: 0

  // Categories in sidebar order. Page ids are also the IPC names
  // (openSettingsPage), so "presets" and "about" keep their ids.
  readonly property var pages: [
    { id: "appearance", label: "Appearance", glyph: "󰏘" },
    { id: "icons", label: "Icons", glyph: "󰩨" },
    { id: "motion", label: "Motion & Effects", glyph: "󰨙" },
    { id: "behavior", label: "Behavior", glyph: "󰒓" },
    { id: "placement", label: "Placement", glyph: "󰍹" },
    { id: "folders", label: "Folders", glyph: "󰉋" },
    { id: "groups", label: "App Groups", glyph: "󰀻" },
    { id: "presets", label: "Presets", glyph: "󰆓" },
    { id: "about", label: "About", glyph: "󰋼" }
  ]

  // ---------------------------------------------------------- settings search
  // Hits rebuild as the query changes (DockModel.searchSettings). Every row
  // carrying a key is registered under it in registerRows(); a picked hit
  // switches to the row's page and flashes it.
  property var searchHits: []
  property var rowByKey: ({})
  property string flashKey: ""

  // Register every keyed settings row in the page subtree (the row family
  // itself stays presentation-only and knows nothing of this machinery).
  function registerRows() {
    var stack = [pageColumn]
    while (stack.length > 0) {
      var kids = stack.pop().children
      for (var i = 0; i < kids.length; i++) {
        if (kids[i].key) panel.rowByKey[kids[i].key] = kids[i]
        stack.push(kids[i])
      }
    }
  }

  // One owner for the flash: flips the previous target's highlight off and
  // the new one's on; "" clears.
  function setFlash(key) {
    var prev = panel.rowByKey[panel.flashKey]
    if (prev) prev.highlighted = false
    panel.flashKey = key
    var row = panel.rowByKey[key]
    if (row) row.highlighted = true
  }

  // Pages hand focus back to the panel after an inline edit ends.
  function refocus() {
    keyCatcher.forceActiveFocus()
  }

  Timer {
    id: flashTimer
    interval: 2200
    onTriggered: panel.setFlash("")
  }

  function gotoSetting(key) {
    var hit = null
    for (var i = 0; i < panel.searchHits.length; i++)
      if (panel.searchHits[i].key === key) {
        hit = panel.searchHits[i]
        break
      }
    if (!hit) return
    root.settingsPanelPage = hit.page
    searchField.text = ""
    panel.setFlash(key)
    flashTimer.restart()
    pageFlick.contentY = 0
    panel.scrollKey = key
    scrollTimer.restart()
  }

  // The scroll waits a frame so the target page's Column has laid out;
  // measuring in the same event loop turn reads stale positions.
  property string scrollKey: ""
  Timer {
    id: scrollTimer
    interval: 50
    onTriggered: {
      var row = panel.rowByKey[panel.scrollKey]
      if (!row) return
      var top = row.mapToItem(pageColumn, 0, 0).y
      pageFlick.contentY = Math.max(0, Math.min(Math.max(0, pageFlick.contentHeight - pageFlick.height), top - Style.space(24)))
    }
  }


  function pageLabelOf(id) {
    for (var i = 0; i < panel.pages.length; i++)
      if (panel.pages[i].id === id) return panel.pages[i].label
    return ""
  }

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
    registerRows()
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
    enabled: panel.editingGroupId === "" && panel.editingPresetId === ""
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
    // also cancels a group or preset rename, since it would not move focus
    // by itself.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onPressed: {
        panel.endPresetEdit()
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

        TextField {
          id: searchField
          width: parent.width
          placeholderText: "Search settings"
          foreground: Color.menu.text
          onTextChanged: panel.searchHits = text.trim() === "" ? [] : DockModel.searchSettings(text)
        }

        Column {
          id: searchResults
          width: parent.width
          visible: searchField.text.trim() !== ""
          spacing: Style.spacing.xxs

          Repeater {
            model: panel.searchHits
            delegate: Rectangle {
              id: hitRow
              required property var modelData
              width: searchResults.width
              height: Style.space(32)
              radius: Style.cornerRadius > 0 ? Style.space(6) : 0
              color: hitMouse.containsMouse ? Util.alpha(Color.menu.text, 0.07) : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.md
                anchors.right: hitWhere.left
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: hitRow.modelData.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                id: hitWhere
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: panel.pageLabelOf(hitRow.modelData.page)
                textFormat: Text.PlainText
                color: Util.alpha(Color.menu.text, 0.55)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                id: hitMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.gotoSetting(hitRow.modelData.key)
              }
            }
          }

          Text {
            visible: panel.searchHits.length === 0
            topPadding: Style.spacing.sm
            bottomPadding: Style.spacing.sm
            text: "No matches"
            textFormat: Text.PlainText
            color: Util.alpha(Color.menu.text, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Repeater {
          model: panel.pages
          delegate: Rectangle {
            id: navItem
            required property var modelData
            readonly property bool current: panel.page === modelData.id
            visible: searchField.text.trim() === ""

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
        text: panel.pageLabelOf(panel.page)
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

          // One instance per settings page, in sidebar order; each page
          // wires root's settings into its rows.

          SettingsAppearance {
            root: root
            panel: panel
            visible: panel.page === "appearance"
          }

          SettingsIcons {
            root: root
            panel: panel
            visible: panel.page === "icons"
          }

          SettingsMotion {
            root: root
            panel: panel
            visible: panel.page === "motion"
          }

          SettingsBehavior {
            root: root
            panel: panel
            visible: panel.page === "behavior"
          }

          SettingsPlacement {
            root: root
            panel: panel
            visible: panel.page === "placement"
          }

          SettingsFolders {
            root: root
            panel: panel
            visible: panel.page === "folders"
          }

          SettingsGroups {
            root: root
            panel: panel
            visible: panel.page === "groups"
          }

          SettingsPresets {
            root: root
            panel: panel
            visible: panel.page === "presets"
          }

          SettingsAbout {
            root: root
            panel: panel
            visible: panel.page === "about" || panel.page === "supporters"
          }

        }
      }
    }
  }
}
