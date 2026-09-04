import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BorderSurface {
  id: bubble

  property string text: ""
  property bool hovered: false
  property bool blocked: false
  property bool shown: false

  property bool showTooltips: true
  property int tooltipDelay: 450
  property string contextAppId: ""

  visible: bubble.shown && bubble.text !== "" && bubble.showTooltips
    && !bubble.blocked && bubble.contextAppId === ""
  z: 300
  color: Color.tooltip.background
  borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
  radius: Style.cornerRadius
  padding: Style.space(4)
  width: bubbleLabel.implicitWidth + contentLeftInset + contentRightInset
  height: bubbleLabel.implicitHeight + contentTopInset + contentBottomInset

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

  Timer {
    id: dwell
    interval: bubble.tooltipDelay
    onTriggered: bubble.shown = true
  }

  Text {
    id: bubbleLabel
    x: bubble.contentLeftInset
    y: bubble.contentTopInset
    text: bubble.text
    textFormat: Text.PlainText
    color: Color.tooltip.text
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
