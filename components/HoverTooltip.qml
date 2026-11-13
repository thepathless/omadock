import QtQuick 6.11
import Quickshell
import qs.Commons
import qs.Ui

// Hover bubble for an item: shows after tooltipDelay, above its parent, in
// its own popup surface (TooltipWindow), so the dock layer needs no room
// for it. The item itself has no size; place it anywhere inside the target.
Item {
  id: bubble

  property string text: ""
  // Windows shown as live preview cards under the label (an app group's
  // member windows); empty keeps the plain one-line bubble.
  property var windows: []
  // >= 0 pins which window sits at the front of the stack (a scroll-cycled
  // member preview); -1 keeps the default front: the focused window when
  // there is one, else the first.
  property int cycleIndex: -1
  property url fallbackIcon: ""
  property bool hovered: false
  property bool blocked: false
  property bool shown: false

  property bool showTooltips: true
  property int tooltipDelay: 450
  property string contextAppId: ""
  // The dock root, for the shared tooltip warmth (TooltipLife).
  property var dockRoot: null
  // What the bubble points at; a tile with a label passes its icon.
  property Item target: bubble.parent
  // Height of the band kept clear under the bubble for a floating hover
  // name, measured from the target's top: the chip sits between the bubble
  // and the bar, so the bubble stacks above it instead of covering it. Zero
  // (or no hover name) falls back to the plain gap.
  property real chipClear: 0

  width: 0
  height: 0

  onHoveredChanged: {
    if (bubble.hovered) dwell.restart()
    else {
      dwell.stop()
      bubble.shown = false
    }
  }

  onBlockedChanged: if (bubble.blocked) {
    dwell.stop()
    bubble.shown = false
  }

  // No wait while another tooltip is still up: moving along the dock
  // cross-fades from one to the next.
  Timer {
    id: dwell
    interval: (bubble.dockRoot && bubble.dockRoot.tooltipsAlive > 0) ? 1 : bubble.tooltipDelay
    onTriggered: bubble.shown = true
  }

  TooltipLife {
    id: life
    dockRoot: bubble.dockRoot
    // A menu opening hides it at once.
    hideDelay: (bubble.blocked || bubble.contextAppId !== "") ? 0 : 200
    want: bubble.shown && bubble.text !== "" && bubble.showTooltips && !bubble.blocked && bubble.contextAppId === ""
  }

  // The popup window exists only while the bubble is alive.
  LazyLoader {
    active: life.alive

    TooltipWindow {
      target: bubble.target
      gap: bubble.chipClear > 0 ? bubble.chipClear : Style.space(8)
      shown: true
      level: life.level
      rises: life.rises
      body: bubbleSurface

      BorderSurface {
        id: bubbleSurface
        color: Color.tooltip.background
        borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
        radius: Style.cornerRadius
        padding: Style.space(4)
        width: bubbleContent.implicitWidth + contentLeftInset + contentRightInset
        height: bubbleContent.implicitHeight + contentTopInset + contentBottomInset

        Column {
          id: bubbleContent
          x: bubbleSurface.contentLeftInset
          y: bubbleSurface.contentTopInset
          spacing: Style.space(3)

          Text {
            id: bubbleLabel
            text: bubble.text
            textFormat: Text.PlainText
            color: Color.tooltip.text
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }

          // The same card stack an app's tooltip carries. The front card is
          // the focused member window when there is one.
          WindowCardStack {
            id: cardStack
            readonly property bool wanted: bubble.dockRoot ? (bubble.dockRoot.advancedTooltips && bubble.windows.length > 0) : false
            visible: wanted
            width: wanted ? implicitWidth : 0
            height: wanted ? implicitHeight : 0
            anchors.horizontalCenter: parent.horizontalCenter
            rootRef: bubble.dockRoot
            windows: bubble.windows
            active: wanted && life.alive
            fallbackIcon: bubble.fallbackIcon
            frontIndex: {
              if (bubble.cycleIndex >= 0 && bubble.cycleIndex < bubble.windows.length) return bubble.cycleIndex
              var fi = bubble.dockRoot ? bubble.dockRoot.focusedIndex(bubble.windows) : -1
              return fi >= 0 ? fi : 0
            }
          }

          Text {
            visible: cardStack.wanted
            width: Math.min(implicitWidth, cardStack.width)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: (cardStack.wanted && bubble.dockRoot) ? bubble.dockRoot.windowRowLabel(bubble.windows[cardStack.frontIndex]) : ""
            textFormat: Text.PlainText
            color: Util.alpha(Color.tooltip.text, 0.80)
            font.family: Style.font.family
            font.pixelSize: Math.max(10, Style.font.caption - 1)
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }
      }
    }
  }

}
