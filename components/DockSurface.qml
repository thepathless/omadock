import QtQuick 6.11
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

  readonly property color effectiveBorderColor: root ? root.rimColor : Util.alpha(Color.menu.border, 0.48)

  // A gradient fill is drawn by the layer below instead of the card colour.
  readonly property bool gradientFill: root ? (root.showBackground && root.bgFill === "gradient") : false
  // The card's body (root.surfaceBody): the fill's colour at the look's own
  // lightness and chroma, at the look's stability. With no material set that
  // is exactly the fill at the dock's opacity, as before.
  color: (root && (!root.showBackground || surface.gradientFill)) ? "transparent"
    : ((root && root.dockBgColor === "none") ? effectiveBgColor
      : (root ? root.surfaceBody(effectiveBgColor, root.effectiveDockOpacity)
              : Util.alpha(effectiveBgColor, 1.0)))
  borderSpec: (root && !root.showBorder)
    ? Border.none()
    : Border.flat(surface.effectiveBorderColor, (root && root.placement.panel) ? surface.borderWidth + " 0 0 0" : surface.borderWidth)
  radius: root ? root.cardRadius(height) : Style.cornerRadius

  // Gradient fill (shaders/gradient.frag): the palette's colours fading
  // into each other over the theme background, at the dock's opacity. Under
  // the grain and the icons; built only while the gradient is on. A
  // negative z draws it under this Rectangle itself, so the native rim
  // (border.color/width) stays on top instead of being painted over.
  Loader {
    anchors.fill: parent
    z: -1
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

  // Specular glass over the fill (shaders/glass.frag): a light layer, not a
  // tint, so the fill and the compositor's blur behind it stay the dock's own
  // background. 0 draws nothing and keeps the surface exactly as it was.
  Loader {
    anchors.fill: parent
    z: 0.4
    active: root ? (root.showBackground && root.surfaceGlass > 0) : false
    sourceComponent: ShaderEffect {
      property real strength: root ? root.surfaceGlass : 0
      property real radius: surface.radius
      property size size: Qt.size(width, height)
      fragmentShader: Qt.resolvedUrl("../shaders/glass.frag.qsb")
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
