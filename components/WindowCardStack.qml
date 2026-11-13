import QtQuick 6.11
import Quickshell.Hyprland
import Quickshell.Wayland._Screencopy
import qs.Commons
import qs.Ui
import "../DockOutput.js" as DockOutput

// Still thumbnails of an app's windows, stacked like cards: the front card
// shows windows[frontIndex], up to two more peek out above it, and changing
// frontIndex slides the cards into their new places. Cards exist only while
// the stack is active: a closed tooltip holds no buffers and loads no icons
// (every dock item has a stack, and icon loads at shell start race inside
// Qt). A card captures a single frame the first time it reaches the front
// three and keeps it while it stays near the front: among the front three or
// the last three flipped behind, the ones scrolling back returns to. Beyond
// that it lets the buffer go, so at most six window-sized buffers (about 30
// MB each for a 4K-wide window) live at once however many windows the app
// has; a card coming back captures again, which takes a few milliseconds.
Item {
  id: stack

  property var rootRef: null
  readonly property var root: rootRef
  // Window captures only while the dock's output is there and powered
  // (DockOutput.js): Hyprland aborts on a capture of a vanished output.
  // monitorRev re-runs this on Hyprland's monitor events.
  readonly property bool canCapture: !!stack.root && DockOutput.outputAwake(stack.root.dockScreen ? stack.root.dockScreen.name : "",
    stack.root.dockScreen ? Hyprland.monitorFor(stack.root.dockScreen) : null, stack.root.monitorRev)
  readonly property var motion: stack.root ? stack.root.motion : null
  property var windows: []
  property int frontIndex: 0
  property bool active: false
  property url fallbackIcon: ""

  readonly property int count: windows ? windows.length : 0
  readonly property real frameWidth: Style.space(240)
  // The frame takes the front window's shape once its frame arrives, so a
  // typical window fills the card instead of sitting between bars.
  property real frontAspect: 16 / 10
  readonly property real frameHeight: Math.round(frameWidth / frontAspect)
  Behavior on frontAspect { NumberAnimation { duration: (stack.motion ? stack.motion.fast : 0); easing.type: Easing.OutCubic } }
  readonly property real peek: count > 1 ? Style.space(10) : 0
  readonly property int peeking: Math.max(0, Math.min(count - 1, 2))

  implicitWidth: frameWidth
  implicitHeight: frameHeight + peek * peeking

  Repeater {
    id: cards
    model: stack.active ? stack.count : 0

    delegate: Item {
      id: card
      required property int index

      readonly property var win: stack.windows[index]
      readonly property int depth: (index - stack.frontIndex + stack.count) % stack.count
      readonly property bool shown: depth <= 2
      readonly property bool nearFront: depth <= 2 || depth >= stack.count - 3
      // Set once the card has been among the front three; dropped when it
      // leaves the front, so its buffer goes with it.
      property bool reached: false
      onShownChanged: if (shown) reached = true
      onNearFrontChanged: if (!nearFront) reached = false
      Component.onCompleted: if (shown) reached = true
      readonly property bool captured: !!(capture.item && capture.item.hasContent)
      readonly property bool capturing: !!(capture.item && capture.item.live)
      readonly property real capturedAspect: captured ? capture.item.aspect : 0

      function adoptAspect() {
        if (card.depth === 0 && card.capturedAspect > 0)
          stack.frontAspect = Math.max(1.0, Math.min(2.4, card.capturedAspect))
      }
      onCapturedAspectChanged: adoptAspect()
      onDepthChanged: adoptAspect()

      width: stack.frameWidth
      height: stack.frameHeight
      y: stack.peek * (stack.peeking - Math.min(depth, 2))
      z: 10 - depth
      transformOrigin: Item.Top
      scale: depth === 0 ? 1 : (depth === 1 ? 0.92 : 0.84)
      opacity: depth === 0 ? 1 : (depth === 1 ? 0.8 : (depth === 2 ? 0.55 : 0))

      Behavior on y { NumberAnimation { duration: (stack.motion ? stack.motion.base : 0); easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: (stack.motion ? stack.motion.base : 0); easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: (stack.motion ? stack.motion.base : 0); easing.type: Easing.OutCubic } }

      Rectangle {
        anchors.fill: parent
        radius: Style.space(4)
        color: Color.tooltip.background
        border.width: 1
        border.color: Util.alpha(Color.tooltip.text, card.depth === 0 ? 0.30 : 0.18)
      }

      Image {
        anchors.centerIn: parent
        width: Style.space(40)
        height: width
        sourceSize: Qt.size(width * 2, height * 2)
        source: stack.fallbackIcon
        visible: !(capture.item && capture.item.hasContent)
        opacity: 0.6
      }

      Loader {
        id: capture
        anchors.centerIn: parent
        active: card.reached && !!card.win && stack.canCapture
        sourceComponent: ScreencopyView {
          constraintSize: Qt.size(Math.max(1, stack.frameWidth - 2), Math.max(1, stack.frameHeight - 2))
          // A plain QQuickItem has no implicit size, so the capture was sized
          // to the card's frame (implicitWidth stays 0) and every window took
          // the card's shape: a square window came out wide. Fit sourceSize
          // inside the frame and keep the window's own shape; the bars left
          // over show the card, as a preview letterbox should.
          readonly property real frameAspect: constraintSize.width / Math.max(1, constraintSize.height)
          readonly property real aspect: (sourceSize.width > 0 && sourceSize.height > 0)
            ? sourceSize.width / sourceSize.height : frameAspect
          width: aspect >= frameAspect ? constraintSize.width : constraintSize.height * aspect
          height: width / aspect
          live: true
          captureSource: (card.win && stack.root) ? stack.root.liveToplevelForAddress(card.win.address) : null
          onCaptureSourceChanged: live = true
          onHasContentChanged: if (hasContent) live = false
          onStopped: captureSource = null
        }
      }

      Rectangle {
        visible: card.depth === 0 && stack.count > 1
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(5)
        width: counter.implicitWidth + Style.space(10)
        height: counter.implicitHeight + Style.space(4)
        radius: height / 2
        color: Util.alpha(Color.tooltip.background, 0.85)

        Text {
          id: counter
          anchors.centerIn: parent
          text: (index + 1) + "/" + stack.count
          textFormat: Text.PlainText
          color: Color.tooltip.text
          font.family: Style.font.family
          font.pixelSize: Math.max(9, Style.font.caption - 2)
          font.bold: true
        }
      }
    }
  }
}
