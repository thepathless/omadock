import QtQuick 6.11
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui
import "../DockLabels.js" as DockLabels
import "../DockMarkGeometry.js" as DockMarkGeometry

// The name beside a dock tile's icon (apps, app groups, folders). Policy
// comes from root.labelStyle() (DockLabelLogic); this item shortens the name
// to the max width in its own font, animates the reveal, and reports the
// width it adds to the tile (extra) to the dock's registry, which feeds the
// zoom/wave centres and the card's hover anchor. No input handling: hover,
// drag and clicks belong to the tile.
Item {
  id: label

  property var rootRef: null
  readonly property var root: rootRef
  readonly property var motion: label.root ? label.root.motion : null
  property string kind: "app"
  property string appId: ""
  property string name: ""
  property bool hovered: false
  property Item iconBox: null
  // Room a drop gap opens at the tile's leading edge: the tile proper
  // (and its plate) starts after it.
  property real tileLead: 0
  property int slot: -1
  // The tile's own indicator row, mirrored into a column on the plate when
  // indicators sit beside the art; and the tile's faint "running without a
  // window" mark.
  property var marksFrom: null
  property bool backgroundMarks: false
  // Any always-on name can fold (foldable): "Pinned apps: When running"
  // (labelPinned) folds a sleeping pinned app's, the dock's fit (DockFit.js)
  // folds names when the row runs out of room. The tile says when (folded).
  // A folded name keeps its plate around the icon, and opening widens it.
  readonly property bool foldable: !!label.style && !label.style.hover
  property bool folded: false
  // Folded because the app sleeps or is still starting ("When running"):
  // its window marks wait for the name. A name folded for room keeps them.
  property bool marksHeld: false

  readonly property var style: root ? root.labelStyle(label.kind) : null
  readonly property string fullText: root ? root.labelName(label.appId, label.name) : label.name
  readonly property bool shown: !!label.style && label.style.show && label.fullText !== ""
  readonly property bool mirror: !!label.style && label.style.mirror

  readonly property color ink: label.style ? label.style.ink : Color.bar.text
  readonly property color fill: label.root ? label.root.labelFillFor(label.ink, label.overlay) : "transparent"
  readonly property color halo: (label.root && label.root.isLight(Qt.color(label.ink))) ? "#000000" : "#ffffff"

  // ---- text and width
  property string shortText: ""
  property bool shortened: false
  readonly property real pad: (label.style && label.style.background !== "none") ? Style.space(6) : Style.space(2)
  readonly property bool plate: !!label.style && label.style.background === "plate"
  // Indicators in a column at the plate's edge, before the icon or after the
  // name; the column's room is kept whether or not anything runs.
  readonly property bool sideMarks: label.plate && label.shown && label.style.marks !== "under"
  readonly property bool marksAfter: label.sideMarks && label.style.marks === "after"
  // The column's room opens only while there is something to show, and
  // eases in and out as an app starts or stops.
  readonly property bool hasMarks: !!(label.marksFrom && label.marksFrom.running) || label.backgroundMarks
  // A name held folded (marksHeld) keeps a column only for the faint
  // "playing without a window" mark; its window marks wait for the name to
  // open. A name folded for room keeps all of them.
  property real marksLevel: label.sideMarks && ((label.folded && label.marksHeld) ? label.backgroundMarks : label.hasMarks) ? 1 : 0
  Behavior on marksLevel {
    enabled: !label._landing
    NumberAnimation { duration: (label.motion ? label.motion.base : 0); easing.type: Easing.OutCubic }
  }
  // The column keeps the plate's own padding to the plate's edge (the room a
  // name has at the far end), the marks' own width and a gap to the art or the
  // name: the sizes are the ones the row draws with, from DockMarkGeometry.js,
  // so the room reserved here can never disagree with the marks (the unit tests
  // pin the pair).
  readonly property var markRoom: DockMarkGeometry.column(Style.space, label.root ? label.root.outputScale : 1)
  readonly property real markEdge: label.pad + label.markRoom.edge
  readonly property real markWidth: label.markRoom.width
  readonly property real markGap: label.markRoom.gap
  readonly property real markSpan: label.markEdge + label.markWidth + label.markGap
  // Before the icon, the room sits ahead of the art (less the margin the
  // plate already has there): the tile shifts its icon by this much.
  // A pill plate's round end keeps clear of the art: the room its curve
  // takes at the art's top and bottom (DockLabels.pillRoom), past the margin
  // the slot already has, and the same for the name at the far end.
  readonly property bool pillPlate: label.plate && !!label.style && label.style.shape === "pill"
  readonly property real pillLead: label.pillPlate
    ? Math.max(0, Math.ceil(DockLabels.pillRoom(plateRect.height / 2, (label.root ? label.root.baseIconArt : 0) / 2)) + Style.space(1) - label.artMargin) : 0
  readonly property real pillTrail: label.pillPlate ? Math.ceil(DockLabels.pillRoom(plateRect.height / 2, textItem.implicitHeight / 2)) : 0
  // The column's room past the slot's own margin. A foldable name keeps it
  // while folded (the plate is there), so it is not scaled by progress.
  // The pill curve keeps its own clearance, scaled by progress like a name.
  readonly property real columnRoom: label.marksLevel * Math.max(0, label.markSpan - label.artMargin)
  readonly property real lead: Math.round(Math.max(
    (label.sideMarks && !label.marksAfter) ? (label.foldable ? 1 : label.progress) * label.columnRoom : 0,
    label.progress * label.pillLead))
  // Folded with the column after the icon: its room behind the art, handed
  // over to the name's trail as the name opens.
  readonly property real foldTail: (label.sideMarks && label.marksAfter && label.foldable)
    ? Math.round((1 - label.progress) * label.columnRoom) : 0
  // Empty room between the icon slot's edge and the drawn art.
  readonly property real artMargin: label.root ? (label.root.iconSlot - label.root.baseIconArt) / 2 : Style.space(7)
  // The name is placed from the art's edge, not the slot's: a pill sits
  // 6 px off the art, bare text and a plate's text about 7 px. Negative
  // gaps reach back into the slot's empty margin.
  readonly property real gap: (label.plate ? 0 : label.style && label.style.background === "pill" ? Style.space(6) : Style.space(5)) - label.artMargin
  // An icon carries its slot padding on both sides, plus the empty margin
  // inside its art; the name ends with about the same room, so a label
  // keeps the spacing an icon would before the next item, a divider or the
  // dock's edge. A plate is its own frame and needs only a little.
  readonly property real trail: label.plate ? Style.space(1) + Math.max(label.marksAfter ? label.marksLevel * (label.markSpan - label.pad) : 0, label.pillTrail) : label.artMargin + Style.space(3)
  readonly property real naturalWidth: label.shown && label.shortText !== ""
    ? Math.ceil(textWidth.advanceWidth) + label.pad * 2 + label.gap + label.trail : 0

  // The bundled pixel font registers only while it is the chosen one.
  Loader {
    active: !!label.style && label.style.family === "Silkscreen"
    sourceComponent: FontLoader { source: Qt.resolvedUrl("../fonts/Silkscreen-Regular.ttf") }
  }
  TextMetrics { id: probe; font: textItem.font }
  TextMetrics { id: textWidth; font: textItem.font; text: label.shortText }

  function reshorten() {
    // A deferred call can land in the window where this label's children have
    // been destroyed and the label itself has not (a delegate being torn
    // down): the metrics the search writes into are gone by then, and the
    // write is a null dereference - the fault logged at this line in the wild
    // ("Value is null and could not be converted to an object", during
    // delayed function evaluation). Nothing to measure with, nothing to
    // shorten: leave the name as it is.
    if (!label.style || !probe || !textWidth) return
    // Max width is for the name; the indicator column comes on top of it.
    var limit = label.style.maxWidth - label.pad * 2 - label.gap - (label.plate ? Style.space(1) : label.trail)
    var r = DockLabels.shortenName(label.fullText, function(t) { probe.text = t; return probe.advanceWidth <= limit })
    label.shortText = r.text
    label.shortened = r.shortened
  }
  // Deferred through a child Timer, not Qt.callLater: a queued callLater
  // still runs after the label is torn down, and when the dock's whole
  // instance goes (a plugin reload, a shell restart) its context is already
  // invalid there - the DockLabels import reads as null and the call throws
  // the same fault at the shortenName line, past the guard above. The Timer
  // dies with the label, so nothing is left queued.
  Timer { id: reshortenLater; interval: 0; onTriggered: label.reshorten() }
  onFullTextChanged: reshortenLater.restart()
  onStyleChanged: reshortenLater.restart()

  // ---- open state. Hover mode opens after a short dwell so a sweep across
  // the dock does not ripple; with another label still open or closing it
  // switches at once. Never during a drag.
  property bool dwelled: false
  readonly property bool dragFree: label.root ? !label.root.dockDragActive : true
  readonly property bool wantOpen: label.shown && !label.folded
    && (!label.style.hover || (label.hovered && label.dwelled && label.dragFree))
  Timer {
    id: dwell
    interval: (label.root && label.root.labelsOpen > 0) ? 1 : 150
    onTriggered: label.dwelled = true
  }

  // Counted while open or closing, so the next icon skips the dwell.
  readonly property bool counts: !!label.style && label.style.hover && label.progress > 0.02
  property bool counted: false
  onCountsChanged: {
    if (!label.root || label.counts === label.counted) return
    label.root.labelsOpen += label.counts ? 1 : -1
    label.counted = label.counts
  }
  property real progress: label.wantOpen ? 1 : 0
  // A foldable name widens its tile only where layout eases (Full); at
  // Reduced the width snaps and the name fades (nameFade).
  // While a drag holds an element, and while it settles, a tile opens or
  // closes its name at once: the tile a drop creates stands at the width
  // the drop gap held for it (DockLift). Names do not move otherwise then.
  readonly property bool _landing: !!label.root && !!label.root.dockCard && !!label.root.dockCard.liftRef && label.root.dockCard.liftRef.phase !== ""
  Behavior on progress {
    enabled: !label._landing
    NumberAnimation { duration: (label.motion && (label.motion.layout || !label.foldable) ? label.motion.base : 0); easing.type: Easing.OutCubic }
  }
  property real nameFade: label.wantOpen ? 1 : 0
  Behavior on nameFade { NumberAnimation { duration: (label.motion ? label.motion.fast : 0); easing.type: Easing.OutCubic } }
  // The plate stays put while the name folds into it.
  readonly property bool restingPlate: label.plate && label.shown && label.foldable
  // Hover names float above the bar in their own surface (HoverNamePlate), so
  // they widen no tile, cover no neighbour, and the dock never moves under the
  // pointer.
  readonly property bool overlay: !!label.style && label.style.hover
  // Where the floating name sits above its icon's top: clear of the card's
  // rim and padding, and of the tallest artwork the wave raises. One formula
  // owns it, and a tooltip that accompanies the name (a window preview, a
  // task row) stacks above `chipClear`, so the preview never covers the
  // name; the name is the thing that always shows.
  readonly property real chipGap: Style.space(10) + (label.root
    ? label.root.dockPadPx + label.root.borderWidth
      + (label.root.waveHover ? Math.ceil(label.root.baseIconArt * (label.root.magnifyPeak - 1) / 2) : 0)
    : 0)
  // The chip's box: one line in the look's own font inside the plate's own
  // padding. A line's height belongs to the font, not to the name (the same
  // measure the plate's own Text takes), so it is known before the chip opens:
  // the room a tooltip keeps above the name is final from the first frame, and
  // the preview does not move when the chip lands under it.
  Text {
    id: chipLine
    visible: false
    text: "X"
    textFormat: Text.PlainText
    font.family: label.style ? label.style.family : Style.font.family
    font.pixelSize: label.style ? label.style.fontPx : Style.font.caption
    font.weight: label.style ? label.style.weight : Font.Medium
  }
  readonly property real chipBox: Math.ceil(chipLine.implicitHeight) + Style.space(4) * 2
  readonly property real chipClear: label.chipGap + label.chipBox + Style.space(3)
  readonly property real rawExtra: label.overlay ? 0 : Math.round(label.progress * label.naturalWidth) + label.lead + label.foldTail
  // In a plate row the tile's width lands on the device-pixel grid.
  readonly property real extra: (label.rawExtra > 0 && label.root && label.root.labelPlates)
    ? DockLabels.gridCeil(label.root.iconSlot + label.rawExtra, label.root.outputScale) - label.root.iconSlot
    : label.rawExtra

  // ---- width registry
  readonly property string owner: String(label)
  property int _slot: -1
  function syncExtra() {
    if (!label.root) return
    if (label._slot >= 0 && label._slot !== label.slot) label.root.setLabelExtra(label._slot, label.owner, 0)
    label._slot = label.slot
    // The part ahead of the icon: a mirrored label, or the indicator lead.
    if (label.slot >= 0) label.root.setLabelExtra(label.slot, label.owner, label.extra, label.mirror ? label.extra - label.lead : label.lead)
  }
  onExtraChanged: label.syncExtra()
  onSlotChanged: { label.syncExtra(); label.syncNatural() }
  Component.onCompleted: { label.reshorten(); label.syncExtra(); label.syncNatural() }
  Component.onDestruction: {
    if (label.root && label._slot >= 0) label.root.setLabelExtra(label._slot, label.owner, 0)
    if (label.fitHost && label._nslot >= 0) label.fitHost.setNatural(label._nslot, label.owner, null)
    if (label.root && label.counted) label.root.labelsOpen -= 1
  }

  // The full width for the fit planner (DockFit.js, DockFitHost): from the
  // full name and the targets (never the animated progress or marks level),
  // so it does not depend on the plan it feeds.
  readonly property var fitHost: label.root ? label.root.fitHostRef : null
  TextMetrics { id: fullWidth; font: textItem.font; text: label.fullText }
  readonly property real trailTarget: label.plate ? Style.space(1) + ((label.marksAfter && label.hasMarks) ? label.markSpan - label.pad : 0) : label.artMargin + Style.space(3)
  readonly property var natural: (label.shown && !label.overlay) ? {
    text: fullWidth.advanceWidth,
    inner: label.pad * 2 + label.gap + (label.plate ? Style.space(1) : label.trailTarget),
    outer: label.pad * 2 + label.gap + label.trailTarget
      + ((label.sideMarks && !label.marksAfter && label.hasMarks) ? Math.max(0, label.markSpan - label.artMargin) : 0),
    folded: (label.sideMarks && (label.backgroundMarks || label.hasMarks)) ? Math.max(0, label.markSpan - label.artMargin) : 0
  } : null
  property int _nslot: -1
  function syncNatural() {
    if (!label.fitHost) return
    if (label._nslot >= 0 && label._nslot !== label.slot) label.fitHost.setNatural(label._nslot, label.owner, null)
    label._nslot = label.slot
    if (label.slot >= 0) label.fitHost.setNatural(label.slot, label.owner, label.natural)
  }
  onNaturalChanged: label.syncNatural()

  // ---- reveal (typewriter / scramble swap the text; slide just grows)
  property real revealT: 1
  property string revealStyle: "slide"
  property real seed: 0
  // Always-on labels show the whole name unless an animation is running
  // (a glitch burst); a hover label's erased state must not outlive a
  // switch to always.
  readonly property string drawnText: ((label.style && label.style.hover) || revealAnim.running || eraseAnim.running)
    ? DockLabels.revealFrame(label.shortText, label.revealStyle, label.revealT, label.seed) : label.shortText
  NumberAnimation {
    id: revealAnim
    target: label; property: "revealT"; from: 0; to: 1
    duration: Math.min(300, 25 * Math.max(1, label.shortText.length))
  }
  function reveal(styleName) {
    // Typing and scrambling are one-shot motion (DockMotion reveal).
    if (!label.motion || !label.motion.reveal) { label.revealT = 1; return }
    label.revealStyle = styleName
    label.seed = Math.random() * 100
    eraseAnim.stop()
    revealAnim.restart()
  }
  // Typewriter labels erase as they close.
  NumberAnimation { id: eraseAnim; target: label; property: "revealT"; to: 0; duration: 160 }
  onWantOpenChanged: {
    if (!label.style) return
    // Reveals belong to hover labels; always-on labels just stand there.
    if (!label.style.hover) return
    // Without reveal motion the name stands there whole.
    if (!label.motion || !label.motion.reveal) { revealAnim.stop(); eraseAnim.stop(); label.revealT = 1; return }
    if (label.wantOpen) label.reveal(label.style.reveal)
    else if (label.style.reveal === "typewriter") { revealAnim.stop(); label.revealStyle = "typewriter"; eraseAnim.restart() }
  }
  onShortTextChanged: if (label.wantOpen && label.style && label.style.hover && label.revealT >= 1 && !revealAnim.running) label.reveal(label.style.reveal)

  // ---- hover sync with the icon's HoverFx
  property real hoverLevel: label.hovered ? 1 : 0
  Behavior on hoverLevel { NumberAnimation { duration: (label.motion ? label.motion.base : 0); easing.type: Easing.OutCubic } }
  readonly property string hoverEffect: label.root ? label.root.hoverEffect : ""
  readonly property real liftY: label.hoverEffect === "lift" && label.root ? -label.root.baseIconArt * 0.16 * label.hoverLevel : 0
  // The tile's launch / urgent bounce: a label (and its plate and marks)
  // jumps with the icon, as one button.
  property real bounce: 0
  readonly property real rise: label.liftY + label.bounce
  onHoveredChanged: {
    if (label.hovered) dwell.restart()
    else { dwell.stop(); label.dwelled = false }
    if (label.hovered && label.hoverEffect === "glitch" && label.progress > 0.5) label.reveal("scramble")
  }
  readonly property real glowLevel: !label.style ? 0
    : Math.max(label.style.effect === "glow" ? 0.55 + 0.45 * label.hoverLevel : 0,
               label.hoverEffect === "glow" ? label.hoverLevel : 0)

  // ---- geometry: beside the icon, the whole tile height. A hover name draws
  // nothing in the row: its chip is a popup above the icon.
  x: label.mirror ? label.tileLead : (label.iconBox ? label.iconBox.x + label.iconBox.width : 0)
  width: label.overlay ? 0 : label.extra - label.lead
  height: parent ? parent.height : 0
  visible: !label.overlay && (label.width > 0 || label.restingPlate)

  // The hover name, above the icon and clear of the bar. Its surface is the
  // dock window's popup (TooltipWindow): the chip parses no input, so the
  // pointer keeps hovering the tile underneath it.
  LazyLoader {
    id: chipLoader
    active: label.overlay && label.progress > 0.01
    TooltipWindow {
      target: label.iconBox ? label.iconBox : label.parent
      // Clear of the card's rim, its padding and the wave-lifted artwork: a
      // magnified icon grows upward out of the bar (artwork * peak, centred on
      // its box), and the name floats over it, not into it. `chipGap` is the
      // single owner - the tooltips that accompany the name stack on it.
      gap: label.chipGap
      shown: true
      level: label.progress
      rises: label.root ? !!label.root.motion && label.root.motion.layout : true
      body: hoverPlate

      HoverNamePlate {
        id: hoverPlate
        rootRef: label.rootRef
        text: label.drawnText
        family: label.style ? label.style.family : Style.font.family
        fontPx: label.style ? label.style.fontPx : Style.font.caption
        weight: label.style ? label.style.weight : Font.Medium
        // The box the label reserved above the icon.
        boxHeight: label.chipBox
      }
    }
  }

  // Plate: one surface behind icon and name. The art gets the same margin
  // on its leading side as the name on the trailing one, and the window
  // indicators under the art get the same room below as the art has above,
  // so they sit inside. Its corners stop short of a full pill so the curve
  // never cuts into the icon.
  Rectangle {
    id: plateRect
    visible: label.plate
    readonly property real artSize: label.root ? label.root.baseIconArt : 0
    readonly property real artTop: label.root ? label.height - label.root.iconArtBottom - artSize : 0
    readonly property real vMargin: Style.space(4)
    readonly property real iconW: label.iconBox ? label.iconBox.width : 0
    readonly property real edge: Style.space(1)
    // Side margin: matches the name's padding plus trail (a glyph's own
    // trailing bearing makes that side read wider), up to the slot's edge.
    readonly property real hMargin: Math.min(label.pad + label.trail, label.artMargin)
    // In a plate row (Dock.labelPlates) a plate fills its tile less the
    // shared inset, so plate-plate, plate-edge and plate-divider gaps match;
    // at "dock" height it also reaches the card's top and bottom, the same
    // gap away.
    readonly property var spacing: (label.root && label.root.labelPlates) ? label.root.plateSpacing : null
    readonly property real tileW: label.parent ? label.parent.width - label.tileLead : 0
    // In a plate row the vertical box is shared with the unlabelled tiles'
    // plates (DockLabelLogic.plateBox); otherwise around the art (and the
    // indicators under it).
    readonly property var box: spacing ? label.root.labelPlateBox(label.height) : null
    y: box ? box.y : artTop - vMargin
    height: box ? box.h
      : ((label.sideMarks || label.overlay) ? artTop + artSize : label.height - Style.space(1) - (label.root ? label.root.indicatorLift : 0)) + vMargin - y
    x: spacing ? label.tileLead + spacing.inset - label.x
      : label.mirror ? edge : -iconW - label.lead + label.artMargin - hMargin
    width: spacing ? tileW - 2 * spacing.inset
      : label.mirror
      ? label.width + label.artMargin + artSize + hMargin + label.lead - edge
      : label.width - edge - x
    // Capped so the curve keeps off the icon; a pill makes room instead (pillLead).
    readonly property real baseRadius: label.style ? Math.min(height * (label.pillPlate ? 0.5 : 0.32), DockLabels.labelRadius(label.style.shape, height, label.style.dockRatio)) : 0
    // Nested corners (and an edge corner that would poke out of the panel's
    // curve) know the plate's place in its panel only in a plate row.
    readonly property var corners: DockLabels.plateCorners(label.style ? label.style.shape : "dock", height, baseRadius,
      label.style ? label.style.nestedRadius : 0,
      (spacing && label.root.dockCardComp) ? label.root.dockCardComp.plateEdges[label.slot] : null,
      label.style ? label.style.plateFit : 0)
    radius: baseRadius
    topLeftRadius: corners.tl
    topRightRadius: corners.tr
    bottomLeftRadius: corners.bl
    bottomRightRadius: corners.br
    color: label.style ? Util.alpha(label.fill, label.overlay ? 1 : 0.55 + 0.25 * label.hoverLevel) : "transparent"
    opacity: label.restingPlate ? 1 : label.progress
    // Lifts with the icon and the name, like one button.
    transform: Translate { y: label.rise }
    // Lifted off the icons it covers.
    layer.enabled: label.overlay && visible
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: "#000000"
      shadowOpacity: 0.35
      shadowBlur: 0.5
      shadowVerticalOffset: 1
      autoPaddingEnabled: true
    }
  }

  // Side indicators: the tile's marks as a column in the plate's margin,
  // centred on the art, before the icon or after the name.
  Item {
    id: markColumn
    visible: label.sideMarks
    transform: Translate { y: label.rise }
    opacity: (label.foldable ? 1 : label.progress) * label.marksLevel
    readonly property real artSize: label.root ? label.root.baseIconArt : 0
    readonly property real iconW: label.iconBox ? label.iconBox.width : 0
    // At the plate's leading edge for "before", its trailing edge for
    // "after" (swapped on a mirrored dock), markEdge in from it.
    readonly property bool atLeft: label.marksAfter === label.mirror
    readonly property real centreX: atLeft
      ? plateRect.x + label.markEdge + label.markWidth / 2
      : plateRect.x + plateRect.width - label.markEdge - label.markWidth / 2
    readonly property real centreY: label.root ? label.height - label.root.iconArtBottom - artSize / 2 : 0
    x: centreX
    y: centreY

    DockIndicatorRow {
      rootRef: label.rootRef
      vertical: true
      markInk: label.ink
      moveKey: label.rise + markColumn.x
      x: -width / 2
      y: -height / 2
      windows: label.marksFrom ? label.marksFrom.windows : []
      running: label.marksFrom ? label.marksFrom.running : false
      focused: label.marksFrom ? label.marksFrom.focused : false
      allMinimized: label.marksFrom ? label.marksFrom.allMinimized : false
      urgent: label.marksFrom ? label.marksFrom.urgent : false
      pulse: label.marksFrom ? label.marksFrom.pulse : 1
    }

    DockIndicator {
      rootRef: label.rootRef
      visible: label.backgroundMarks && !(label.marksFrom && label.marksFrom.running)
      inkOverride: label.ink
      moveKey: label.rise + markColumn.x
      x: -width / 2
      y: -height / 2
      kind: "background"
    }
  }

  Item {
    id: clipBox
    // Reaches back over the slot margin a negative gap uses.
    anchors.fill: parent
    anchors.leftMargin: label.mirror ? 0 : Math.min(0, label.gap)
    anchors.rightMargin: label.mirror ? Math.min(0, label.gap) : 0
    clip: label.progress < 0.999

    Item {
      id: content
      x: (label.mirror ? label.trail : label.gap) - (label.mirror ? 0 : Math.min(0, label.gap))
      width: Math.max(0, label.naturalWidth - label.gap - label.trail)
      height: textItem.implicitHeight + Style.space(2)
      // Centred on the icon art, which sits on the dock floor.
      y: label.root ? Math.round(label.height - label.root.iconArtBottom - label.root.baseIconArt / 2 - height / 2) : 0
      opacity: label.foldable ? Math.min(label.progress, label.nameFade) : label.progress
      transform: Translate { y: label.rise }

      Rectangle {
        visible: !!label.style && label.style.background === "pill"
        anchors.fill: parent
        radius: label.style ? DockLabels.labelRadius(label.style.shape, height, label.style.dockRatio) : 0
        color: label.style ? Util.alpha(label.fill, label.overlay ? 1 : label.fill.a) : "transparent"
        layer.enabled: label.overlay && visible
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: "#000000"
          shadowOpacity: 0.35
          shadowBlur: 0.5
          shadowVerticalOffset: 1
          autoPaddingEnabled: true
        }
      }

      // Glow: a lightly blurred copy of the name behind it, under an outline
      // in the same light accent. A wide blur would thin a caption-sized
      // stroke to nothing.
      Text {
        anchors.fill: textItem
        visible: label.glowLevel > 0.01
        text: textItem.text
        textFormat: Text.PlainText
        font: textItem.font
        color: label.style ? label.style.glow : Color.accent
        horizontalAlignment: textItem.horizontalAlignment
        verticalAlignment: Text.AlignVCenter
        opacity: Math.min(1, label.glowLevel * 1.8)
        layer.enabled: visible
        layer.effect: MultiEffect {
          blurEnabled: true
          blur: 0.25
          blurMax: 8
          autoPaddingEnabled: true
        }
      }

      Text {
        id: textItem
        anchors.fill: parent
        anchors.leftMargin: label.pad
        anchors.rightMargin: label.pad
        text: label.drawnText
        textFormat: Text.PlainText
        color: label.ink
        font.family: label.style ? label.style.family : Style.font.family
        font.pixelSize: label.style ? label.style.fontPx : Style.font.caption
        font.weight: label.style ? label.style.weight : Font.Medium
        horizontalAlignment: label.mirror ? Text.AlignRight : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        maximumLineCount: 1
        // A name with no background always gets a faint outline so it reads
        // on any dock fill; Outline makes it strong, Glow tints it.
        readonly property bool bare: !!label.style && label.style.background === "none"
        style: (label.style && (bare || label.style.effect !== "none")) ? Text.Outline : Text.Normal
        styleColor: !label.style ? "transparent"
          : label.style.effect === "glow" ? Util.alpha(label.style.glow, 0.5 + 0.4 * label.glowLevel)
          : label.style.effect === "outline" ? Util.alpha(label.halo, 0.85)
          : Util.alpha(label.halo, 0.55)
      }
    }
  }
}
