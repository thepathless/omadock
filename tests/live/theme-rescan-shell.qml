  Od.DockHost { id: host }

  IpcHandler {
    target: "theme-rescan-test"
    function state(): string {
      var docks = host.orderedDocks()
      var d = docks.length ? docks[0] : null
      if (!d) return JSON.stringify({ error: "no dock" })
      return JSON.stringify({
        current: String(d.iconThemeRef.iconTheme),
        ids: d.iconThemeRef.themes.map(function(t) { return t.id }),
        themeError: String(d.iconThemeRef.themeError),
        pending: d.iconThemeRef.themeRescanPending,
        installing: d.iconThemeRef.themeInstalling
      })
    }
    function refresh(): string {
      var docks = host.orderedDocks()
      var d = docks.length ? docks[0] : null
      if (!d) return JSON.stringify({ error: "no dock" })
      d.iconThemeRef.refreshThemes()
      return JSON.stringify({ ok: true, pending: d.iconThemeRef.themeRescanPending })
    }
    function applyTheme(id: string): string {
      var docks = host.orderedDocks()
      var d = docks.length ? docks[0] : null
      if (!d) return JSON.stringify({ error: "no dock" })
      d.iconThemeRef.setIconTheme(id)
      return JSON.stringify({ ok: true })
    }
    function install(): string {
      var docks = host.orderedDocks()
      var d = docks.length ? docks[0] : null
      if (!d) return JSON.stringify({ error: "no dock" })
      d.iconThemeRef.installWhiteSur()
      return JSON.stringify({ ok: true, installing: d.iconThemeRef.themeInstalling })
    }
  }
