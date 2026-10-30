import QtQuick 6.11
import QtQuick.Effects
import qs.Commons
import qs.Ui

// The name a "hover" look floats above its icon: a rounded chip in its own
// popup surface (TooltipWindow), a clear gap above the bar, so it covers no
// neighbour and the row needs no room for it.
//
// Its material is the dock's own: floatingBody carries the card body's hue and
// chroma at full stability - a chip floats over the wallpaper, with no blurred
// card behind it to borrow a body from - moved away from the ink the dock chose
// for that body (dockForeground) until the pair reads on a dark wallpaper as on
// a light one. Same ink, same rule, only the separation grows.
BorderSurface {
  id: chip

  property var rootRef: null
  readonly property var root: rootRef
  property string text: ""
  property string family: ""
  property int fontPx: 12
  property int weight: Font.Medium
  // The box the label reserved above the icon, measured from the same font
  // before this chip exists (DockLabel.chipBox). Zero measures itself.
  property real boxHeight: 0

  readonly property real padX: Style.space(9)
  readonly property real padY: Style.space(4)

  // What the card's body is made of: the look's own fill (or the theme's bar
  // colour), exactly as DockSurface picks it.
  readonly property color baseFill: {
    if (!chip.root) return Color.bar.background
    var name = String(chip.root.dockBgColor || "")
    if (name === "none") return Qt.rgba(0, 0, 0, 0.25)
    if (name === "theme" || name.length === 0) return Color.bar.background
    try { return Qt.color(name) } catch (e) { return Color.bar.background }
  }

  // The card's body, opaque, at the separation its own ink needs.
  readonly property color fill: chip.root
    ? chip.root.floatingBody(chip.baseFill, chip.root.effectiveDockOpacity, chip.ink)
    : Qt.rgba(0.09, 0.09, 0.10, 1.0)
  readonly property color ink: chip.root ? chip.root.dockForeground : Color.bar.text

  TextMetrics {
    id: measure
    font: chipText.font
    text: chip.text
  }

  Text {
    id: chipText
    anchors.fill: parent
    anchors.leftMargin: chip.padX
    anchors.rightMargin: chip.padX
    text: chip.text
    textFormat: Text.PlainText
    color: chip.ink
    font.family: chip.family
    font.pixelSize: chip.fontPx
    font.weight: chip.weight
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    maximumLineCount: 1
  }

  width: Math.ceil(measure.advanceWidth) + chip.padX * 2
  height: chip.boxHeight > 0 ? chip.boxHeight : chipText.implicitHeight + chip.padY * 2
  radius: Math.min(chip.height / 2, Style.space(9))
  color: chip.fill
  borderSpec: Border.flat(Util.alpha(chip.ink, 0.14), 1)

  // Lifted off the wallpaper it floats over.
  layer.enabled: true
  layer.effect: MultiEffect {
    shadowEnabled: true
    shadowColor: "#000000"
    shadowOpacity: 0.38
    shadowBlur: 0.55
    shadowVerticalOffset: 2
    autoPaddingEnabled: true
  }
}
