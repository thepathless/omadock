import QtQuick
import QtQuick.Effects
import qs.Commons

// One icon, drawn in the dock's icon style:
//
//   original  the icon as shipped
//   mono      the icon in one theme colour, its tone kept as ink density
//   pixel     the icon rendered on a coarse grid and scaled up unsmoothed
//   dots      a dot matrix: one round dot per grid cell, ordered-dithered
//             from the icon's brightness, in one theme colour
//
// dropShadow adds a soft shadow that follows the drawn shape, used when the
// dock has no background card to cast one.
//
// showOriginal draws the icon as shipped whatever iconStyle says (the
// "show original on hover" option). The styled layers stay built while it is
// on, so switching back and forth costs no decode or shader rebuild.
//
// hovered and hoverFx (the dock's object) drive the hover effects that keep
// the icon's size; the drawn icon sits inside a HoverFx. With hoverFx.reveal
// the mono and dots styles dither the original in (shaders/iconstyle.frag)
// instead of switching to it at once.
//
// Instead of an image source, the icon can be any item declared inside
// (e.g. a font glyph). Such content is already one colour, so "mono" shows it
// as is (the caller colours it with the tint); "pixel" and "dots" work from
// its rendering.
Item {
  id: art

  property url source
  property string iconStyle: "original"
  property bool showOriginal: false
  // The style actually drawn right now.
  readonly property string shownStyle: (art.showOriginal && !art.revealMode) ? "original" : art.iconStyle
  property bool hovered: false
  property var hoverFx: null
  // The styled shader draws the original itself, dithering it in.
  readonly property bool revealMode: (art.hoverFx ? art.hoverFx.reveal === true : false)
    && (art.iconStyle === "dots" || (art.iconStyle === "mono" && !art.hasCustom))
  property real revealLevel: art.showOriginal ? 1 : 0
  Behavior on revealLevel { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }
  property color tint: Color.bar.text
  // Cells across the icon for the pixel and dots styles.
  property int grid: 16
  // mono / dots: adaptive contrast 0..1, and how much of the effect covers
  // the original icon (1 = effect only, 0 = original).
  property real contrast: 0
  property real strength: 1
  property bool dropShadow: false
  property real shadowStrength: 0.4
  // Size (logical px) the icon is decoded at. Keep it fixed: tying it to the
  // animated width makes every zoom frame decode the icon again, and with
  // asynchronous loading the icon blinks out between frames. Callers pass
  // their largest on-screen size so zoom stays crisp.
  property real renderSize: 64

  readonly property bool usesGrid: art.iconStyle === "pixel" || art.iconStyle === "dots"
  // Declared content (a font glyph) is drawn with thin strokes; a fine grid
  // leaves them a sparse dotted outline that barely differs from the glyph,
  // so such content is capped at a coarser grid.
  readonly property int cells: Math.max(6, Math.min(art.hasCustom ? 14 : 48, art.grid))
  readonly property int status: img.status

  default property alias content: custom.data
  // Drawn over the icon, inside the hover effects but outside the icon
  // styles and the icon shadow (a notification badge): it rises, glows and
  // glitches with the icon yet stays as drawn.
  property alias overlay: overlayLayer.data
  readonly property bool hasCustom: custom.children.length > 0
  // The item the grid styles read from.
  readonly property Item styleSource: art.hasCustom ? custom : img

  HoverFx {
    id: fxHost
    anchors.fill: parent
    hovered: art.hovered
    hoverFx: art.hoverFx
  }

  // Drawn inside fxHost, so hover effects move and outline it.
  Item {
    id: canvas
    parent: fxHost.contentItem
    anchors.fill: parent

    layer.enabled: art.dropShadow
    layer.smooth: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: "#000000"
      shadowOpacity: art.shadowStrength
      shadowBlur: 0.45
      shadowVerticalOffset: Math.max(1, Math.round(art.height * 0.05))
      autoPaddingEnabled: true
    }

    Image {
      id: img
      anchors.fill: parent
      source: art.source
      // One decode size for every style, so switching style (or showing the
      // original on hover) never reloads the image.
      sourceSize: Qt.size(Math.max(16, art.renderSize * Screen.devicePixelRatio), Math.max(16, art.renderSize * Screen.devicePixelRatio))
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
      asynchronous: true
      // Also shows under a mono / dots effect that is not at full strength,
      // and while the pixel grid samples it. That grid stands in for the
      // image on screen and hides it from the scene itself (hideSource), so
      // the image stays rendered as the grid's texture and never shows
      // through the coarse cells.
      readonly property bool underEffect: (art.shownStyle === "mono" || art.shownStyle === "dots") && art.strength < 1
      visible: !art.hasCustom && (art.shownStyle === "original" || underEffect || art.shownStyle === "pixel")
      opacity: underEffect ? 1 - art.strength : 1
    }

    Item {
      id: custom
      anchors.fill: parent
      // Declared content follows the same rule as the image: it stays
      // rendered while the pixel grid reads from it, and the grid hides it
      // from the scene again.
      visible: art.shownStyle === "original" || art.shownStyle === "mono"
        || (art.shownStyle === "dots" && art.strength < 1)
        || (art.shownStyle === "pixel" && art.hasCustom)
      opacity: art.shownStyle === "dots" ? 1 - art.strength : 1
    }

    // Pixel style: the icon rendered onto its grid (averaging each cell) and
    // scaled back up unsmoothed, so every cell is a hard square.
    //
    // This is the grid's side of the source contract: the item it samples
    // (art.styleSource: img, or declared content) stays rendered for this
    // shader, and the grid hides that source from the scene itself with
    // hideSource, instead of leaning on the source's own visible flag to
    // keep it off screen.
    ShaderEffectSource {
      anchors.fill: parent
      visible: art.shownStyle === "pixel"
      sourceItem: art.iconStyle === "pixel" ? art.styleSource : null
      // Only while the grid is the thing on screen: hovering back to the
      // original must not leave the image hidden behind an invisible grid.
      hideSource: art.shownStyle === "pixel"
      textureSize: Qt.size(art.cells, art.cells)
      smooth: false
      live: true
    }

    // Monochrome and dot matrix share one shader (shaders/iconstyle.frag),
    // built only while one of them is selected.
    Loader {
      anchors.fill: parent
      active: art.iconStyle === "dots" || (art.iconStyle === "mono" && !art.hasCustom)
      visible: !art.showOriginal || art.revealMode
      sourceComponent: Item {
        // The dot matrix reads one texel per cell, so the icon is first
        // reduced to two texels per cell with smoothing: each cell then
        // averages its area instead of point-sampling one detail.
        ShaderEffectSource {
          id: styleTexture
          visible: false
          sourceItem: art.styleSource
          textureSize: art.iconStyle === "dots"
            ? Qt.size(art.cells * 2, art.cells * 2)
            : Qt.size(Math.max(16, art.renderSize * Screen.devicePixelRatio), Math.max(16, art.renderSize * Screen.devicePixelRatio))
          smooth: true
          live: true
        }

        // Full-resolution original for the dithered reveal; the dots texture
        // above is reduced to the grid.
        ShaderEffectSource {
          id: originalTexture
          visible: false
          sourceItem: art.revealMode && art.iconStyle === "dots" ? art.styleSource : null
          textureSize: Qt.size(Math.max(16, art.renderSize * Screen.devicePixelRatio), Math.max(16, art.renderSize * Screen.devicePixelRatio))
          smooth: true
          live: true
        }

        ShaderEffect {
          opacity: art.strength
          anchors.fill: parent
          property variant source: styleTexture
          property color tint: art.tint
          property real grid: art.cells
          property real dotFill: 0.72
          property real dimLevel: art.iconStyle === "dots" ? 0.22 : 0.35
          property real invert: art.tint.hslLightness < 0.5 ? 1.0 : 0.0
          property real dots: art.iconStyle === "dots" ? 1.0 : 0.0
          // Thin glyph strokes cover only part of a cell; count them in.
          property real alphaCut: art.hasCustom ? 0.12 : 0.35
          property real contrast: art.contrast
          property real reveal: art.revealMode ? art.revealLevel : 0
          property variant original: art.iconStyle === "dots" ? originalTexture : styleTexture
          fragmentShader: Qt.resolvedUrl("../shaders/iconstyle.frag.qsb")
        }
      }
    }
  }

  Item {
    id: overlayLayer
    parent: fxHost.contentItem
    anchors.fill: parent
    z: 10
  }
}
