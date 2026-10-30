import QtQuick
import Quickshell
import qs.Commons
import "../DockIcons.js" as DockIcons

// The faded folder shown in the gap the dock opens while a folder from a file
// manager is dragged over it. It grows with the gap, so it slides in rather
// than popping up.
Item {
  id: ghost

  property var rootRef: null
  readonly property var root: rootRef

  clip: true
  visible: width > 1

  Image {
    readonly property real full: ghost.root ? ghost.root.baseIconArt : 28
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: ghost.root ? ghost.root.iconArtBottom : 0
    width: full * Math.min(1, ghost.width / Math.max(1, ghost.root ? ghost.root.iconSlot : 1))
    height: width
    opacity: 0.5
    source: ghost.root ? DockIcons.resolveThemedFolderIcon("folder", ghost.root.iconThemeRef.iconTheme, ghost.root.folderColor, ghost.root.appLibrary) : ""
    sourceSize: Qt.size(full * 2, full * 2)
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
  }
}
