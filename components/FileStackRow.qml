import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui
import "../DockModel.js" as DockModel

Item {
  id: frow

  property string name: ""
  property string path: ""
  property string icon: "folder"
  property string subtext: ""
  signal triggered()
  // Drag-and-drop out of the stack finished (action is the Qt.DropAction the
  // target chose, Qt.IgnoreAction when it was dropped nowhere).
  signal dragFinished(int action)

  // file:// URI for drag-and-drop. Each path segment is percent-encoded so
  // spaces, #, ? and non-ASCII names survive the trip through text/uri-list.
  readonly property string fileUri: "file://" + frow.path.split("/").map(encodeURIComponent).join("/")

  property int themeVersion: 0
  property string currentIconThemeName: "Yaru"
  property string folderColor: "theme"
  property var appLibrary: null
  property real menuRowWidth: {
    var p = parent
    while (p) {
      if (p.rowWidth !== undefined) return p.rowWidth
      p = p.parent
    }
    return 0
  }

  readonly property bool isMenuContent: true
  readonly property real rowWidth: frow.menuRowWidth > 0 ? frow.menuRowWidth : frow.implicitWidth

  implicitWidth: Math.max(240, Style.space(8) + Style.space(16) + Style.space(8)
    + label.implicitWidth + (sublabel.text !== "" ? (sublabel.implicitWidth + Style.space(8)) : 0) + Style.space(8))
  width: frow.rowWidth
  height: Math.max(28, Style.space(28))

  readonly property string resolvedIconSource: {
    var _tv = frow.themeVersion
    return DockModel.resolveFileItemIcon(frow.icon, frow.currentIconThemeName, frow.folderColor, frow.appLibrary || null)
  }
  readonly property bool isIconSymbolic: resolvedIconSource.indexOf("-symbolic.svg") >= 0 || resolvedIconSource.indexOf("symbolic") >= 0
  readonly property color symbolicColor: {
    if (frow.folderColor === "white") return "#ffffff"
    if (frow.folderColor === "black") return "#111111"
    return (Color.bar.background.hslLightness < 0.5 || Color.background.hslLightness < 0.5) ? "#ffffff" : "#111111"
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: area.containsMouse ? Color.menu.selectedBackground : "transparent"
  }

  Item {
    id: content
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(16, label.implicitHeight)

    Item {
      id: iconHolder
      width: Style.space(16)
      height: Style.space(16)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter

      Image {
        id: stackRowImg
        anchors.fill: parent
        source: frow.resolvedIconSource
        sourceSize: Qt.size(48, 48)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        visible: !frow.isIconSymbolic
      }

      Item {
        anchors.fill: parent
        visible: frow.isIconSymbolic

        Image {
          id: symStackImg
          anchors.fill: parent
          source: frow.resolvedIconSource
          sourceSize: Qt.size(48, 48)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          mipmap: true
          visible: false
        }

        MultiEffect {
          anchors.fill: symStackImg
          source: symStackImg
          // Symbolic icons are dark grey; colorization keeps the source's
          // lightness, so lift it to white first or light colours come out grey.
          brightness: 1.0
          colorization: 1.0
          colorizationColor: frow.symbolicColor
        }
      }
    }

    Text {
      id: sublabel
      visible: frow.subtext !== ""
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: frow.subtext
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      id: label
      anchors.left: iconHolder.right
      anchors.leftMargin: Style.space(8)
      anchors.right: sublabel.visible ? sublabel.left : parent.right
      anchors.rightMargin: sublabel.visible ? Style.space(8) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: frow.name
      textFormat: Text.PlainText
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideMiddle
    }
  }

  // Invisible drag proxy: moving it past the drag threshold starts a
  // platform drag (Drag.Automatic) carrying the file as text/uri-list, the
  // format file managers, browsers and chat apps accept.
  Item {
    id: dragProxy
    width: 1
    height: 1
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
    Drag.proposedAction: Qt.CopyAction
    Drag.mimeData: ({ "text/uri-list": frow.fileUri + "\r\n", "text/plain": frow.path })
    // Only while dragging: the drag image loads synchronously on assignment.
    Drag.imageSource: area.drag.active ? frow.resolvedIconSource : ""
    Drag.imageSourceSize: Qt.size(32, 32)
    Drag.active: area.drag.active
    Drag.onDragFinished: function(action) {
      dragProxy.x = 0
      dragProxy.y = 0
      frow.dragFinished(action)
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    drag.target: frow.path !== "" ? dragProxy : null
    onClicked: frow.triggered()
  }
}
