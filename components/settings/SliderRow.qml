import QtQuick 6.11
import qs.Commons
import qs.Ui

// SettingRow with a slider and value readout.

SettingRow {
  id: sliderRow
  property real value: 0

  // A hidden row can lose its mouse grab mid-drag without ever getting a
  // release; drop the drag state so the knob cannot stick to the cursor.
  onVisibleChanged: if (!visible && slider.dragging) slider.dragging = false
  property real minimum: 0
  property real maximum: 1
  property real step: 1
  property string suffix: ""
  property real displayScale: 1
  // Decimals shown next to the slider (0 rounds to whole numbers).
  property int displayDecimals: 0
  signal committed(real value)

  // PanelSlider reads its palette from a bar-shaped object.
  QtObject {
    id: sliderPalette
    property color foreground: Color.menu.text
    property color background: Color.menu.background
  }

  Row {
    spacing: Style.spacing.lg

    PanelSlider {
      id: slider
      objectName: "settings-slider-" + sliderRow.key
      activeFocusOnTab: true
      Keys.onPressed: function(event) {
        var direction = event.key === Qt.Key_Right || event.key === Qt.Key_Up ? 1
          : event.key === Qt.Key_Left || event.key === Qt.Key_Down ? -1 : 0
        if (direction === 0) return
        sliderRow.committed(Math.max(sliderRow.minimum, Math.min(sliderRow.maximum, sliderRow.value + direction * sliderRow.step)))
        event.accepted = true
      }
      onActiveFocusChanged: if (activeFocus && sliderRow.settingsPanel) sliderRow.settingsPanel.keepFocusVisible(sliderRow)
      Rectangle {
        anchors.fill: parent
        anchors.margins: -Style.space(3)
        visible: slider.activeFocus
        color: "transparent"
        border.color: Color.accent
        border.width: 1
        radius: Style.cornerRadius
      }
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(180)
      bar: sliderPalette
      minimum: sliderRow.minimum
      maximum: sliderRow.maximum
      step: sliderRow.step
      integer: sliderRow.step >= 1
      value: sliderRow.value
      onReleased: function(v) {
        sliderRow.committed(v)
        // Belt and braces: if the press was ever canceled (grab stolen or the
        // row hidden mid-drag), PanelSlider never resets its drag state and the
        // knob follows the cursor. Re-assert it on every release/commit.
        slider.dragging = false
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
      horizontalAlignment: Text.AlignRight
      text: (slider.liveValue * sliderRow.displayScale).toFixed(sliderRow.displayDecimals) + sliderRow.suffix
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
}
