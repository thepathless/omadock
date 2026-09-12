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
  property var targetCard: root ? (root.dockCardComp || root.dockCard) : null
  property var targetWindow: root ? root.contentItemRef : null

  property alias appContextMenuColumn: appContextMenuColumn

  visible: root ? (root.contextAppId !== "") : false
  z: 100
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
  radius: Style.cornerRadius
  padding: Style.space(4)

  readonly property real rowWidth: (root && root.contextAppId !== "" && root.settingsSubmenu !== undefined)
    ? root.menuContentWidth(menuColumn)
    : 0

  width: (root && root.contextAppId !== "")
    ? rowWidth + contentLeftInset + contentRightInset
    : 0
  height: (root && root.contextAppId !== "")
    ? Math.min(540, menuColumn.implicitHeight + contentTopInset + contentBottomInset)
    : 0

  anchors.bottom: targetCard ? targetCard.top : undefined
  anchors.bottomMargin: Style.space(6)
  x: Math.max(Style.gapsOut, Math.min((targetWindow ? targetWindow.width : 1920) - width - Style.gapsOut, (root ? root.contextX : 0) - width / 2))

  onVisibleChanged: {
    if (!visible) menuFlickable.contentY = 0
  }

  Connections {
    target: root
    function onContextAppIdChanged() { menuFlickable.contentY = 0 }
    function onSettingsSubmenuChanged() { menuFlickable.contentY = 0 }
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

    // Dock Settings Menu (when right-clicking leftmost Omarchy icon)
    Column {
      spacing: Style.space(1)
      visible: root ? root.contextAppId === "__dock_settings__" : false

      // 1. Main Categories Page (Minimalist & Categorized)
      Column {
        spacing: Style.space(2)
        visible: root ? root.settingsSubmenu === "" : false

        ContextRow {
          text: "Omadock Settings"
          isHeader: true
        }

        ContextRow {
          text: "Appearance ›"
          onTriggered: { if (root) root.settingsSubmenu = "appearance" }
        }

        ContextRow {
          text: "Placement & Alignment ›"
          onTriggered: { if (root) root.settingsSubmenu = "alignment" }
        }

        ContextRow {
          text: "Behavior & Windows ›"
          onTriggered: { if (root) root.settingsSubmenu = "behavior" }
        }

        ContextRow {
          text: "Effects & Animations ›"
          onTriggered: { if (root) root.settingsSubmenu = "effects" }
        }

        ContextRow {
          text: "Size & Spacing ›"
          onTriggered: { if (root) root.settingsSubmenu = "size_spacing" }
        }

        ContextRow {
          text: "Folders & Stacks ›"
          onTriggered: { if (root) root.settingsSubmenu = "folders" }
        }

        ContextRow {
          text: "App Folders & Groups ›"
          onTriggered: { if (root) root.settingsSubmenu = "app_groups" }
        }
      }

      // Placement & Alignment Category Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "alignment" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "" }
        }

        ContextRow {
          text: "Dock Alignment"
          isHeader: true
        }

        ContextRow {
          text: "Center (Default)"
          checked: root ? (root.alignment === "center" || !root.alignment) : true
          onTriggered: { if (root) root.setDockAlignment("center") }
        }

        ContextRow {
          text: "Left Aligned"
          checked: root ? root.alignment === "left" : false
          onTriggered: { if (root) root.setDockAlignment("left") }
        }

        ContextRow {
          text: "Right Aligned"
          checked: root ? root.alignment === "right" : false
          onTriggered: { if (root) root.setDockAlignment("right") }
        }
      }

      // App Folders & Groups Category Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "app_groups" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "" }
        }

        ContextRow {
          text: "App Folders & Groups"
          isHeader: true
        }

        ContextRow {
          text: "+ Create Group from Running Apps..."
          textColor: Color.accent
          onTriggered: {
            if (root) {
              root.createAppGroupFromRunning()
              root.settingsSubmenu = ""
              root.closeContext()
            }
          }
        }

        MenuDivider {}

        Repeater {
          model: (root && root.appGroups) ? root.appGroups : []
          delegate: ContextRow {
            text: (modelData.name || "Group") + " (" + (modelData.apps ? modelData.apps.length : 0) + " apps) - Remove"
            danger: true
            onTriggered: {
              if (root) {
                root.removeAppGroup(modelData.id)
              }
            }
          }
        }
      }

      // Folders & Stacks Category Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "folders" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "" }
        }

        ContextRow {
          text: "Folder Color: " + (root ? root.folderColorLabel(root.folderColor) : "") + " ›"
          onTriggered: { if (root) root.settingsSubmenu = "folder_color" }
        }

        MenuDivider {}

        ContextRow {
          text: "Pinned Folder Stacks"
          isHeader: true
        }

        ContextRow {
          text: "+ Add Custom Folder..."
          textColor: Color.accent
          onTriggered: {
            if (root && root.customFolderPickerProc) root.customFolderPickerProc.running = true
            if (root) root.closeContext()
          }
        }

        MenuDivider {}

        ContextRow {
          text: "Downloads (~/Downloads)"
          checked: root ? root.isFolderPinned("~/Downloads") : false
          onTriggered: { if (root) root.toggleFolderPin("~/Downloads", "Downloads", "folder-download") }
        }

        ContextRow {
          text: "Documents (~/Documents)"
          checked: root ? root.isFolderPinned("~/Documents") : false
          onTriggered: { if (root) root.toggleFolderPin("~/Documents", "Documents", "folder-documents") }
        }

        ContextRow {
          text: "Pictures (~/Pictures)"
          checked: root ? root.isFolderPinned("~/Pictures") : false
          onTriggered: { if (root) root.toggleFolderPin("~/Pictures", "Pictures", "folder-pictures") }
        }

        ContextRow {
          text: "Projects (~/Projects)"
          checked: root ? root.isFolderPinned("~/Projects") : false
          onTriggered: { if (root) root.toggleFolderPin("~/Projects", "Projects", "folder-development") }
        }

        ContextRow {
          text: "Music (~/Music)"
          checked: root ? root.isFolderPinned("~/Music") : false
          onTriggered: { if (root) root.toggleFolderPin("~/Music", "Music", "folder-music") }
        }

        ContextRow {
          text: "Videos (~/Videos)"
          checked: root ? root.isFolderPinned("~/Videos") : false
          onTriggered: { if (root) root.toggleFolderPin("~/Videos", "Videos", "folder-videos") }
        }

        ContextRow {
          text: "Home (~/)"
          checked: root ? root.isFolderPinned("~") : false
          onTriggered: { if (root) root.toggleFolderPin("~", "Home", "user-home") }
        }

        MenuDivider {}

        ContextRow {
          text: "Show Removable USB Drives"
          checked: root ? root.showRemovableDrives : true
          onTriggered: {
            if (root) {
              root.showRemovableDrives = !root.showRemovableDrives
              root.saveConfig()
              root.scanRemovableDrives()
            }
          }
        }
      }

      // Folders & Stacks > Folder Color Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "folder_color" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "folders" }
        }

        ContextRow {
          text: "Folder Color & Style"
          isHeader: true
        }

        ContextRow {
          text: "Auto (Match Theme)"
          checked: root ? (root.folderColor === "theme" || !root.folderColor) : true
          onTriggered: { if (root) root.setFolderColor("theme") }
        }

        MenuDivider {}

        ContextRow {
          text: "Color Presets"
          isHeader: true
        }

        Item {
          readonly property bool isMenuContent: true
          implicitWidth: Math.max(220, 6 * Style.space(24) + 5 * Style.space(4) + Style.space(16))
          implicitHeight: 2 * Style.space(24) + Style.space(4) + Style.space(8)
          width: contextMenu.rowWidth > 0 ? contextMenu.rowWidth : implicitWidth
          height: implicitHeight

          Grid {
            anchors.centerIn: parent
            columns: 6
            spacing: Style.space(4)

            readonly property var colorPresets: [
              { id: "white", name: "White", color: "#ffffff" },
              { id: "black", name: "Black", color: "#111111" },
              { id: "Yaru-sage", name: "Sage Green", color: "#61895a" },
              { id: "Yaru-olive", name: "Olive", color: "#878846" },
              { id: "Yaru-blue", name: "Blue", color: "#3d7ab8" },
              { id: "Yaru-purple", name: "Purple", color: "#775aa6" },
              { id: "Yaru-magenta", name: "Magenta", color: "#b3497d" },
              { id: "Yaru-red", name: "Red", color: "#c73838" },
              { id: "Yaru-yellow", name: "Yellow", color: "#d9a13b" },
              { id: "Yaru-wartybrown", name: "Brown", color: "#8a583e" },
              { id: "Yaru-prussiangreen", name: "Teal", color: "#2d7f7b" },
              { id: "Yaru-dark", name: "Charcoal", color: "#3c3b37" }
            ]

            Repeater {
              model: parent.colorPresets
              delegate: Rectangle {
                id: fColorSwatch
                required property var modelData
                width: Style.space(24)
                height: Style.space(24)
                radius: Style.space(4)
                color: modelData.color
                border.color: (root && root.folderColor === modelData.id)
                  ? Color.accent
                  : Util.alpha(Color.menu.border, 0.8)
                border.width: (root && root.folderColor === modelData.id) ? 2 : 1

                Rectangle {
                  visible: root && (root.folderColor === fColorSwatch.modelData.id)
                  anchors.centerIn: parent
                  width: Style.space(8)
                  height: Style.space(8)
                  radius: Style.space(4)
                  color: fColorSwatch.modelData.id === "white" ? "#111111" : "#ffffff"
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { if (root) root.setFolderColor(fColorSwatch.modelData.id) }
                }
              }
            }
          }
        }
      }

      // 2. Appearance Category Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "appearance" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "" }
        }

        ContextRow {
          text: "Appearance"
          isHeader: true
        }

        ContextRow {
          text: "Shape: " + (root ? (root.dockShape === "theme" || root.dockShape === "auto" ? "Auto (Theme)" : (root.dockShape === "round" || root.dockShape === "pill" ? "Round" : (root.dockShape === "square" ? "Square" : "Rounded"))) : "Rounded") + " ›"
          onTriggered: { if (root) root.settingsSubmenu = "shape" }
        }

        ContextRow {
          text: "Opacity: " + (root ? (root.dockOpacity < 0 ? "Auto (Theme)" : (root.dockOpacity >= 0.95 ? "Opaque" : (root.dockOpacity >= 0.75 ? "Glass" : (root.dockOpacity >= 0.55 ? "Frosted Glass" : (root.dockOpacity >= 0.20 ? "Translucent" : "Transparent"))))) : "Opaque") + " ›"
          onTriggered: { if (root) root.settingsSubmenu = "opacity" }
        }

        ContextRow {
          text: "Color: " + (root ? (root.dockBgColor === "theme" || !root.dockBgColor ? "Theme" : (root.dockBgColor === "none" ? "No Color" : "Custom")) : "Theme") + " ›"
          onTriggered: { if (root) root.settingsSubmenu = "color" }
        }
      }

      // 3. Behavior & Windows Category Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "behavior" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "" }
        }

        ContextRow {
          text: "Behavior & Windows"
          isHeader: true
        }

        ContextRow {
          text: "Autohide: " + (root ? (root.autohide ? (root.intelligentAutohide ? "Intelligent" : "Auto Hide") : "Always Show") : "Intelligent") + " ›"
          onTriggered: { if (root) root.settingsSubmenu = "autohide" }
        }

        ContextRow {
          text: "Minimize On Click: " + (root ? (root.minimizeMode === "all" ? "All Windows" : (root.minimizeMode === "active" ? "Active Window" : "Disabled")) : "Active Window") + " ›"
          onTriggered: { if (root) root.settingsSubmenu = "minimize" }
        }

        ContextRow {
          text: "Urgent Highlights"
          checked: root ? root.showUrgentHint : true
          onTriggered: {
            if (root) {
              root.showUrgentHint = !root.showUrgentHint
              root.saveConfig()
            }
          }
        }

        ContextRow {
          text: "Urgent On Notification"
          checked: root ? root.urgentOnNotification : true
          onTriggered: {
            if (root) {
              root.urgentOnNotification = !root.urgentOnNotification
              root.saveConfig()
            }
          }
        }

        ContextRow {
          text: "Urgent Sound: " + (root ? (root.urgentSoundName === "message-new-instant" ? "Message" : (root.urgentSoundName === "complete" ? "Complete" : (root.urgentSoundName === "dialog-information" ? "Information" : (root.urgentSoundName === "dialog-warning" ? "Warning" : (root.urgentSoundName === "phone-incoming-call" ? "Phone" : (root.urgentSoundName === "alarm-clock-elapsed" ? "Alarm" : (root.urgentSoundName === "none" ? "Mute" : "Bell"))))))) : "Bell") + " ›"
          onTriggered: { if (root) root.settingsSubmenu = "urgent_sound" }
        }
      }

      // 4. Effects & Animations Category Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "effects" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "" }
        }

        ContextRow {
          text: "Effects & Animations"
          isHeader: true
        }

        ContextRow {
          text: "Hover: " + (root ? (root.hoverEffect === "wave" ? "Wave" : (root.hoverEffect === "off" ? "None" : "Zoom")) : "Zoom") + " ›"
          onTriggered: { if (root) root.settingsSubmenu = "hover" }
        }

        ContextRow {
          text: "Launch Bounce"
          checked: root ? root.launchBounce : true
          onTriggered: {
            if (root) {
              root.launchBounce = !root.launchBounce
              root.saveConfig()
            }
          }
        }

        ContextRow {
          text: "Window Previews"
          checked: root ? root.advancedTooltips : true
          onTriggered: {
            if (root) {
              root.advancedTooltips = !root.advancedTooltips
              root.saveConfig()
            }
          }
        }

        ContextRow {
          text: "Show Tooltips"
          checked: root ? root.showTooltips : true
          onTriggered: {
            if (root) {
              root.showTooltips = !root.showTooltips
              root.saveConfig()
            }
          }
        }

        ContextRow {
          text: "Minimized Window Previews"
          checked: root ? root.showMinimizedTiles : true
          onTriggered: {
            if (root) {
              root.showMinimizedTiles = !root.showMinimizedTiles
              root.saveConfig()
            }
          }
        }
      }

      // Hover Effect Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "hover" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "effects" }
        }

        ContextRow {
          text: "Hover Effect"
          isHeader: true
        }

        ContextRow {
          text: "Zoom"
          checked: root ? (root.hoverEffect !== "wave" && root.hoverEffect !== "off") : true
          onTriggered: { if (root) root.setHoverEffect("zoom") }
        }

        ContextRow {
          text: "Wave"
          checked: root ? (root.hoverEffect === "wave") : false
          onTriggered: { if (root) root.setHoverEffect("wave") }
        }

        ContextRow {
          text: "None"
          checked: root ? (root.hoverEffect === "off") : false
          onTriggered: { if (root) root.setHoverEffect("off") }
        }
      }

      // 5. Size & Spacing Category Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "size_spacing" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "" }
        }

        ContextRow {
          text: "Size & Spacing"
          isHeader: true
        }

        ContextRow {
          text: "Icon Size: " + (root ? root.iconSize : 36) + "px ›"
          onTriggered: { if (root) root.settingsSubmenu = "size" }
        }

        ContextRow {
          text: "Spacing: " + (root ? (root.itemSpacing <= 2 ? "Compact" : (root.itemSpacing <= 5 ? "Normal" : "Relaxed")) : "Normal") + " ›"
          onTriggered: { if (root) root.settingsSubmenu = "spacing" }
        }
      }

      // 6. Autohide Submenu Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "autohide" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "behavior" }
        }

        ContextRow {
          text: "Autohide Mode"
          isHeader: true
        }

        ContextRow {
          text: "Always Show"
          checked: root ? !root.autohide : false
          onTriggered: { if (root) root.setAutohideMode("always") }
        }

        ContextRow {
          text: "Intelligent Autohide"
          checked: root ? (root.autohide && root.intelligentAutohide) : true
          onTriggered: { if (root) root.setAutohideMode("intelligent") }
        }

        ContextRow {
          text: "Auto Hide"
          checked: root ? (root.autohide && !root.intelligentAutohide) : false
          onTriggered: { if (root) root.setAutohideMode("autohide") }
        }
      }

      // 7. Minimize Mode Submenu Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "minimize" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "behavior" }
        }

        ContextRow {
          text: "Minimize On Click"
          isHeader: true
        }

        ContextRow {
          text: "Disabled"
          checked: root ? (root.minimizeMode === "off") : false
          onTriggered: {
            if (root) {
              root.minimizeMode = "off"
              root.saveConfig()
            }
          }
        }

        ContextRow {
          text: "Active Window (Most Recent)"
          checked: root ? (root.minimizeMode === "active") : true
          onTriggered: {
            if (root) {
              root.minimizeMode = "active"
              root.saveConfig()
            }
          }
        }

        ContextRow {
          text: "All Windows of App"
          checked: root ? (root.minimizeMode === "all") : false
          onTriggered: {
            if (root) {
              root.minimizeMode = "all"
              root.saveConfig()
            }
          }
        }
      }

      // Urgent Sound Alert Submenu Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "urgent_sound" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "behavior" }
        }

        ContextRow {
          text: "Urgent Sound Alert"
          isHeader: true
        }

        ContextRow {
          text: "Bell (Default)"
          checked: root ? (root.urgentSoundName === "bell") : true
          onTriggered: { if (root) root.setUrgentSoundName("bell") }
        }

        ContextRow {
          text: "Message Chime"
          checked: root ? (root.urgentSoundName === "message-new-instant") : false
          onTriggered: { if (root) root.setUrgentSoundName("message-new-instant") }
        }

        ContextRow {
          text: "Complete Ding"
          checked: root ? (root.urgentSoundName === "complete") : false
          onTriggered: { if (root) root.setUrgentSoundName("complete") }
        }

        ContextRow {
          text: "Information Pop"
          checked: root ? (root.urgentSoundName === "dialog-information") : false
          onTriggered: { if (root) root.setUrgentSoundName("dialog-information") }
        }

        ContextRow {
          text: "Warning Alert"
          checked: root ? (root.urgentSoundName === "dialog-warning") : false
          onTriggered: { if (root) root.setUrgentSoundName("dialog-warning") }
        }

        ContextRow {
          text: "Phone Ring"
          checked: root ? (root.urgentSoundName === "phone-incoming-call") : false
          onTriggered: { if (root) root.setUrgentSoundName("phone-incoming-call") }
        }

        ContextRow {
          text: "Alarm Beeps"
          checked: root ? (root.urgentSoundName === "alarm-clock-elapsed") : false
          onTriggered: { if (root) root.setUrgentSoundName("alarm-clock-elapsed") }
        }

        ContextRow {
          text: "Mute / Silent"
          checked: root ? (root.urgentSoundName === "none") : false
          onTriggered: { if (root) root.setUrgentSoundName("none") }
        }
      }

      // 8. Shape Submenu Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "shape" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "appearance" }
        }

        ContextRow {
          text: "Dock Shape"
          isHeader: true
        }

        ContextRow {
          text: "Auto (Theme)"
          checked: root ? (root.dockShape === "theme" || root.dockShape === "auto") : true
          onTriggered: { if (root) root.setDockShape("theme") }
        }

        ContextRow {
          text: "Rounded"
          checked: root ? (root.dockShape === "rounded") : false
          onTriggered: { if (root) root.setDockShape("rounded") }
        }

        ContextRow {
          text: "Round (Pill)"
          checked: root ? (root.dockShape === "round" || root.dockShape === "pill") : false
          onTriggered: { if (root) root.setDockShape("round") }
        }

        ContextRow {
          text: "Square"
          checked: root ? (root.dockShape === "square") : false
          onTriggered: { if (root) root.setDockShape("square") }
        }
      }

      // 9. Background Color Submenu Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "color" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "appearance" }
        }

        ContextRow {
          text: "Background Color"
          isHeader: true
        }

        ContextRow {
          text: "Theme (Default)"
          checked: root ? (root.dockBgColor === "theme" || !root.dockBgColor) : true
          onTriggered: { if (root) root.setDockBgColor("theme") }
        }

        ContextRow {
          text: "No Color"
          checked: root ? (root.dockBgColor === "none") : false
          onTriggered: { if (root) root.setDockBgColor("none") }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(Color.menu.border, 0.4)
        }

        ContextRow {
          text: "Presets"
          isHeader: true
        }

        Item {
          readonly property bool isMenuContent: true
          implicitWidth: Math.max(220, 5 * Style.space(24) + 4 * Style.space(4) + Style.space(16))
          implicitHeight: 2 * Style.space(24) + Style.space(4) + Style.space(8)
          width: contextMenu.rowWidth > 0 ? contextMenu.rowWidth : implicitWidth
          height: implicitHeight

          Grid {
            id: swatchGrid
            anchors.centerIn: parent
            columns: 5
            spacing: Style.space(4)

            readonly property var presetColors: [
              "#000000", "#181825", "#1e1e2e", "#0f172a", "#111827",
              "#062e24", "#1c1917", "#2c0b16", "#1e102d", "#334155"
            ]

            Repeater {
              model: parent.presetColors
              delegate: Rectangle {
                id: swatchRect
                required property string modelData
                width: Style.space(24)
                height: Style.space(24)
                radius: Style.space(4)
                color: modelData
                border.color: (root && root.dockBgColor === modelData)
                  ? Color.accent
                  : Util.alpha(Color.menu.border, 0.8)
                border.width: (root && root.dockBgColor === modelData) ? 2 : 1

                Rectangle {
                  visible: root && (root.dockBgColor === swatchRect.modelData)
                  anchors.centerIn: parent
                  width: Style.space(8)
                  height: Style.space(8)
                  radius: Style.space(4)
                  color: Color.accent
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { if (root) root.setDockBgColor(swatchRect.modelData) }
                }
              }
            }
          }
        }
      }

      // 10. Background Opacity Submenu Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "opacity" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "appearance" }
        }

        ContextRow {
          text: "Background Opacity"
          isHeader: true
        }

        ContextRow {
          text: "Auto (Theme)"
          checked: root ? (root.dockOpacity < 0) : true
          onTriggered: { if (root) root.setDockOpacity(-1.0) }
        }

        ContextRow {
          text: "Opaque (100%)"
          checked: root ? (root.dockOpacity >= 0.95) : false
          onTriggered: { if (root) root.setDockOpacity(1.0) }
        }

        ContextRow {
          text: "Glass (80%)"
          checked: root ? (root.dockOpacity >= 0.75 && root.dockOpacity < 0.95) : false
          onTriggered: { if (root) root.setDockOpacity(0.80) }
        }

        ContextRow {
          text: "Frosted Glass (65%)"
          checked: root ? (root.dockOpacity >= 0.55 && root.dockOpacity < 0.75) : false
          onTriggered: { if (root) root.setDockOpacity(0.65) }
        }

        ContextRow {
          text: "Translucent (35%)"
          checked: root ? (root.dockOpacity >= 0.20 && root.dockOpacity < 0.55) : false
          onTriggered: { if (root) root.setDockOpacity(0.35) }
        }

        ContextRow {
          text: "Transparent (0%)"
          checked: root ? (root.dockOpacity >= 0.0 && root.dockOpacity < 0.20) : false
          onTriggered: { if (root) root.setDockOpacity(0.0) }
        }
      }

      // 11. Icon Size Submenu Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "size" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "size_spacing" }
        }

        ContextRow {
          text: "Icon Size"
          isHeader: true
        }

        ContextRow {
          text: "Small (28px)"
          checked: root ? (root.configuredIconSize === 28) : false
          onTriggered: { if (root) root.setIconSize(28) }
        }

        ContextRow {
          text: "Medium (36px)"
          checked: root ? (root.configuredIconSize === 36 || (root.configuredIconSize === 0 && root.iconSize === 36)) : true
          onTriggered: { if (root) root.setIconSize(36) }
        }

        ContextRow {
          text: "Large (44px)"
          checked: root ? (root.configuredIconSize === 44) : false
          onTriggered: { if (root) root.setIconSize(44) }
        }

        ContextRow {
          text: "Extra Large (52px)"
          checked: root ? (root.configuredIconSize === 52) : false
          onTriggered: { if (root) root.setIconSize(52) }
        }
      }

      // 12. Icon Spacing Submenu Page
      Column {
        spacing: Style.space(1)
        visible: root ? root.settingsSubmenu === "spacing" : false

        ContextRow {
          text: "‹ Back"
          textColor: Color.accent
          onTriggered: { if (root) root.settingsSubmenu = "size_spacing" }
        }

        ContextRow {
          text: "Icon Spacing"
          isHeader: true
        }

        ContextRow {
          text: "Compact (2px)"
          checked: root ? (root.itemSpacing === 2) : false
          onTriggered: { if (root) root.setItemSpacing(2) }
        }

        ContextRow {
          text: "Normal (4px)"
          checked: root ? (root.itemSpacing === 4) : true
          onTriggered: { if (root) root.setItemSpacing(4) }
        }

        ContextRow {
          text: "Relaxed (8px)"
          checked: root ? (root.itemSpacing === 8) : false
          onTriggered: { if (root) root.setItemSpacing(8) }
        }
      }
    }

    // Folder Context Menu
    Column {
      spacing: Style.space(2)
      visible: root ? root.contextAppId === "__folder_context__" : false

      ContextRow {
        text: (root ? root.contextFolderName : "") || "Folder"
        isHeader: true
      }

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
        text: "Ungroup / Remove Group"
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

        // Fallback Default Action Row when no custom desktop actions exist
        ContextRow {
          text: (root && root.contextWindows > 0) ? "New Window" : "Launch"
          visible: root ? (root.contextDesktopActions.length === 0) : true
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
          if (!root || wheel.angleDelta.y === 0 || root.contextWindowList.length <= 1) return
          var dir = wheel.angleDelta.y > 0 ? -1 : 1
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
