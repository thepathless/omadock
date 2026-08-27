import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BorderSurface {
  id: folderStackPopover

  property var rootRef: null
  readonly property var root: rootRef
  property var targetCard: root ? root.dockCard : null
  property var targetWindow: root ? root.contentItemRef : null

  visible: root ? (root.activeStackFolder !== "" && root.dockVisible) : false
  opacity: (root && root.activeStackFolder !== "" && root.dockVisible) ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 120 } }

  z: 100
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
  radius: Style.cornerRadius
  padding: Style.space(4)

  readonly property real rowWidth: (root && root.activeStackFolder !== "")
    ? root.menuContentWidth(stackColumn)
    : 0

  width: (root && root.activeStackFolder !== "")
    ? rowWidth + contentLeftInset + contentRightInset
    : 0
  height: (root && root.activeStackFolder !== "")
    ? stackColumn.implicitHeight + contentTopInset + contentBottomInset
    : 0

  anchors.bottom: targetCard ? targetCard.top : undefined
  anchors.bottomMargin: Style.space(6)
  x: Math.max(Style.gapsOut, Math.min((targetWindow ? targetWindow.width : 1920) - width - Style.gapsOut, (root ? root.activeStackX : 0) - width / 2))

  Column {
    id: stackColumn
    spacing: Style.space(2)

    anchors.left: parent.left
    anchors.leftMargin: folderStackPopover.contentLeftInset
    anchors.right: parent.right
    anchors.rightMargin: folderStackPopover.contentRightInset
    anchors.top: parent.top
    anchors.topMargin: folderStackPopover.contentTopInset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: folderStackPopover.contentBottomInset

    ContextRow {
      text: ((root ? root.activeStackName : "") || "Folder") + ((root && root.activeStackTotalCount > 0) ? (" (" + root.activeStackTotalCount + ")") : "")
      isHeader: true
    }

    Text {
      visible: root ? root.activeStackEntries.length === 0 : true
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "Folder is empty"
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      padding: Style.space(8)
    }

    Repeater {
      model: root ? root.activeStackEntries.slice(0, 16) : []
      delegate: FileStackRow {
        name: modelData.name
        path: modelData.path
        icon: modelData.icon
        subtext: modelData.size
        themeVersion: root ? root.themeVersion : 0
        currentIconThemeName: root ? root.currentIconThemeName : "Yaru"
        folderColor: root ? root.folderColor : "theme"
        onTriggered: {
          Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(modelData.path))
          if (root) root.closeFolderStack()
        }
      }
    }

    // The scanner caps at 16 entries; tell the user when the folder holds
    // more instead of silently truncating.
    ContextRow {
      visible: root ? (root.activeStackTotalCount > root.activeStackEntries.length) : false
      text: "+ " + (root ? (root.activeStackTotalCount - root.activeStackEntries.length) : 0) + " more — open in File Manager"
      onTriggered: {
        if (root) {
          Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(root.activeStackFolder.replace(/^~/, Quickshell.env("HOME"))))
          root.closeFolderStack()
        }
      }
    }

    MenuDivider {
      visible: root ? (root.activeStackTotalCount > root.activeStackEntries.length) : false
    }

    ContextRow {
      text: "Open in File Manager"
      onTriggered: {
        if (root) {
          Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(root.activeStackFolder.replace(/^~/, Quickshell.env("HOME"))))
          root.closeFolderStack()
        }
      }
    }
  }
}
