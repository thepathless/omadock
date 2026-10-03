import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

BorderSurface {
  id: contextMenu

  property var rootRef: null
  readonly property var root: rootRef

  property alias appContextMenuColumn: appContextMenuColumn

  // Folder menu page: "" (actions), "sort" (Sort By) or "view" (View As).
  property string folderPage: ""
  property string dockPage: ""
  onFolderPageChanged: menuFlickable.contentY = 0

  visible: root ? (root.contextAppId !== "") : false
  z: 100
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
  radius: Style.cornerRadius
  padding: Style.space(4)

  readonly property real rowWidth: (root && root.contextAppId !== "")
    ? root.menuContentWidth(menuColumn)
    : 0

  width: (root && root.contextAppId !== "")
    ? rowWidth + contentLeftInset + contentRightInset
    : 0
  height: (root && root.contextAppId !== "")
    ? Math.min(540, menuColumn.implicitHeight + contentTopInset + contentBottomInset)
    : 0


  onVisibleChanged: {
    if (!visible) menuFlickable.contentY = 0
  }

  Connections {
    target: root
    function onContextAppIdChanged() {
      menuFlickable.contentY = 0
      contextMenu.folderPage = ""
      contextMenu.dockPage = ""
    }
  }

  Flickable {
    id: menuFlickable
    anchors.left: parent.left
    anchors.leftMargin: contextMenu.contentLeftInset
    anchors.right: parent.right
    anchors.rightMargin: contextMenu.contentRightInset
    anchors.top: parent.top
    anchors.topMargin: contextMenu.contentTopInset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: contextMenu.contentBottomInset

    contentWidth: width
    contentHeight: menuColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height

    WheelHandler {
      target: menuFlickable
      onWheel: function(event) {
        if (event.angleDelta.y === 0) return
        var step = Style.space(32)
        var dy = event.angleDelta.y > 0 ? -step : step
        menuFlickable.contentY = Math.max(0, Math.min(menuFlickable.contentHeight - menuFlickable.height, menuFlickable.contentY + dy))
      }
    }

    Column {
      id: menuColumn
      width: parent.width
      spacing: Style.space(2)

    // Dock menu (right-click on the Omarchy button or the dock background):
    // quick toggles plus the way into the full settings panel, which holds
    // every option the old category pages used to carry.
    Column {
      spacing: Style.space(2)
      visible: root ? (root.contextAppId === "__dock_settings__" && contextMenu.dockPage === "") : false

      ContextRow {
        text: "Omadock"
        isHeader: true
      }

      ContextRow {
        text: "Dock Settings…"
        textColor: Color.accent
        onTriggered: { if (root) root.openSettingsPanel() }
      }

      ContextRow {
        visible: root ? root.presets.length > 0 : false
        text: "Presets ›"
        onTriggered: contextMenu.dockPage = "presets"
      }

      MenuDivider {}

      ContextRow {
        text: "Autohide"
        checked: root ? root.autohide : false
        onTriggered: { if (root) root.setAutohideMode(root.autohide ? "always" : "intelligent") }
      }

      ContextRow {
        text: "Create Group from Running Apps"
        onTriggered: {
          if (root) {
            root.createAppGroupFromRunning()
            root.closeContext()
          }
        }
      }
    }

    // Dock menu: Presets page
    Column {
      spacing: Style.space(2)
      visible: root ? (root.contextAppId === "__dock_settings__" && contextMenu.dockPage === "presets") : false

      ContextRow {
        text: "‹ Back"
        textColor: Color.accent
        onTriggered: contextMenu.dockPage = ""
      }

      ContextRow {
        text: "Presets"
        isHeader: true
      }

      Repeater {
        model: root ? root.presets : []
        delegate: ContextRow {
          required property var modelData
          text: modelData.name
          checked: root ? root.activePresetId === modelData.id : false
          onTriggered: {
            if (!root) return
            var id = modelData.id
            root.closeContext()
            root.applyPresetAfterMenu(id)
          }
        }
      }

      MenuDivider {}

      ContextRow {
        text: "Manage Presets…"
        onTriggered: {
          if (!root) return
          root.settingsPanelPage = "presets"
          root.openSettingsPanel()
          root.closeContext()
        }
      }
    }

    // Folder Context Menu
    Column {
      spacing: Style.space(2)
      visible: root ? (root.contextAppId === "__folder_context__" && contextMenu.folderPage === "") : false

      ContextRow {
        text: (root ? root.contextFolderName : "") || "Folder"
        isHeader: true
      }

      ContextRow {
        text: "View As: " + (root && root.folderViewFor(root.contextFolderPath) === "grid" ? "Folder" : "Stack") + " ›"
        onTriggered: contextMenu.folderPage = "view"
      }

      ContextRow {
        text: "Sort By: " + (root ? (root.folderSortLabels[root.folderSortFor(root.contextFolderPath)] || "Date Modified") : "Date Modified") + " ›"
        onTriggered: contextMenu.folderPage = "sort"
      }

      MenuDivider {}

      ContextRow {
        text: "Open in File Manager"
        onTriggered: {
          if (root) {
            Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(root.contextFolderPath.replace(/^~/, Quickshell.env("HOME"))))
            root.closeContext()
          }
        }
      }

      ContextRow {
        text: "Open in Terminal"
        onTriggered: {
          if (root) {
            Util.execDetached("uwsm-app -- xdg-terminal-exec --dir=" + Util.shellQuote(root.contextFolderPath.replace(/^~/, Quickshell.env("HOME"))))
            root.closeContext()
          }
        }
      }

      MenuDivider {}

      ContextRow {
        text: "Unpin from Dock"
        danger: true
        onTriggered: {
          if (root) {
            root.toggleFolderPin(root.contextFolderPath, root.contextFolderName, "")
            root.closeContext()
          }
        }
      }
    }

    // Folder menu: View As page. Stack lists entries; Folder shows a grid
    // of larger icons with previews.
    Column {
      spacing: Style.space(2)
      visible: root ? (root.contextAppId === "__folder_context__" && contextMenu.folderPage === "view") : false

      ContextRow {
        text: "‹ Back"
        textColor: Color.accent
        onTriggered: contextMenu.folderPage = ""
      }

      ContextRow {
        text: "View As"
        isHeader: true
      }

      Repeater {
        model: [
          { value: "stack", label: "Stack" },
          { value: "grid", label: "Folder" }
        ]
        delegate: ContextRow {
          required property var modelData
          text: modelData.label
          checked: root ? root.folderViewFor(root.contextFolderPath) === modelData.value : false
          onTriggered: {
            if (!root) return
            root.setFolderView(root.contextFolderPath, modelData.value)
            root.closeContext()
          }
        }
      }
    }

    // Folder menu: Sort By page
    Column {
      spacing: Style.space(2)
      visible: root ? (root.contextAppId === "__folder_context__" && contextMenu.folderPage === "sort") : false

      ContextRow {
        text: "‹ Back"
        textColor: Color.accent
        onTriggered: contextMenu.folderPage = ""
      }

      ContextRow {
        text: "Sort By"
        isHeader: true
      }

      Repeater {
        model: ["name", "kind", "modified", "added", "size"]
        delegate: ContextRow {
          required property string modelData
          text: root ? root.folderSortLabels[modelData] : modelData
          checked: root ? root.folderSortFor(root.contextFolderPath) === modelData : false
          onTriggered: {
            if (!root) return
            root.setFolderSort(root.contextFolderPath, modelData)
            root.closeContext()
          }
        }
      }
    }

    // Minimized Window Tile Context Menu
    Column {
      spacing: Style.space(2)
      visible: root ? root.contextAppId === "__tile_context__" : false

      ContextRow {
        text: (root && root.contextTileName !== "") ? root.contextTileName : ((root && root.contextTileAppId !== "") ? root.contextTileAppId : "Window")
        isHeader: true
      }

      ContextRow {
        text: (root && root.contextTileWins.length > 1) ? "Restore All Here" : "Restore Here"
        onTriggered: {
          if (root) {
            root.restoreContextTile()
            root.closeContext()
          }
        }
      }

      ContextRow {
        text: (root && root.contextTileWins.length > 1) ? "Restore All to Original" : "Restore to Original"
        onTriggered: {
          if (root) {
            root.restoreContextTileOriginal()
            root.closeContext()
          }
        }
      }

      MenuDivider {}

      ContextRow {
        text: (root && root.contextTilePinned) ? "Unpin from Dock" : "Pin to Dock"
        onTriggered: {
          if (root) {
            root.togglePin(root.contextTileAppId)
            root.closeContext()
          }
        }
      }

      MenuDivider {}

      ContextRow {
        text: (root && root.contextTileWins.length > 1) ? "Close All" : "Close"
        danger: true
        onTriggered: {
          if (root) {
            root.closeContextTile()
            root.closeContext()
          }
        }
      }
    }

    // Removable Drive Context Menu
    Column {
      spacing: Style.space(2)
      visible: root ? root.contextAppId === "__drive_context__" : false

      ContextRow {
        text: (root ? root.contextDriveName : "") || "USB Drive"
        isHeader: true
      }

      ContextRow {
        text: root ? (root.contextDriveSpace !== "" ? root.contextDriveSpace : root.contextDriveMount) : ""
        textColor: Util.alpha(Color.menu.text, 0.6)
        isHeader: true
        visible: text !== ""
      }

      MenuDivider {}

      ContextRow {
        text: "Open in File Manager"
        onTriggered: {
          if (root) {
            Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(root.contextDriveMount))
            root.closeContext()
          }
        }
      }

      ContextRow {
        text: "Open in Terminal"
        onTriggered: {
          if (root) {
            Util.execDetached("uwsm-app -- omarchy-terminal -d " + Util.shellQuote(root.contextDriveMount))
            root.closeContext()
          }
        }
      }

      ContextRow {
        text: "Copy Mount Path"
        onTriggered: {
          if (root) {
            Util.execDetached("uwsm-app -- wl-copy " + Util.shellQuote(root.contextDriveMount))
            root.closeContext()
          }
        }
      }

      MenuDivider {}

      ContextRow {
        text: "Safely Eject / Unmount"
        textColor: Color.urgent || Color.accent
        onTriggered: {
          if (root) {
            root.ejectDrive(root.contextDriveDev, root.contextDriveMount, root.contextDriveName)
          }
        }
      }
    }

    // App Group Context Menu
    Column {
      spacing: Style.space(2)
      visible: root ? root.contextAppId === "__app_group_context__" : false

      ContextRow {
        text: (root && root.contextAppGroupData) ? root.contextAppGroupData.name : "App Group"
        isHeader: true
      }

      ContextRow {
        text: (root && root.contextAppGroupData && root.contextAppGroupData.apps) ? (root.contextAppGroupData.apps.length + " Apps") : ""
        textColor: Util.alpha(Color.menu.text, 0.6)
        isHeader: true
        visible: text !== ""
      }

      MenuDivider {}

      ContextRow {
        text: "Open Group Grid"
        onTriggered: {
          if (root && root.contextAppGroupData) {
            root.openAppGroup(root.contextAppGroupData, root.contextX, root.contextY)
            root.closeContext()
          }
        }
      }

      ContextRow {
        text: "Ungroup"
        onTriggered: {
          if (root && root.contextAppGroupData) {
            root.ungroupAppGroup(root.contextAppGroupData.id)
            root.closeContext()
          }
        }
      }

      ContextRow {
        text: "Remove Group"
        danger: true
        onTriggered: {
          if (root && root.contextAppGroupData) {
            root.removeAppGroup(root.contextAppGroupData.id)
            root.closeContext()
          }
        }
      }
    }

    // Regular App Context Menu
    Item {
      id: appContextMenuWrapper
      visible: root ? (root.contextAppId !== "" && root.contextAppId !== "__dock_settings__" && root.contextAppId !== "__folder_context__" && root.contextAppId !== "__tile_context__" && root.contextAppId !== "__drive_context__" && root.contextAppId !== "__app_group_context__") : false
      implicitWidth: appContextMenuColumn.implicitWidth
      implicitHeight: appContextMenuColumn.implicitHeight
      width: contextMenu.rowWidth > 0 ? contextMenu.rowWidth : implicitWidth
      height: appContextMenuColumn.implicitHeight

      Column {
        id: appContextMenuColumn
        spacing: Style.space(2)
        width: contextMenu.rowWidth > 0 ? contextMenu.rowWidth : implicitWidth

        property int selectedWindowIdx: -1

        // 0. Now Playing: media controls for apps that expose an MPRIS
        // player (Spotify and the like, or a browser playing a video), as
        // the macOS dock does. The buttons leave the menu open, so several
        // tracks can be skipped in a row.
        Column {
          id: mediaSection
          readonly property var player: root ? root.contextPlayer : null
          spacing: Style.space(2)
          visible: player !== null
          width: parent.width

          // No window but a live player: the app runs in the background
          // (closed to the tray), which the dock shows as a faint dot.
          ContextRow {
            text: (root && root.contextWindows === 0) ? "Now Playing · in background" : "Now Playing"
            isHeader: true
          }

          Item {
            readonly property bool isMenuContent: true
            readonly property string title: mediaSection.player ? (mediaSection.player.trackTitle || mediaSection.player.identity || "") : ""
            readonly property string artist: mediaSection.player ? (mediaSection.player.trackArtist || "") : ""
            implicitWidth: Math.min(Style.space(260), Math.max(titleLabel.implicitWidth, artistLabel.implicitWidth) + Style.space(16))
            implicitHeight: trackColumn.implicitHeight + Style.space(4)
            width: parent.width
            height: implicitHeight

            Column {
              id: trackColumn
              x: Style.space(8)
              width: parent.width - Style.space(16)
              spacing: Style.space(1)

              Text {
                id: titleLabel
                width: parent.width
                text: parent.parent.title
                textFormat: Text.PlainText
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                id: artistLabel
                visible: text !== ""
                width: parent.width
                text: parent.parent.artist
                textFormat: Text.PlainText
                color: Util.alpha(Color.menu.text, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }

          Row {
            id: mediaButtons
            readonly property bool isMenuContent: true
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(6)

            Repeater {
              model: [
                { id: "previous", glyph: "󰒮", label: "Previous" },
                { id: "toggle", glyph: "", label: "Play / Pause" },
                { id: "next", glyph: "󰒭", label: "Next" }
              ]
              delegate: Rectangle {
                id: mediaButton
                required property var modelData
                readonly property var player: mediaSection.player
                readonly property bool enabledAction: !player ? false
                  : modelData.id === "previous" ? player.canGoPrevious
                  : modelData.id === "next" ? player.canGoNext
                  : player.canTogglePlaying
                width: Style.space(34)
                height: Style.space(28)
                radius: Style.cornerRadius > 0 ? Style.space(6) : 0
                color: mediaMouse.containsMouse && enabledAction ? Color.menu.selectedBackground : "transparent"
                opacity: enabledAction ? 1 : 0.35

                Text {
                  anchors.centerIn: parent
                  text: mediaButton.modelData.id === "toggle"
                    ? (mediaButton.player && mediaButton.player.isPlaying ? "󰏤" : "󰐊")
                    : mediaButton.modelData.glyph
                  textFormat: Text.PlainText
                  color: mediaButton.modelData.id === "toggle" ? Color.accent : Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.iconLarge
                }

                MouseArea {
                  id: mediaMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: mediaButton.enabledAction ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: {
                    var p = mediaButton.player
                    if (!p || !mediaButton.enabledAction) return
                    if (mediaButton.modelData.id === "previous") p.previous()
                    else if (mediaButton.modelData.id === "next") p.next()
                    else p.togglePlaying()
                  }
                }
              }
            }
          }

          MenuDivider {}
        }

        // 1. Multi-window / Active Window instance list
        Column {
          id: windowListSection
          spacing: Style.space(1)
          visible: root ? (root.contextWindowList.length > 0) : false

          ContextRow {
            text: (root && root.contextWindowList.length > 1)
              ? ("Windows (" + root.contextWindowList.length + ")")
              : "Active Window"
            isHeader: true
          }

          Repeater {
            model: root ? root.contextWindowList.slice(0, 8) : []
            delegate: ContextRow {
              text: root ? root.windowRowLabel(modelData) : ""
              isWindowRow: true
              winFocused: root ? root.isWindowFocused(modelData) : false
              winParked: root ? root.isWindowParked(modelData) : false
              checked: appContextMenuColumn.selectedWindowIdx === index

              onTriggered: {
                if (modelData && modelData.address && root) {
                  root.focusWindowByAddress(modelData.address, root.contextAppId)
                }
                if (root) root.closeContext()
              }
            }
          }

          ContextRow {
            visible: root ? (root.contextWindowList.length > 8) : false
            text: "+ " + (root ? (root.contextWindowList.length - 8) : 0) + " more windows"
            isHeader: true
          }

          MenuDivider {}
        }

        // 2. Native Desktop Actions / Jump List
        Column {
          spacing: Style.space(1)
          visible: root ? (root.contextDesktopActions.length > 0) : false

          Repeater {
            model: root ? root.contextDesktopActions : []
            delegate: ContextRow {
              text: modelData.name || modelData.id
              onTriggered: {
                if (root) {
                  root.launchDesktopAction(modelData, root.contextName)
                  root.closeContext()
                }
              }
            }
          }

          MenuDivider {}
        }

        // Fallback Default Action Row when no custom desktop actions exist.
        // A running media app gets playback controls above instead of a
        // second window it rarely supports.
        ContextRow {
          text: (root && root.contextWindows > 0) ? "New Window" : "Launch"
          visible: root ? (root.contextDesktopActions.length === 0 && !(root.contextWindows > 0 && mediaSection.player !== null)) : true
          onTriggered: {
            if (root) {
              root.launchApp(root.contextAppId, null)
              root.closeContext()
            }
          }
        }

        // 3. Window & Dock Management
        ContextRow {
          text: "Minimize Window"
          visible: root ? (root.minimizeMode !== "off" && root.contextWindows > 1) : false
          onTriggered: {
            if (root) {
              root.minimizeOneWindow(root.entryForId(root.contextAppId))
              root.closeContext()
            }
          }
        }

        ContextRow {
          text: (root && root.contextPinned) ? "Unpin from Dock" : "Pin to Dock"
          onTriggered: {
            if (root) {
              var deskEntry = DockModel.entryFor(root.appRows, root.contextAppId)
              if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries) {
                deskEntry = DesktopEntries.heuristicLookup(root.contextAppId) || DesktopEntries.byId(root.contextAppId)
              }
              var canonicalId = (deskEntry && deskEntry.id) ? deskEntry.id : root.contextAppId
              root.togglePin(canonicalId)
              root.closeContext()
            }
          }
        }

        ContextRow {
          text: (root && root.contextWindows > 1) ? "Close All Windows" : "Close Window"
          visible: root ? (root.contextWindows > 0) : false
          danger: true
          onTriggered: {
            if (root) {
              DockModel.closeApp((ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []), root.contextAppId)
              root.closeContext()
            }
          }
        }
      }

      // Wheel-scroll overlay to cycle window selection
      MouseArea {
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
          if (!root || root.contextWindowList.length <= 1) return
          var dir = root.wheelStep("menu", wheel.angleDelta.y)
          if (dir === 0) return
          var len = root.contextWindowList.length
          if (appContextMenuColumn.selectedWindowIdx < 0) {
            var cur = 0
            for (var c = 0; c < len; c++) {
              if (root.isWindowFocused(root.contextWindowList[c])) { cur = c; break }
            }
            appContextMenuColumn.selectedWindowIdx = (cur + dir + len) % len
          } else {
            appContextMenuColumn.selectedWindowIdx = (appContextMenuColumn.selectedWindowIdx + dir + len) % len
          }
        }
      }
    }
  }
}
}
