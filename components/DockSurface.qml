import QtQuick
import qs.Commons
import qs.Ui

// The dock's background panel: fill (solid, translucent or gradient), grain
// and rim. The card draws one across its full width, or one per section when
// sections are split.
BorderSurface {
  id: surface

  property var rootRef: null
  readonly property var root: rootRef
  // Snapped to device pixels by the card, which also lays out by it.
  property real borderWidth: 1.5

  readonly property color effectiveBgColor: {
    if (!root) return Color.bar.background
    if (root.dockBgColor === "none") return Qt.rgba(0, 0, 0, 0.25)
    if (root.dockBgColor === "theme" || !root.dockBgColor) return Color.bar.background
    return root.dockBgColor
  }

  readonly property color effectiveBorderColor: {
    if (!root) return Util.alpha(Color.menu.border, 0.48)
    // Specular Frosted Glass Rim: Crisp highlight with high alpha for contrast on dark and light surfaces
    var autoAlpha = (root.effectiveDockOpacity < 0.25 || root.dockBgColor === "none")
      ? 0.48
      : Math.max(0.24, root.effectiveDockOpacity * 0.35)
    // Manual override from Settings → Appearance → Border opacity.
    var rimAlpha = root.borderOpacity < 0 ? autoAlpha : Math.max(0.0, Math.min(1.0, root.borderOpacity))
    return Util.alpha(root.dockForeground, rimAlpha)
  }

  // A gradient fill is drawn by the layer below instead of the card colour.
  readonly property bool gradientFill: root ? (root.showBackground && root.bgFill === "gradient") : false
  color: (root && (!root.showBackground || surface.gradientFill)) ? "transparent"
    : ((root && root.dockBgColor === "none") ? effectiveBgColor : Util.alpha(effectiveBgColor, root ? root.effectiveDockOpacity : 1.0))
  borderSpec: (root && !root.showBorder)
    ? Border.none()
    : Border.flat(surface.effectiveBorderColor, surface.borderWidth)
  radius: root ? root.cardRadius(height) : Style.cornerRadius

  // Gradient fill (shaders/gradient.frag): the palette's colours fading
  // into each other over the theme background, at the dock's opacity. Under
  // the grain and the icons; built only while the gradient is on.
  Loader {
    anchors.fill: parent
    z: 0.25
    active: surface.gradientFill
    sourceComponent: ShaderEffect {
      readonly property var palette: root ? root.gradientColors : []
      property color base: Util.alpha(Color.bar.background, root ? root.effectiveDockOpacity : 1.0)
      property color c1: palette.length > 0 ? palette[0] : "transparent"
      property color c2: palette.length > 1 ? palette[1] : c1
      property color c3: palette.length > 2 ? palette[2] : c2
      property real count: palette.length > 2 ? 3 : 2
      property real strength: root ? root.gradientStrength : 0.6
      property real radius: surface.radius
      property size size: Qt.size(width, height)
      fragmentShader: Qt.resolvedUrl("../shaders/gradient.frag.qsb")
    }
  }

  // Film grain over the background (shaders/grain.frag), in the style of
  // Zen / Arc browser themes: soft grey specks at low opacity, cut to the
  // card's rounded shape. Static, so it costs nothing between frames;
  // built only while grain is on.
  Loader {
    anchors.fill: parent
    z: 0.5
    active: root ? (root.showBackground && root.grain > 0) : false
    sourceComponent: ShaderEffect {
      property real strength: root ? root.grain : 0
      property real radius: surface.radius
      property size size: Qt.size(width, height)
      fragmentShader: Qt.resolvedUrl("../shaders/grain.frag.qsb")
    }
  }
}
