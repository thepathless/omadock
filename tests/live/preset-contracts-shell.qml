// probe.sh body: no desktop input, compositor dispatches, or window actions.
  Od.DockHost { id: host }

  function dock() {
    var docks = host.orderedDocks()
    return docks.length > 0 ? docks[0] : null
  }

  function allowed(d) {
    var screen = Quickshell.env("PROBE_SCREEN")
    return d && screen !== "" && d.dockScreen && String(d.dockScreen.name) === screen
  }

  IpcHandler {
    target: "omadock-contracts"

    function prepare(): string {
      var d = dock()
      if (!allowed(d)) return "wrong screen"
      // Own a pin only if the inherited state has no app to measure.
      if (d.pinnedSection.length + d.groupSlots + d.visibleRunningCount === 0) {
        var rows = d.appRows || []
        if (rows.length === 0) return "no installed app"
        d.togglePin(rows[0].appId)
      }
      d.showTooltips = false
      d.advancedTooltips = false
      d.saveConfig()
      return "ok"
    }

    function adjust(key: string, value: string): string {
      var d = dock()
      if (!allowed(d)) return "wrong screen"
      // Change the real properties behind settings, without adding public IPC.
      if (["layout", "alignment", "minimizeMode"].indexOf(key) >= 0) d[key] = value
      else if (["showAppsButton", "autohide", "intelligentAutohide", "showMinimizedTiles"].indexOf(key) >= 0) d[key] = value === "true"
      else return "unknown key"
      d.saveConfig()
      return "ok"
    }

    function read(): string {
      var d = dock()
      if (!allowed(d)) return JSON.stringify({ error: "wrong screen" })
      var w = d.dockCardComp
      var out = { active: d.activePresetId, layout: d.layout, alignment: d.alignment,
        autohide: d.autohide, intelligentAutohide: d.intelligentAutohide,
        showMinimizedTiles: d.showMinimizedTiles, minimizeMode: d.minimizeMode,
        showAppsButton: d.showAppsButton, showTooltips: d.showTooltips,
        advancedTooltips: d.advancedTooltips, taskbar: d.placement.taskbar }
      if (w && d.placement.taskbar) {
        var slots = w.liveSlots(w.pinnedRowRepeater).concat(w.liveSlots(w.runningRepeater))
        var start = null
        for (var i = 0; i < w.row.children.length; i++) {
          var c = w.row.children[i]
          if (c.child && c.child.glyph !== undefined && c.shown) start = c
        }
        if (slots.length > 0) {
          var first = slots[0], last = slots[slots.length - 1]
          var left = (start || first).mapToItem(w.dockCard, 0, 0).x
          var right = last.mapToItem(w.dockCard, last.width, 0).x
          out.geometry = { startShown: !!start, firstApp: first.mapToItem(w.dockCard, 0, 0).x,
            startRight: start ? start.mapToItem(w.dockCard, start.width, 0).x : 0,
            groupCenter: (left + right) / 2, panelCenter: w.dockCard.width / 2,
            spacing: w.row.spacing, rightEdge: w.rightRowRef.mapToItem(w.dockCard, w.rightRowRef.width, 0).x,
            panelRight: w.dockCard.width - w.dockCard.contentRightInset,
            rightGroupStart: w.rightRowRef.mapToItem(w.dockCard, 0, 0).x, appsRight: right }
        }
      }
      return JSON.stringify(out)
    }
  }
