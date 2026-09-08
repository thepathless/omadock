import QtQuick
import Quickshell

// Overlay plugins no longer receive shell.appLibrary on Omarchy 4.0.3.
// Use Quickshell's public desktop-entry model without requesting menu/bar
// capabilities or reaching into the shell's private object tree.
Item {
  id: root

  property var entriesModel: DesktopEntries.applications
  property int iconRevision: 0
  signal appsChanged()

  Connections {
    target: root.entriesModel
    function onValuesChanged() { root.appsChanged() }
  }

  function entryName(entry) {
    return String((entry && (entry.name || entry.id)) || "")
  }

  function sortedEntries(query) {
    var values = root.entriesModel ? root.entriesModel.values : []
    var search = String(query || "").trim().toLowerCase()
    var rows = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay) continue
      var name = root.entryName(entry)
      if (!name) continue
      if (search && (name + " " + entry.id + " " + (entry.genericName || "")).toLowerCase().indexOf(search) < 0) continue
      // Keep the row.entry shape used by the shell and DockModel.
      rows.push({ entry: entry, name: name.toLowerCase() })
    }
    rows.sort(function(a, b) {
      return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
    })
    return rows
  }

  function iconSource(icon) {
    var revision = root.iconRevision
    var value = String(icon || "")
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value.split("/").map(encodeURIComponent).join("/")
    var themed = value ? Quickshell.iconPath(value, true) : ""
    return themed || Quickshell.iconPath("application-x-executable", true)
  }

  function refreshIcons() {
    // Dock already watches the theme files and resolves theme-specific icons.
    // Invalidate bindings without adding another polling timer or index scan.
    root.iconRevision++
  }

  function launchArguments(desktopId) {
    var id = String(desktopId || "")
    if (!id) return []
    // IDs from DesktopEntries omit the file suffix, even org.telegram.desktop.
    // gtk-launch handles Terminal/Path/field codes; uwsm keeps the application
    // outside the shell's process scope. Never interpolate an ID into a shell.
    return ["uwsm-app", "--", "gtk-launch", "--", id + ".desktop"]
  }

  function launch(desktopId, name) {
    var args = root.launchArguments(desktopId)
    if (args.length > 0) Quickshell.execDetached(args)
  }
}
