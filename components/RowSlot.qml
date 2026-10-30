import QtQuick

// One element of the dock's row as it enters and leaves (DockMotion). The
// slot is as wide as its element times `appear`, so the neighbours and the
// card ease along; the element scales up from 0.6 and fades in with it.
// Repeater rows set `fresh` and `leaving` (KeyedListModel); a single element
// (the Omarchy button) or a row that hides itself sets `shown`. Reduced
// keeps only the fade (the width snaps); Off changes at once.
Item {
  id: slot

  property var rootRef: null
  readonly property var root: rootRef
  readonly property var motion: root ? root.motion : null
  property bool fresh: false
  property bool leaving: false
  property bool shown: true
  readonly property bool wanted: slot.shown && !slot.leaving

  // A drag inside the dock picks the element up (DockLift). Its slot gives
  // up exactly the room the drop gaps take (DockLift.gapSum), at most
  // itself and the row spacing after it, so the dock keeps its width while
  // the element is held and while it settles; where no gap opens its room
  // stays empty. Dropped into another run, a group or off the dock, the
  // slot eases shut from the room it had left. The slot the drop lands in
  // shows its element only once the dragged copy has settled there.
  property string liftKey: ""
  readonly property var lift: (root && root.dockCard) ? root.dockCard.liftRef : null
  readonly property bool lifted: slot.liftKey !== "" && !!slot.lift && slot.lift.key === slot.liftKey
  readonly property bool liftSource: slot.liftKey !== "" && !!slot.lift && slot.lift.phase !== "" && slot.lift.sourceKey === slot.liftKey
  readonly property bool landing: slot.liftKey !== "" && !!slot.lift && slot.lift.landKey === slot.liftKey
  property bool _exiting: false
  property real _kept: 0
  onLeavingChanged: {
    if (slot.leaving && slot.lift && slot.lift.handsOff(slot.liftKey)) {
      // Its room goes to the slots that take its place (DockLift.handOn).
      slot.lift.noteHanded(slot.liftKey, slot.visible ? slot.width + slot._spacing : 0)
      slot._start(0)
    } else if (slot.leaving && slot.liftSource) {
      slot._kept = Math.min(slot.lift.heldGapSum, slot.full + slot._spacing)
      slot._exiting = true
      // Without layout motion (Reduced) its room goes at once.
      if (!(slot.motion && slot.motion.layout)) slot._start(0)
    } else if (!slot.leaving) {
      slot._exiting = false
    }
  }
  // The dock's rows all space their elements by gapWidth.
  readonly property real _spacing: root ? root.gapWidth : 0
  readonly property real _given: slot._exiting ? slot._kept * slot.appear + slot._spacing * (1 - slot.appear)
    : slot.liftSource ? Math.min(slot.lift.gapSum, slot.full + slot._spacing) : 0

  // Taking others' place (DockLift.handOn): until it settles the slot
  // stands at its share of their room; then it eases from there (_base) to
  // its own width. Taking one element's place it swaps in whole (_swap).
  readonly property var _handIn: (!slot._settled && slot.liftKey !== "" && slot.lift) ? slot.lift.handTo[slot.liftKey] : undefined
  property real _base: 0
  property bool _swap: false
  property bool _handed: false
  readonly property bool _swapping: slot._handIn ? slot._handIn.n === 1 : slot._swap
  onAppearChanged: if (slot.appear >= 1) { slot._base = 0; slot._swap = false; slot._handed = false }

  // A pulse when the dragged copy has gone into this slot (a group).
  property real _pulse: 1
  Connections {
    target: slot.lift
    function onAbsorbed(key) { if (key === slot.liftKey && slot.motion && slot.motion.scale) pulseMotion.restart() }
  }
  SequentialAnimation {
    id: pulseMotion
    NumberAnimation { target: slot; property: "_pulse"; to: 1.12; duration: slot.motion ? slot.motion.fast / 2 : 0; easing.type: Easing.OutQuad }
    NumberAnimation { target: slot; property: "_pulse"; to: 1; duration: slot.motion ? slot.motion.base : 0; easing.type: Easing.OutBack }
  }

  default property alias content: holder.data
  readonly property Item child: holder.children.length > 0 ? holder.children[0] : null

  // Set by hand, not bound: a delegate's required roles (fresh, leaving)
  // arrive after its bindings and onCompleted first ran.
  property real appear: 1
  property bool _snap: false
  // The easing reads the Behavior's target (set before the animation
  // starts); bound to `wanted` it could start with the old one.
  Behavior on appear {
    id: appearMotion
    enabled: !slot._snap && !!slot.motion && slot.motion.base > 0
    NumberAnimation {
      duration: slot.motion ? slot.motion.base : 0
      // The empty room a dropped element leaves (its content hidden) closes
      // on the curve the slots taking its room open on, so the dock's width
      // moves one way.
      easing.type: (appearMotion.targetValue > 0.5 || slot._exiting) ? Easing.OutCubic : Easing.InCubic
    }
  }
  // A write past the Behavior.
  function _start(from) {
    slot._snap = true
    slot.appear = from
    slot._snap = false
  }
  // The model's roles reach a new delegate only after it completes (and
  // without a change signal), so the slot waits one turn, drawn as nothing,
  // and then knows whether it is fresh.
  property bool _settled: false
  // Deferred through a child Timer, not Qt.callLater: a queued callLater
  // still runs after the slot is torn down (a delegate being destroyed as
  // the dock rebuilds a row), and its context is invalid there - the fault
  // logged at this line in the wild ("Property '_start' ... is not a
  // function", during delayed function evaluation). The Timer dies with the
  // slot, so nothing is left queued.
  Timer {
    id: settleLater
    interval: 0
    onTriggered: {
      var h = slot._handIn
      if (h && slot.fresh && slot.wanted) {
        slot._base = slot.lift.handBase(slot.liftKey)
        slot._swap = h.n === 1
        slot._handed = true
        slot._settled = true
        slot.lift.handTaken(slot.liftKey)
        slot._start(0)
        slot.appear = 1
        return
      }
      slot._settled = true
      if (!slot.fresh || slot.landing) slot._start(slot.wanted ? 1 : 0)
      else slot.appear = slot.wanted ? 1 : 0
    }
  }
  Component.onCompleted: {
    slot._start(0)
    settleLater.start()
  }
  // A row that hides or shows itself while the dock starts (its data still
  // arriving) does so at once.
  readonly property real _bornAt: Date.now()
  onWantedChanged: {
    if (!slot._settled) return
    if (Date.now() - slot._bornAt < 1500) slot._start(slot.wanted ? 1 : 0)
    else slot.appear = slot.wanted ? 1 : 0
  }

  // A landing tile is at least what the gap held for it: its label settles
  // a frame after the tile is made.
  readonly property real full: !slot.child ? 0 : slot.landing ? Math.max(slot.child.width, slot.lift.liftWidth) : slot.child.width
  // The slot a drop lands in stands open from its first frame, before its
  // roles (and `appear`) have arrived.
  // A slot handed room eases from that room instead (_base).
  readonly property real _shownAppear: (slot.landing && slot._base <= 0 && !slot._handIn) ? 1 : slot.appear
  readonly property bool _eases: slot._exiting || (!!slot.motion && slot.motion.layout)
  width: (slot._handIn ? (slot._eases ? slot.lift.handBase(slot.liftKey) : slot.full)
    : slot._eases ? slot._base + (slot.full - slot._base) * slot._shownAppear
    : (slot._shownAppear > 0.001 || slot._handed ? slot.full : 0)) - slot._given
  height: slot.child ? slot.child.height : 0
  visible: slot._shownAppear > 0.001 || !!slot._handIn || slot._handed
  // A zoomed element raises itself over its neighbours; in the Row that
  // takes the slot's z.
  z: slot.child ? slot.child.z : 0

  Item {
    id: holder
    width: slot.full
    height: slot.height
    x: Math.round((slot.width - slot.full) / 2)
    opacity: (slot.landing || slot._exiting) ? 0 : slot._swapping ? 1 : slot.appear
    // A leaving element takes no clicks, hovers or drops during its exit.
    enabled: slot.wanted
    scale: ((slot.motion && slot.motion.scale && !slot._swapping) ? 0.6 + 0.4 * slot.appear : 1) * slot._pulse
    transformOrigin: Item.Bottom
  }
}
