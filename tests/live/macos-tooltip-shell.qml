// Body for tests/live/macos-tooltip.sh (probe.sh's PROBE_BODY hook): the real
// dock, plus a reader for the macOS hover callout and the icon it belongs to.
//
// `prepare` gives the probe the one thing a fresh HOME cannot: an app tile. A
// pin is chosen from the dock's own app list (so it resolves on whatever host
// runs the suite) and toggled through the dock's own `togglePin`, exactly as
// a drop would - the tile that results is a real DockItem, built by the
// delegate, not a copy.
//
// `read(kind)` reports one tile of the row as the dock has laid it out - an
// app (`app`), an app group (`group`) or a pinned folder (`folder`) - its
// slot, the box its label is anchored to and the drawn (possibly magnified)
// artwork inside it, and the callout its own DockLabel built. Everything is
// in dock-window coordinates, so the suite can turn it into screen
// coordinates with the headless output's origin. The callout is found by
// walking the label's own `data` for the LazyLoader whose item is a
// TooltipWindow: that is the window DockLabel builds, not a copy.

  Od.DockHost { id: host }

  function dock() {
    var list = host.orderedDocks ? host.orderedDocks() : []
    return list.length > 0 ? list[0] : null
  }

  // Visual children, QObject data (a LazyLoader is not an Item) and a
  // Loader's loaded item: RowSlot builds each tile through a Loader, so the
  // item tree alone does not reach it.
  function kidsOf(o) {
    var out = []
    var ch = o.children || []
    for (var i = 0; i < ch.length; i++) out.push(ch[i])
    var data = o.data || []
    for (var j = 0; j < data.length; j++) if (out.indexOf(data[j]) < 0) out.push(data[j])
    try { if (o.item && out.indexOf(o.item) < 0) out.push(o.item) } catch (e) {}
    return out
  }

  function findAll(o, depth, pred, out) {
    if (!o || depth > 30) return out
    if (pred(o)) out.push(o)
    var kids = kidsOf(o)
    for (var i = 0; i < kids.length; i++) findAll(kids[i], depth + 1, pred, out)
    return out
  }

  // A DockItem: the app tile (groups and folders carry magnifyScale too, so
  // the window list is what tells an app apart).
  function isTile(o) {
    return o.appId !== undefined && o.windowList !== undefined && o.magnifyScale !== undefined
  }

  function isGroupTile(o) {
    return o.groupData !== undefined && o.magnifyScale !== undefined && o.appId === undefined
  }

  function isFolderTile(o) {
    return o.folderPath !== undefined && o.magnifyScale !== undefined && o.appId === undefined
  }

  function isLabel(o) {
    return o.fullText !== undefined && o.style !== undefined && o.chipBox !== undefined
  }

  function isChip(o) {
    return o.variant !== undefined && o.padX !== undefined && o.boxHeight !== undefined
      && o.text !== undefined
  }

  // The window DockLabel's LazyLoader built (a TooltipWindow), if it is alive.
  function chipWindowOf(label) {
    var kids = label.data || []
    for (var i = 0; i < kids.length; i++) {
      var loader = kids[i]
      if (!loader || loader.item === undefined) continue
      try { if (loader.item.body) return loader.item } catch (e) {}
    }
    return null
  }

  function rect(o, root) {
    var p = o.mapToItem(root.contentItemRef, 0, 0)
    return { x: Number(p.x), y: Number(p.y), w: Number(o.width), h: Number(o.height) }
  }

  // The fixture's own tile when it has one (a pin cannot vanish under the
  // pointer the way a running app can), else the first app tile on the row.
  function appTile(d) {
    var tiles = findAll(d.contentItemRef, 0, isTile, [])
    var first = null
    for (var i = 0; i < tiles.length; i++) {
      if (!tiles[i].visible || !tiles[i].appId || tiles[i].magnifyScale <= 0) continue
      if (ipc.probeAppId !== "" && String(tiles[i].appId) === ipc.probeAppId) return tiles[i]
      if (!first) first = tiles[i]
    }
    return first
  }

  function tileOfKind(d, kind) {
    if (kind === "group") return findAll(d.contentItemRef, 0, isGroupTile, [])[0] || null
    if (kind === "folder") return findAll(d.contentItemRef, 0, isFolderTile, [])[0] || null
    return appTile(d)
  }

  function firstApp(d) {
    var rows = d.appRows || []
    for (var i = 0; i < rows.length; i++) {
      var e = (rows[i] && rows[i].entry) ? rows[i].entry : rows[i]
      var id = String((e && e.id) || "")
      if (id !== "" && d.resolveDesktopEntry(id)) return id
    }
    return ""
  }

  function tileReport(d, tile, kind) {
    var label = findAll(tile, 0, isLabel, [])[0] || null
    var tileRect = rect(tile, d)
    var scale = Number(label && label.iconScale !== undefined ? label.iconScale : tile.magnifyScale)
    var out = {
      kind: kind,
      id: kind === "group" ? String(tile.groupId || "") : (kind === "folder" ? String(tile.folderPath || "") : String(tile.appId || "")),
      scale: scale,
      rect: tileRect,
      icon: null,
      label: null
    }
    // The label anchors its callout to `iconBox` (the app tile's icon area, a
    // group's or a folder's icon slot) and knows the artwork's scale. The
    // drawn box follows from the same two values the label uses: the artwork
    // is `baseIconArt * scale` square, centred in the box and lifted off the
    // box's bottom by `iconArtBottom`.
    if (label && label.iconBox) {
      var box = rect(label.iconBox, d)
      var art = Number(d.baseIconArt) * scale
      out.iconBox = box
      out.icon = { x: box.x + (box.w - art) / 2, y: box.y + box.h - Number(d.iconArtBottom) - art,
                   w: art, h: art }
    }
    out.name = label ? String(label.fullText || "") : ""
    if (label) out.label = {
      text: String(label.drawnText || ""),
      full: String(label.fullText || ""),
      chip: String(label.style ? label.style.chip : ""),
      fontPx: Number(label.style ? label.style.fontPx : 0),
      weight: Number(label.style ? label.style.weight : 0),
      family: String(label.style ? label.style.family : ""),
      chipBox: Number(label.chipBox),
      gap: Number(label.macGap),
      clear: Number(label.chipClear),
      hoverDelay: Number(label.hoverDelay),
      baseDelay: Number(label.baseDelay),
      progress: Number(label.progress)
    }
    var win = label ? chipWindowOf(label) : null
    var body = win ? win.body : null
    if (win && body) {
      var surfaceLeft = Number(win.surfaceCenterX) - Math.round(Number(win.implicitWidth) / 2)
      var surfaceTop = Number(win.anchor.rect.y) - Number(win.implicitHeight)
      var chip = findAll(body, 0, isChip, [])[0] || null
      out.chip = {
        win: { x: surfaceLeft, y: surfaceTop, w: Number(win.implicitWidth), h: Number(win.implicitHeight),
               anchorY: Number(win.anchor.rect.y), centerX: Number(win.surfaceCenterX),
               targetCenterX: Number(win.targetCenterX), gap: Number(win.gap) },
        body: { x: Number(body.x), y: Number(body.y), w: Number(body.width), h: Number(body.height) },
        screen: { x: surfaceLeft + Number(body.x), y: surfaceTop + Number(body.y),
                  w: Number(body.width), h: Number(body.height) },
        design: chip ? {
          variant: String(chip.variant),
          fill: String(chip.fill),
          ink: String(chip.ink),
          radius: Number(chip.radius),
          width: Number(chip.width),
          height: Number(chip.height),
          padX: Number(chip.padX),
          padY: Number(chip.padY),
          text: String(chip.text),
          fontPx: Number(chip.fontPx),
          weight: Number(chip.weight),
          family: String(chip.family)
        } : null
      }
    }
    return out
  }

  IpcHandler {
    id: ipc
    target: "omadock-test"

    // Chosen once: togglePin flips, so a second call would unpin it.
    property string probeAppId: ""

    function prepare(): string {
      var d = dock()
      if (!d) return JSON.stringify({ ok: false, why: "no dock" })
      if (ipc.probeAppId === "") ipc.probeAppId = firstApp(d)
      var pinned = d.pinnedIds || []
      var fresh = ipc.probeAppId !== "" && pinned.indexOf(ipc.probeAppId) < 0
      if (fresh) d.togglePin(ipc.probeAppId)
      return JSON.stringify({ ok: true, app: ipc.probeAppId, pinned: fresh,
        had: appTile(d) !== null })
    }

    // Which kinds of tile this desk has: the suite only drives the ones that
    // are there (a desk with no group has no group tile to hover).
    function kinds(): string {
      var d = dock()
      if (!d) return JSON.stringify({ ok: false, why: "no dock" })
      return JSON.stringify({ ok: true, app: appTile(d) !== null,
        group: tileOfKind(d, "group") !== null, folder: tileOfKind(d, "folder") !== null })
    }

    function read(kind: string): string {
      var d = dock()
      if (!d) return JSON.stringify({ ok: false, why: "no dock" })
      if (kind === "") kind = "app"
      var out = {
        ok: true,
        kind: kind,
        preset: String(d.activePresetId || ""),
        chipKey: String(d.labelChip || ""),
        tooltipDelay: Number(d.tooltipDelay),
        dockVisible: d.dockVisible === true,
        screen: { w: Number(d.dockScreen ? d.dockScreen.width : 0),
                  h: Number(d.dockScreen ? d.dockScreen.height : 0) },
        window: { w: Number(d.dockWindowRef ? d.dockWindowRef.width : 0),
                  h: Number(d.dockWindowRef ? d.dockWindowRef.height : 0) },
        // The card's own input state, so a failed hover names the surface
        // rather than the pointer warp.
        hover: { card: !!(d.cardHover && d.cardHover.hovered), x: Number(d.pointerX) },
        card: d.dockCard ? rect(d.dockCard, d) : null
      }
      var tile = tileOfKind(d, kind)
      out.tile = tile ? tileReport(d, tile, kind) : null
      return JSON.stringify(out)
    }
  }
