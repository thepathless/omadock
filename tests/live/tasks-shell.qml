// Body for tests/live/tasks.sh (probe.sh's PROBE_BODY hook): the real dock,
// plus a reader that reports what the task HUD actually resolved to.
//
// Two things are read out of the running dock, never off the source text:
//
//  * every tile - its `taskInfo`/`badgeView` bindings and the BadgeMark that
//    draws them (steps `items`), which is what the IPC answer alone cannot
//    prove.
//  * the hover chip inside the tooltip (steps `chip-open` / `chip-read`). The
//    chip lives in a LazyLoader gated on the tooltip's own life flag, and a
//    real hover cannot be produced on this host without warping the pointer,
//    which would steal the owner's focus (`input:follow_mouse = full`). So
//    `chip-open` raises the tooltip life directly and the chip's instantiated
//    subtree is then read back - the content and colours are the surface under
//    test; the hover -> dwell -> tipShown chain is the dock's pre-existing
//    tooltip machinery and is not what this file verifies.
//
// Detection is by the properties each component uniquely owns - a BadgeMark
// (`badgeColor` + `shownGlyph`), a DockItem (`appId` + `windowList` +
// `magnifyScale`), a TooltipLife (`want` + `alive` + `dockRoot`) - so a rename
// or a re-layout cannot silently disable the read.

  Od.DockHost { id: host }

  function dock() {
    var list = host.orderedDocks ? host.orderedDocks() : []
    return list.length > 0 ? list[0] : null
  }

  function isItem(o) {
    return o.appId !== undefined && o.windowList !== undefined && o.magnifyScale !== undefined
  }

  function eachItem(o, depth, fn) {
    if (!o || depth > 20) return
    fn(o)
    var ch = o.children || []
    for (var i = 0; i < ch.length; i++) eachItem(ch[i], depth + 1, fn)
  }

  function findFirst(o, depth, pred) {
    if (!o || depth > 20) return null
    if (pred(o)) return o
    var ch = o.children || []
    for (var i = 0; i < ch.length; i++) {
      var hit = findFirst(ch[i], depth + 1, pred)
      if (hit) return hit
    }
    return null
  }

  function itemFor(appId) {
    var found = null
    eachItem(dock() ? dock().contentItemRef : null, 0, function(o) {
      if (!found && isItem(o) && String(o.appId) === appId) found = o
    })
    return found
  }

  // The tooltip's life object inside one tile: the only thing in the tree that
  // declares both `want` and `alive`, and points at the dock.
  function lifeOf(item) {
    return item ? findFirst(item, 0, function(o) {
      return o.want !== undefined && o.alive !== undefined && o.dockRoot !== undefined
    }) : null
  }

  function itemReport(o) {
    return {
      appId: String(o.appId),
      notifications: Number(o.notificationCount) || 0,
      hasTask: o.taskInfo !== null && o.taskInfo !== undefined,
      taskStatus: o.taskInfo ? String(o.taskInfo.status) : "",
      taskTitle: o.taskInfo ? String(o.taskInfo.title) : "",
      taskExit: o.taskInfo ? Number(o.taskInfo.exitCode) : -1,
      taskDuration: o.taskInfo ? Number(o.taskInfo.duration) : -1,
      badgeMode: o.badgeView ? String(o.badgeView.mode) : "",
      badgeCount: o.badgeView ? Number(o.badgeView.count) : -1,
      badgeGlyph: o.badgeView ? String(o.badgeView.glyph) : "",
      badgeColor: o.badgeView ? String(o.badgeView.color) : ""
    }
  }

  function badgeReport(o) {
    // Named inkText, not ink: a JS object literal key spelled the same as its
    // local (`ink: ink`) is indistinguishable from a self-binding `x: x` to
    // tests/unit/test_qml_self_binding.py, whose scan cannot tell a JS object
    // literal from a QML object declaration.
    var inkText = ""
    var ch0 = o.children || []
    for (var k = 0; k < ch0.length; k++) {
      if (ch0[k] && ch0[k].text !== undefined) inkText = String(ch0[k].text)
    }
    var level = Number(o.level)
    var anchored = o.anchorRef !== null && o.anchorRef !== undefined
    return {
      glyph: String(o.glyph),
      shownGlyph: String(o.shownGlyph),
      shownCount: Number(o.shownCount),
      badgeColor: String(o.badgeColor),
      resolved: String(o.color),
      // The badge's OWN visibility rule. `visible` itself cascades from the
      // hidden probe dock (see tasks.sh's header), so the rule is reported as
      // the boolean it evaluates to here.
      expr: String(level > 0.01 && anchored),
      visible: String(o.visible),
      level: level,
      opacity: Number(o.opacity),
      hasAnchor: anchored,
      ink: inkText
    }
  }

  // The surface the hover chip lives in. It is not part of the tile's item
  // tree: the tile's LazyLoader builds a TooltipWindow (its own popup surface,
  // a separate window) and hands it a BorderSurface as `body`, and only
  // `LazyLoader.item` reaches it. Two traps make the walk below look at `data`
  // and not `children`: a LazyLoader's prototype is Quickshell's `Reloadable`,
  // a plain QObject, so it never appears in `children` at all, and the window
  // it builds is not parented into the tile either. `Item.data` holds the
  // visual and non-visual children alike, which is where the loader is.
  function tipSurface(item) {
    var kids = item && item.data ? item.data : []
    for (var i = 0; i < kids.length; i++) {
      var c = kids[i]
      var gk = c.data || []
      for (var j = -1; j < gk.length; j++) {
        var cand = j < 0 ? c : gk[j]
        try {
          if (cand.item && cand.item.body) return cand.item.body
        } catch (e) {}
      }
    }
    return null
  }

  IpcHandler {
    target: "omadock-test"

    function read(step: string, arg: string): string {
      var d = dock()
      if (!d) return JSON.stringify({ ok: false, why: "no dock" })

      if (step === "screen") {
        var name = d.dockScreen ? String(d.dockScreen.name) : ""
        return JSON.stringify({ ok: true, screen: name, visible: d.dockVisible === true,
          docks: host.orderedDocks().length })
      }

      if (step === "reveal") {
        d.dockVisible = true
        return JSON.stringify({ ok: true, visible: d.dockVisible === true })
      }

      if (step === "items") {
        var out = { items: [], badges: [] }
        eachItem(d.contentItemRef, 0, function(o) {
          if (isItem(o)) out.items.push(itemReport(o))
          if (o.badgeColor !== undefined && o.shownGlyph !== undefined) out.badges.push(badgeReport(o))
        })
        return JSON.stringify({ ok: true, count: out.items.length, items: out.items, badges: out.badges })
      }

      // The fixture's app tile: a pin from the dock's own list, picked only
      // when the desk has no app tile of its own (every running app can be in
      // a group). `togglePin` flips, so the caller pins once.
      if (step === "pin") {
        var grouped = {}
        var groups = d.appGroups || []
        for (var g = 0; g < groups.length; g++) {
          var members = groups[g].apps || []
          for (var m = 0; m < members.length; m++) grouped[String(members[m])] = true
        }
        var rows = d.appRows || []
        for (var r = 0; r < rows.length; r++) {
          var e = (rows[r] && rows[r].entry) ? rows[r].entry : rows[r]
          var id = String((e && e.id) || "")
          if (id === "" || grouped[id] || !d.resolveDesktopEntry(id)) continue
          d.togglePin(id)
          return JSON.stringify({ ok: true, appId: id })
        }
        return JSON.stringify({ ok: false, why: "no ungrouped installed app to pin" })
      }

      // Raise the tooltip's own life flag on one tile, so the LazyLoader builds
      // the surface the chip lives in. No pointer is used (see the header).
      if (step === "chip-open") {
        var item = itemFor(String(arg))
        if (!item) return JSON.stringify({ ok: false, why: "no tile for " + arg })
        if (!item.taskInfo) return JSON.stringify({ ok: false, why: "the tile holds no task" })
        var life = lifeOf(item)
        if (!life) return JSON.stringify({ ok: false, why: "no tooltip life in the tile" })
        life.alive = true
        life.level = 1
        return JSON.stringify({ ok: true, tile: String(item.appId), alive: life.alive === true,
          level: Number(life.level) })
      }

      // What the instantiated chip resolves to: the text it drew, the colour it
      // drew with, and the colours of the small marks beside it - read out of
      // the tooltip surface the tile's own LazyLoader built (tipSurface), not
      // out of the dock's own item tree, which the chip is not part of.
      if (step === "chip-read") {
        var needle = String(arg)
        var texts = []
        var marks = []
        var surfaces = 0
        eachItem(d.contentItemRef, 0, function(o) {
          if (!isItem(o)) return
          var surf = tipSurface(o)
          if (!surf) return
          surfaces++
          var stack = [surf]
          while (stack.length > 0) {
            var s = stack.pop()
            if (s.text !== undefined && s.color !== undefined)
              texts.push({ text: String(s.text), color: String(s.color),
                w: Number(s.width), h: Number(s.height), iw: Number(s.implicitWidth) })
            if (s.text === undefined && s.color !== undefined && s.radius !== undefined)
              marks.push({ color: String(s.color), w: Number(s.width), h: Number(s.height) })
            var ch = s.children || []
            for (var i = 0; i < ch.length; i++) stack.push(ch[i])
          }
        })
        var hits = []
        for (var j = 0; j < texts.length; j++)
          if (texts[j].text.indexOf(needle) >= 0) hits.push(texts[j])
        return JSON.stringify({ ok: true, surfaces: surfaces, texts: texts.length, hits: hits, marks: marks })
      }

      // The clear the dock's focus handling performs. Dock.qml's focus-driven
      // and click-driven paths both call root.clearUrgentApp(appId, address)
      // (onActiveIdChanged for a focus change, activateApp for a click); this
      // drives that function with the shape of arguments the focus handler
      // passes. What it does NOT re-verify is that Hyprland's focus event
      // reaches the dock's pre-existing activeId tracking - that machinery is
      // untouched by this feature.
      if (step === "focus-clear") {
        var ft = itemFor(String(arg))
        if (!ft) return JSON.stringify({ ok: false, why: "no tile for " + arg })
        if (!ft.taskInfo) return JSON.stringify({ ok: false, why: "the tile holds no task" })
        d.clearUrgentApp(String(ft.appId), "")
        return JSON.stringify({ ok: true, appId: String(ft.appId) })
      }

      if (step === "chip-close") {
        var all = []
        eachItem(d.contentItemRef, 0, function(o) {
          if (o.want !== undefined && o.alive !== undefined && o.dockRoot !== undefined) all.push(o)
        })
        for (var j = 0; j < all.length; j++) { all[j].level = 0; all[j].alive = false }
        return JSON.stringify({ ok: true, closed: all.length })
      }

      return JSON.stringify({ ok: false, why: "unknown step " + step })
    }
  }
