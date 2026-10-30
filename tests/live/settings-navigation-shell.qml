  Od.DockHost { id: host }
  property var input: null
  property var panel: null
  property string error: ""

  function dock() { var ds = host.orderedDocks(); return ds.length ? ds[0] : null }
  function safe() {
    var d = dock()
    return d && d.dockScreen && String(d.dockScreen.name) === Quickshell.env("PROBE_SCREEN")
  }
  function find(o, name, depth) {
    if (!o || depth > 30) return null
    if (o.objectName === name) return o
    var kids = o.children || []
    for (var i = 0; i < kids.length; i++) { var hit = find(kids[i], name, depth + 1); if (hit) return hit }
    return null
  }
  // The first thing a Tab would land on: a dropdown's trigger, say, rather
  // than the component root the test names.
  function focusable(o, depth) {
    if (!o || depth > 30) return null
    if (o.activeFocusOnTab && o.visible && o.enabled) return o
    var kids = o.children || []
    for (var i = 0; i < kids.length; i++) { var hit = focusable(kids[i], depth + 1); if (hit) return hit }
    return null
  }
  function dropdown(panel) {
    var dd = find(panel.pageContent, "settings-icon-theme-dropdown", 0)
    if (!dd) return null
    var opts = [], filt = []
    for (var i = 0; i < dd.options.length; i++)
      opts.push({ value: String(dd.options[i].value), label: String(dd.options[i].label), description: String(dd.options[i].description) })
    for (var j = 0; j < dd.filtered.length; j++) filt.push(String(dd.filtered[j].value))
    return { found: true, visible: dd.visible, open: !!dd.popupOpen, value: String(dd.value),
      current: String(dd.currentLabel()), options: opts, filtered: filt }
  }
  function report(key) {
    if (!panel) return { error: error || "no panel" }
    var row = panel.rowByKey[key]
    var controls = [], advanced = []
    function walk(o, depth) {
      if (!o || depth > 30) return
      if (o.key && o.visible) controls.push(o.key)
      if (o.expanded !== undefined) advanced.push({ title: o.title, expanded: o.expanded })
      var kids = o.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1)
    }
    walk(panel.pageContent, 0)
    return { page: panel.page, categories: panel.pages.map(function(p) { return p.id }),
      target: panel.targetKey, focus: input.focused(panel.pageContent),
      editing: { preset: panel.editingPresetId, group: panel.editingGroupId },
      hits: panel.searchHits, scroll: panel.pageScroller.contentY,
      row: row ? { visible: row.visible, available: row.available, hint: row.shownHint,
        dependency: row.dependency, highlighted: row.highlighted,
        y: row.mapToItem(panel.pageContent, 0, 0).y,
        height: row.height } : null,
      viewport: panel.pageScroller.height, visibleKeys: controls, advanced: advanced,
      themes: { installed: dock().iconThemeRef.themes.length, current: dock().iconThemeRef.iconTheme,
        installedIds: dock().iconThemeRef.themes.map(function(th) { return th.id }),
        error: String(dock().iconThemeRef.themeError),
        chain: dock().iconThemeRef.themeChain(),
        whiteSurInstalled: dock().iconThemeRef.themes.some(function(th) { return th.id.indexOf("WhiteSur") === 0 }),
        whiteSur: (function() {
          var dd = dropdown(panel)
          if (!dd) return { found: false }
          var entry = null
          for (var i = 0; i < dd.options.length; i++)
            if (dd.options[i].value.indexOf("__install") === 0) entry = dd.options[i]
          return { found: dd.found, visible: dd.visible, installEntry: !!entry,
            text: entry ? entry.label : "", open: dd.open, value: dd.value }
        })(),
        folder: String(dock().iconThemeRef.iconIndex["folder"] || "") },
      settingsOpen: dock().settingsPanelOpen,
      iconThemeDropdownOpen: panel.iconThemeDropdownOpen,
      config: dock().buildConfig({}) }
  }

  IpcHandler {
    target: "omadock-settings-test"
    function run(action: string, arg: string): string {
      if (!safe()) return JSON.stringify({ error: "wrong screen" })
      var d = dock()
      if (action === "open") {
        // The real settings component, with only its layer-shell keyboard
        // policy overridden BEFORE mapping. No exclusive keyboard grab.
        var plugin = Qt.createComponent("file:" + Quickshell.env("SETTINGS_INPUT_QML"))
        input = plugin.createObject(host)
        var component = Qt.createComponent("file:" + Quickshell.env("SETTINGS_PANEL_QML"))
        panel = component.createObject(host, { rootRef: d, visible: false })
        if (!panel) { error = component.errorString(); return JSON.stringify({ error: error }) }
        panel.visible = true
        return JSON.stringify({ opened: true })
      }
      if (!panel || !input) return JSON.stringify({ error: "not opened" })
      if (action === "category") {
        var nav = find(panel.contentItem, "settings-category-" + arg, 0)
        return JSON.stringify({ keySent: input.key(nav, Qt.Key_Return) })
      }
      if (action === "legacy") { d.settingsPanelPage = arg; return JSON.stringify({ page: panel.page }) }
      if (action === "search") {
        panel.searchInput.text = arg
        return JSON.stringify({ hits: panel.searchHits })
      }
      if (action === "enter-search") return JSON.stringify({ keySent: input.key(panel.searchInput, Qt.Key_Return) })
      if (action === "goto") { panel.gotoSetting(arg); return JSON.stringify({ target: panel.targetKey }) }
      if (action === "key" || action === "key-focused") {
        var args = arg.split(":")
        var object = find(panel.contentItem, args[0], 0)
        var keys = { Right: Qt.Key_Right, Left: Qt.Key_Left, Space: Qt.Key_Space, Return: Qt.Key_Return,
          Tab: Qt.Key_Tab, Backtab: Qt.Key_Backtab, Down: Qt.Key_Down, Up: Qt.Key_Up, PageDown: Qt.Key_PageDown,
          Escape: Qt.Key_Escape }
        var code = keys[args[1]]
        if (code === undefined && args[1].length === 1) code = args[1].toUpperCase().charCodeAt(0)
        var sent = action === "key" ? input.key(object, code) : input.keyFocused(object, code)
        return JSON.stringify({ keySent: sent, focus: input.focused(panel.pageContent) })
      }
      if (action === "key-trigger") {
        // A synthetic key on the first Tab stop of a named component: the
        // dropdown trigger, which takes focus and opens the list on Enter.
        var parts = arg.split(":")
        var trigger = focusable(find(panel.contentItem, parts[0], 0), 0)
        var codes = { Return: Qt.Key_Return, Enter: Qt.Key_Enter, Down: Qt.Key_Down, Space: Qt.Key_Space, Escape: Qt.Key_Escape }
        var keyCode = codes[parts[1]]
        if (keyCode === undefined && parts[1].length === 1) keyCode = parts[1].toUpperCase().charCodeAt(0)
        return JSON.stringify({ keySent: input.key(trigger, keyCode), focus: input.focused(panel.pageContent) })
      }
      if (action === "read-dropdown") return JSON.stringify(dropdown(panel) || { found: false })
      if (action === "targets") return JSON.stringify(Object.keys(panel.rowByKey))
      if (action === "read") return JSON.stringify(report(arg))
      if (action === "close") { panel.visible = false; panel.destroy(); panel = null; return "ok" }
      return JSON.stringify({ error: "unknown action" })
    }
  }
