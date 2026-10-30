import QtQuick 6.11
import QtQuick.Shapes

// A full-bleed sheet with the card's own silhouette punched out of it, used as
// the mask for the card's drop shadow.
//
// A shadow belongs outside the surface that casts it. The shadow is drawn as a
// blurred black rectangle behind the card, so without this mask its middle is
// still there - and a translucent fill renders that as a grey wash over the
// glass, which is darker than the wallpaper it is supposed to be sampling. The
// mask keeps the halo and drops everything inside the card's rounded edge.
//
// The mask is a texture source (layer.enabled), so a MultiEffect can sample it.
// Odd-even fill turns the inner rounded rectangle into a hole.
Item {
  id: mask

  // Corner radius of the card, and how far its edge sits inside this sheet:
  // the sheet is the shadow's padded box, the card sits in the middle of it.
  property real radius: 0
  property real inset: 0
  property real bottomInset: 0

  readonly property real holeX: inset
  readonly property real holeY: inset
  readonly property real holeW: Math.max(0, width - inset * 2)
  readonly property real holeH: Math.max(0, height - inset - bottomInset)
  readonly property real r: Math.max(0, Math.min(radius, Math.min(holeW, holeH) / 2))

  layer.enabled: true
  visible: false

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: 0
      fillColor: "white"
      fillRule: ShapePath.OddEvenFill

      // The sheet.
      PathMove { x: 0; y: 0 }
      PathLine { x: mask.width; y: 0 }
      PathLine { x: mask.width; y: mask.height }
      PathLine { x: 0; y: mask.height }
      PathLine { x: 0; y: 0 }

      // The card, clockwise from its top-left corner's end.
      PathMove { x: mask.holeX + mask.r; y: mask.holeY }
      PathLine { x: mask.holeX + mask.holeW - mask.r; y: mask.holeY }
      PathArc {
        x: mask.holeX + mask.holeW; y: mask.holeY + mask.r
        radiusX: mask.r; radiusY: mask.r
      }
      PathLine { x: mask.holeX + mask.holeW; y: mask.holeY + mask.holeH - mask.r }
      PathArc {
        x: mask.holeX + mask.holeW - mask.r; y: mask.holeY + mask.holeH
        radiusX: mask.r; radiusY: mask.r
      }
      PathLine { x: mask.holeX + mask.r; y: mask.holeY + mask.holeH }
      PathArc {
        x: mask.holeX; y: mask.holeY + mask.holeH - mask.r
        radiusX: mask.r; radiusY: mask.r
      }
      PathLine { x: mask.holeX; y: mask.holeY + mask.r }
      PathArc {
        x: mask.holeX + mask.r; y: mask.holeY
        radiusX: mask.r; radiusY: mask.r
      }
    }
  }
}
