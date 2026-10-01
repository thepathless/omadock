import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import "../DockModel.js" as DockModel

// One entry in a folder stack's grid view: a large icon, or a preview when
// the entry has one (images themselves, or a thumbnail a file manager already
// rendered), with the name underneath. Clicks and drag-out behave like
// FileStackRow.
Item {
  id: tile

  property string name: ""
  property string path: ""
  property string icon: "folder"
  property string thumb: ""
  property bool isDir: false
  property int themeVersion: 0
  property string currentIconThemeName: "Yaru"
  property string folderColor: "theme"
  // Set by the popup, which knows the backdrop the tile sits on.
  property color symbolicColor: "#ffffff"
  property var appLibrary: null

  signal triggered()
  signal dragFinished(int action)

  readonly property string fileUri: "file://" + tile.path.split("/").map(encodeURIComponent).join("/")
  readonly property string resolvedIconSource: {
    var _tv = tile.themeVersion
    return DockModel.resolveFileItemIcon(tile.icon, tile.currentIconThemeName, tile.folderColor, tile.appLibrary || null)
  }
  readonly property bool isIconSymbolic: resolvedIconSource.indexOf("symbolic") >= 0
  readonly property bool hasPreview: tile.thumb !== "" && preview.status !== Image.Error

  width: Style.space(92)
  height: Style.space(100)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: area.containsMouse ? Color.menu.selectedBackground : "transparent"
  }

  Item {
    id: art
    anchors.horizontalCenter: parent.horizontalCenter
    y: Style.space(8)
    width: Style.space(56)
    height: Style.space(56)

    // Preview, cropped to a square card.
    Image {
      id: preview
      anchors.fill: parent
      visible: tile.hasPreview
      source: tile.thumb !== "" ? "file://" + tile.thumb.split("/").map(encodeURIComponent).join("/") : ""
      sourceSize: Qt.size(Style.space(112), Style.space(112))
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      mipmap: true
    }

    Rectangle {
      anchors.fill: parent
      visible: tile.hasPreview
      color: "transparent"
      radius: Math.min(Style.cornerRadius, Style.space(6))
      border.color: Util.alpha(Color.menu.text, 0.15)
      border.width: 1
    }

    Image {
      id: iconImg
      anchors.fill: parent
      visible: !tile.hasPreview && !tile.isIconSymbolic
      source: tile.resolvedIconSource
      sourceSize: Qt.size(Style.space(112), Style.space(112))
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
    }

    // Symbolic icons are grey templates: recoloured as in the list view.
    MultiEffect {
      anchors.fill: iconImg
      visible: !tile.hasPreview && tile.isIconSymbolic
      source: iconImg
      brightness: 1.0
      colorization: 1.0
      colorizationColor: tile.symbolicColor
    }
  }

  Text {
    anchors.top: art.bottom
    anchors.topMargin: Style.space(6)
    anchors.horizontalCenter: parent.horizontalCenter
    width: parent.width - Style.space(8)
    horizontalAlignment: Text.AlignHCenter
    text: tile.name
    textFormat: Text.PlainText
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WrapAnywhere
    maximumLineCount: 2
    elide: Text.ElideMiddle
  }

  // Invisible drag proxy, as in FileStackRow: a platform drag carrying the
  // entry as text/uri-list.
  Item {
    id: dragProxy
    width: 1
    height: 1
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
    Drag.proposedAction: Qt.CopyAction
    Drag.mimeData: ({ "text/uri-list": tile.fileUri + "\r\n", "text/plain": tile.path })
    // Only while dragging: the drag image loads synchronously, and for a
    // photo that would mean decoding the full file for every tile up front.
    Drag.imageSource: area.drag.active ? (tile.hasPreview ? preview.source : tile.resolvedIconSource) : ""
    Drag.imageSourceSize: Qt.size(48, 48)
    Drag.active: area.drag.active
    Drag.onDragFinished: function(action) {
      dragProxy.x = 0
      dragProxy.y = 0
      tile.dragFinished(action)
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    drag.target: tile.path !== "" ? dragProxy : null
    onClicked: tile.triggered()
  }
}
