// Body for tests/live/interactions.sh (probe.sh's PROBE_BODY hook): the real
// dock, plus an IPC surface that drives the interactive paths the live suites
// never touched before - the context menu, the rename field inside it, the app
// group popup and its menu, and the settings panel - and reports what each one
// rendered with.
//
// Why a driver at all: those paths need a pointer. The dock opens them from its
// tiles' own signals (right-click, click on a group), which a script cannot
// reach, so the steps here call the very functions those signal handlers call
// (`openContext`, `openFolderContext`, `openAppGroup`, `openAppGroupContext`,
// `openSettingsPanel`) with the same arguments, taken from itemGeometry() -
// the item's own centre, exactly where the pointer would be.
//
// Why colours are read here and not only in the pixels: the Qt 6.12 failure
// this guards against is a *value* resolution - a surface that reads its panel
// colour from QtQuick's shadowing singleton gets undefined, the binding throws,
// and it draws with the property's default. So each surface's own `color` is
// compared against the shell's singleton, imported with a qualifier
// (`qs.Commons as C`) because a qualified reference cannot be shadowed; and
// every text the opened subtree draws must carry one of the theme's colours.
// tests/live/interactions.sh separately checks the rendered pixels, so a value
// that resolved but never drew is caught too.
//
// Every step is gated on PROBE_SCREEN, the output the dock must be on: with
// the variable unset, or the dock on any other output, no step opens anything
// and each answers why. That gate is what makes this file safe to run - a body
// that drove these paths on the owner's own screen would not be.

  Od.DockHost { id: host }

  // The output the dock must sit on before anything opens. Set by the suite.
  readonly property string mustBeOn: String(Quickshell.env("PROBE_SCREEN") || "")

  function dock() {
    var list = host.orderedDocks ? host.orderedDocks() : []
    return list.length > 0 ? list[0] : null
  }

  // "" when it is safe to drive the dock, else why it is not.
  function gate(d) {
    if (mustBeOn === "") return "PROBE_SCREEN is not set"
    if (!d) return "no dock"
    if (!d.dockScreen) return "the dock has no screen"
    var name = String(d.dockScreen.name)
    if (name !== mustBeOn) return "the dock is on " + name + ", not " + mustBeOn
    return ""
  }

  // Every colour the surfaces under test draw with, read through the qualified
  // import. Only used for membership: whichever of them a row picked, it must
  // be one of these - an unresolved theme colour reads as undefined and lands
  // on a default (transparent, or black through the QColor conversion) instead.
  readonly property var palette: [C.Color.menu.background, C.Color.menu.text,
    C.Color.menu.border, C.Color.menu.selectedBackground, C.Color.accent, C.Color.urgent]

  // "#aarrggbb" (alpha first when it is there, as QColor.toString writes it) or
  // "#rrggbb"; null for anything else ("transparent", undefined).
  function parts(c) {
    if (c === undefined || c === null) return null
    var s = String(c)
    if (s.charAt(0) !== "#") return null
    s = s.substring(1)
    if (s.length === 8) return { a: parseInt(s.substring(0, 2), 16), r: parseInt(s.substring(2, 4), 16),
      g: parseInt(s.substring(4, 6), 16), b: parseInt(s.substring(6, 8), 16) }
    if (s.length === 6) return { a: 255, r: parseInt(s.substring(0, 2), 16),
      g: parseInt(s.substring(2, 4), 16), b: parseInt(s.substring(4, 6), 16) }
    return null
  }

  function sameRgba(a, b) {
    var x = parts(a), y = parts(b)
    return !!x && !!y && x.r === y.r && x.g === y.g && x.b === y.b && x.a === y.a
  }

  function inPalette(c) {
    var x = parts(c)
    if (!x) return false
    for (var i = 0; i < palette.length; i++) {
      var y = parts(palette[i])
      if (y && y.r === x.r && y.g === x.g && y.b === x.b) return true
    }
    return false
  }

  function findFirst(o, pred, depth) {
    if (!o || depth > 16) return null
    if (pred(o)) return o
    var ch = o.children || []
    for (var i = 0; i < ch.length; i++) {
      var found = findFirst(ch[i], pred, depth + 1)
      if (found) return found
    }
    return null
  }

  // Every text in a subtree and the colour it resolved to. A Text whose colour
  // binding threw keeps its default - black - and black is not one of the
  // theme's colours, so it lands in `foreign`; a tree that drew nothing at all
  // reports no text, which the suite fails on too.
  function textReport(o) {
    var texts = 0, foreign = []
    function walk(item, depth) {
      if (!item || depth > 16) return
      if (item.text !== undefined && item.color !== undefined) {
        texts++
        if (!inPalette(item.color)) foreign.push(String(item.color))
      }
      var ch = item.children || []
      for (var i = 0; i < ch.length; i++) walk(ch[i], depth + 1)
    }
    walk(o, 0)
    return { texts: texts, foreign: foreign }
  }

  // The opened menu (Dock.qml `contextMenu`), its own panel colour against the
  // shell singleton, how many rows it laid out, and what it drew with.
  function menuReport(d) {
    var menu = d.contextMenu
    if (!menu) return { ok: true, menu: false }
    var rows = 0
    function countRows(item, depth) {
      if (!item || depth > 16) return
      if (item.menuRowWidth !== undefined && item.height > 0) rows++
      var ch = item.children || []
      for (var i = 0; i < ch.length; i++) countRows(ch[i], depth + 1)
    }
    countRows(menu, 0)
    var rep = textReport(menu)
    return { ok: true, menu: true, panel: String(menu.color),
      panelMatch: sameRgba(menu.color, C.Color.menu.background),
      rows: rows, texts: rep.texts, foreign: rep.foreign }
  }

  function itemOf(d, kind) {
    var items = JSON.parse(d.itemGeometry())
    for (var i = 0; i < items.length; i++)
      if (items[i].kind === kind) return items[i]
    return null
  }

  function centreOf(it) { return { x: it.x + it.w / 2, y: it.y + it.h / 2 } }

  function groupData(d, id) {
    var groups = d.appGroups || []
    for (var i = 0; i < groups.length; i++)
      if (groups[i] && groups[i].id === id) return groups[i]
    return null
  }

  function folderName(d, path) {
    var pins = d.pinnedFolders || []
    for (var i = 0; i < pins.length; i++)
      if (pins[i] && pins[i].path === path) return String(pins[i].name || "")
    return ""
  }

  // Every app id the dock's own list knows, de-duplicated: what a precondition
  // this fixture has to supply can be chosen from. The list is the dock's, so
  // an id taken from it resolves on whatever host is running the suite.
  function appIds(d) {
    var rows = d.appRows || []
    var out = [], seen = {}
    for (var i = 0; i < rows.length; i++) {
      var e = (rows[i] && rows[i].entry) ? rows[i].entry : rows[i]
      var id = String((e && e.id) || "")
      if (id === "" || seen[id]) continue
      seen[id] = true
      out.push(id)
    }
    return out
  }

  function firstResolvable(d) {
    var ids = appIds(d)
    for (var i = 0; i < ids.length; i++) if (d.resolveDesktopEntry(ids[i])) return ids[i]
    return ""
  }

  IpcHandler {
    id: ipc
    target: "omadock-test"

    // What the fixture supplied for this run, so repeated `prepare` calls are
    // idempotent (togglePin flips a pin, and a second call would unpin it).
    property string probeAppId: ""
    // The group the suite's config copy adds when the desk has none.
    property string probeGroupId: "omadock_probe_group"

    // One step per call, so the suite can capture a frame before and after a
    // surface opens. Every step answers JSON; `ok` is false when the gate
    // refused, and the suite counts that as its own failure.
    function run(step: string, arg: string): string {
      var d = dock()
      var why = gate(d)
      if (why !== "") return JSON.stringify({ ok: false, why: why })

      if (step === "probe")
        return JSON.stringify({ ok: true, screen: String(d.dockScreen.name),
          visible: d.dockVisible, items: JSON.parse(d.itemGeometry()).length })

      if (step === "reveal") {
        d.dockVisible = true
        return JSON.stringify({ ok: true, visible: d.dockVisible })
      }

      // The preconditions the suite owns, supplied only where the desk cannot:
      // an app tile comes from a running window (the compositor's, not this
      // fixture's) or from a pin, and a probe HOME starts with neither, while
      // a group tile needs at least one app in it for the popup to draw tiles.
      // Nothing is added while an app tile already exists - the real thing is
      // preferred, the same way the config copy prefers a real pinned folder.
      // Idempotent: a pin is chosen once and remembered, because togglePin
      // flips.
      if (step === "prepare") {
        var hadApp = !!itemOf(d, "app")
        if (!hadApp && ipc.probeAppId === "") ipc.probeAppId = firstResolvable(d)
        if (!hadApp && ipc.probeAppId !== "") d.togglePin(ipc.probeAppId)
        var filled = false
        var groups = d.appGroups || []
        for (var gi = 0; gi < groups.length; gi++) {
          if (!groups[gi] || groups[gi].id !== ipc.probeGroupId) continue
          if (groups[gi].apps && groups[gi].apps.length > 0) break
          var pick = ipc.probeAppId !== "" ? ipc.probeAppId : firstResolvable(d)
          if (pick === "") break
          ipc.probeAppId = pick
          d.addAppToGroup(ipc.probeGroupId, pick)
          filled = true
          break
        }
        return JSON.stringify({ ok: true, hadApp: hadApp, app: ipc.probeAppId,
          pinned: !hadApp && ipc.probeAppId !== "", filled: filled,
          group: !!itemOf(d, "group"),
          why: hadApp ? "" : (ipc.probeAppId === "" ? "the dock lists no installed app to pin" : "") })
      }

      if (step === "palette")
        return JSON.stringify({ ok: true, menuBg: String(C.Color.menu.background),
          menuText: String(C.Color.menu.text), accent: String(C.Color.accent) })

      // An app tile's right click.
      if (step === "context-app") {
        var it = itemOf(d, "app")
        if (!it) return JSON.stringify({ ok: false, why: "no app item" })
        var c = centreOf(it)
        d.openContext(it.id, c.x, c.y)
        var rep = menuReport(d)
        rep.id = it.id
        rep.appId = d.contextAppId
        return JSON.stringify(rep)
      }

      // A group tile's right click - the menu PR #56 gave a group, opened from
      // the group menu's own rows.
      if (step === "context-group") {
        var gi = itemOf(d, "group")
        if (!gi) return JSON.stringify({ ok: false, why: "no group item" })
        var gc = centreOf(gi)
        d.openAppGroupContext(groupData(d, gi.id), gc.x, gc.y)
        var greport = menuReport(d)
        greport.id = gi.id
        greport.appId = d.contextAppId
        // Which group the menu actually took: without it the menu's group
        // section draws its placeholder rows and the surface assertions below
        // would still hold, so the step would not be about this tile at all.
        greport.groupData = (d.contextAppGroupData && d.contextAppGroupData.id)
          ? String(d.contextAppGroupData.id) : ""
        return JSON.stringify(greport)
      }

      // A pinned folder's right click, then its "Rename…" row turned into the
      // name field, then Escape. The suite md5s the config copy across this:
      // a cancelled edit must not commit anything.
      if (step === "folder-rename") {
        var f = itemOf(d, "folder")
        if (!f) return JSON.stringify({ ok: false, why: "no folder item" })
        var fc = centreOf(f)
        d.openFolderContext(f.id, folderName(d, f.id), fc.x, fc.y, "")
        var menu = d.contextMenu
        var row = menu ? findFirst(menu, function(o) { return typeof o.startEdit === "function" }, 0) : null
        if (!row) return JSON.stringify({ ok: false, why: "no rename row in the folder menu" })
        row.startEdit()
        var input = findFirst(row, function(o) { return o.maximumLength !== undefined && o.color !== undefined && o.text !== undefined }, 0)
        // The field's border sits on the input's own container.
        var field = input && input.parent ? input.parent : null
        var mrep = menuReport(d)
        var report = { ok: true, path: f.id, menu: mrep.menu, panelMatch: mrep.panelMatch,
          texts: mrep.texts, foreign: mrep.foreign,
          editing: row.editing === true, holdsKeyboard: d.contextRenaming === true,
          input: input ? String(input.color) : "",
          inputMatch: input ? sameRgba(input.color, C.Color.menu.text) : false,
          border: field ? String(field.border.color) : "",
          borderMatch: field ? sameRgba(field.border.color, C.Color.accent) : false }
        row.finish(false)
        report.cancelled = row.editing === false
        report.releasedKeyboard = d.contextRenaming === false
        return JSON.stringify(report)
      }

      // A group tile's left click: its popup, the surface the Qt 6.12 shading
      // left with unreadable rows.
      if (step === "group-popup") {
        var gt = itemOf(d, "group")
        if (!gt) return JSON.stringify({ ok: false, why: "no group item" })
        var data = groupData(d, gt.id)
        if (!data) return JSON.stringify({ ok: false, why: "no data for group " + gt.id })
        var gtc = centreOf(gt)
        d.openAppGroup(data, gtc.x, gtc.y)
        return JSON.stringify({ ok: true, id: gt.id, active: d.activeAppGroupId,
          apps: data.apps ? data.apps.length : 0, panel: String(d.popupSurface().surface) })
      }

      if (step === "settings-open") {
        d.openSettingsPanel()
        return JSON.stringify({ ok: true, open: d.settingsPanelOpen })
      }

      // Switching a page re-evaluates the visibility-driven bindings of the
      // page components (the panel instantiates every page, only one shows).
      if (step === "settings-page") {
        if (!d.settingsPanelOpen) return JSON.stringify({ ok: false, why: "the panel is not open" })
        d.settingsPanelPage = String(arg)
        return JSON.stringify({ ok: true, page: d.settingsPanelPage })
      }

      if (step === "close") {
        d.closeContext()
        d.closeAppGroup()
        d.closeSettingsPanel()
        return JSON.stringify({ ok: true, context: d.contextAppId, group: d.activeAppGroupId,
          settings: d.settingsPanelOpen })
      }

      return JSON.stringify({ ok: false, why: "unknown step " + step })
    }
  }
