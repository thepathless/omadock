// Body for tests/live/apps-menu.sh (probe.sh's PROBE_BODY hook): the real
// dock, plus a reader that drives and reports the apps button's launcher.
//
// `press` calls the exact function the button's own click handler calls
// (sharedState.appGrid.openLauncher), so the suite proves the button's path
// without a pointer on the owner's screen. `read` reports the window and the
// panel as the dock resolves them: the surface's place over the button, the
// panel's box inside it, the gap above the card and the app rows.
  Od.DockHost { id: host }

  function dock() {
    var list = host.orderedDocks ? host.orderedDocks() : []
    return list.length > 0 ? list[0] : null
  }

  IpcHandler {
    target: "omadock-test"

    // The apps button's own press path (DockCard.qml's onPressed).
    function press(): string {
      var d = dock()
      if (!d || !d.sharedState) return JSON.stringify({ ok: false, why: "no dock" })
      d.sharedState.appGrid.openLauncher()
      return JSON.stringify({ ok: true, open: d.appsMenuHost.open === true })
    }

    function closeMenu(): string {
      var d = dock()
      if (!d) return JSON.stringify({ ok: false, why: "no dock" })
      d.appsMenuHost.close()
      return JSON.stringify({ ok: true, open: d.appsMenuHost.open === true })
    }

    // What the launcher resolves to, read out of the running dock: the panel
    // (StartMenu), its window (DockPopupWindow) and the button it anchors to.
    function read(): string {
      var d = dock()
      if (!d) return JSON.stringify({ ok: false, why: "no dock" })
      var h = d.appsMenuHost
      var win = h ? h.menuWindow : null
      var body = h ? h.menu : null
      var card = d.dockCardComp ? d.dockCardComp.dockCard : null
      var button = h ? h.button : null
      var out = {
        ok: true,
        open: h ? h.open === true : false,
        mode: String(d.sharedState ? d.sharedState.appGrid.mode : ""),
        dockVisible: d.dockVisible === true,
        hasWindow: win !== null && win !== undefined,
        hasBody: body !== null && body !== undefined,
        apps: body ? body.apps.length : -1,
        panelVisible: body ? body.visible === true : false,
        anchorX: h ? Number(h.anchorX) : -1,
        screenHeight: d.dockScreen ? Number(d.dockScreen.height) : -1,
        windowHeight: d.dockWindowRef ? Number(d.dockWindowRef.height) : -1,
        windowWidth: d.dockWindowRef ? Number(d.dockWindowRef.width) : -1
      }
      if (win) {
        var surfaceLeft = Number(win.surfaceCenterX) - Math.round(Number(win.implicitWidth) / 2)
        var surfaceTop = Number(win.anchor.rect.y) - Number(win.implicitHeight)
        out.win = { x: surfaceLeft, y: surfaceTop, w: Number(win.implicitWidth), h: Number(win.implicitHeight),
                    anchorY: Number(win.anchor.rect.y), centerX: Number(win.surfaceCenterX),
                    gap: Number(win.gap), grab: win.grabActive === true, level: Number(win.level) }
        if (body) {
          out.body = { x: Number(body.x), y: Number(body.y), w: Number(body.width), h: Number(body.height) }
          out.bodyScreen = { x: surfaceLeft + out.body.x, y: surfaceTop + out.body.y, w: out.body.w, h: out.body.h }
        }
      }
      if (button) {
        out.buttonVisible = button.visible === true
        out.buttonCentreX = Number(button.mapToItem(d.contentItemRef, button.width / 2, 0).x)
      }
      if (card && d.contentItemRef) out.cardTop = Number(d.contentItemRef.mapFromItem(card, 0, 0).y)
      if (out.bodyScreen) {
        out.bodyBottom = out.bodyScreen.y + out.bodyScreen.h
        if (out.cardTop !== undefined) out.gap = out.cardTop - out.bodyBottom
        out.dx = out.bodyScreen.x + out.bodyScreen.w / 2 - Number(out.buttonCentreX || 0)
      }
      return JSON.stringify(out)
    }

    // The panel's rows, in the order it draws them. Two desktop entries can
    // share a display name (Foot and footclient, two Chrome profiles), so the
    // id is what identifies a row.
    function names(): string {
      var d = dock()
      var body = d && d.appsMenuHost ? d.appsMenuHost.menu : null
      if (!body) return "[]"
      return JSON.stringify(body.apps.map(function(e) {
        return { id: String(e.id), name: String(e.name || e.id) }
      }))
    }
  }
