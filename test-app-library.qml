// Run with: qs -p test-app-library.qml --no-color
// Uses an invisible item, never opens a dock or launches an application.
import QtQuick
import Quickshell
import "." as Dock
import "DockModel.js" as DockModel

Item {
  id: test
  property int changes: 0

  QtObject {
    id: fixture
    property var values: [
      { id: "terminal", name: "Terminal", icon: "utilities-terminal" },
      { id: "editor", name: "Editor", icon: "text-editor" },
      { id: "hidden", name: "Hidden", noDisplay: true },
      null
    ]
  }

  Dock.DockAppLibrary { id: library; entriesModel: fixture }
  Dock.DockAppLibrary { id: liveLibrary }
  Connections {
    target: library
    function onAppsChanged() { test.changes++ }
  }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  function run() {
    var rows = library.sortedEntries("")
    check(rows.length === 2, "Hidden/invalid entries should be excluded")
    check(rows[0].entry.id === "editor" && rows[1].entry.id === "terminal", "Entries should be sorted by name")
    check(fixture.values[0].id === "terminal", "Sorting must not mutate the desktop model")
    check(library.sortedEntries("TERMINAL").length === 1, "Search should ignore case")
    check(library.entryName({id: "unnamed"}) === "unnamed", "Names should fall back to the desktop ID")
    check(DockModel.entryFor(rows, "editor.desktop").id === "editor", "Rows must remain compatible with DockModel")

    var tops = [{appId: "editor", title: "Editor"}, {appId: "terminal", title: "Terminal"}]
    var model = DockModel.buildEntries(["editor"], tops, rows, library, function(top) {
      return {address: top.appId === "editor" ? "0x1" : "0x2", workspace: {name: "1"}}
    }, "special:minimized", {}, [])
    check(model.pinned.length === 1 && model.pinned[0].running, "Pinned apps should retain their running windows")
    check(model.running.length === 1 && model.running[0].name === "Terminal", "Unpinned running apps should populate the dock")
    check(model.pinned[0].icon.length > 0 && model.running[0].icon.length > 0, "App icons should resolve")

    check(library.iconSource("/tmp/My icon#1.png") === "file:///tmp/My%20icon%231.png", "Absolute icon paths must be encoded")
    check(library.iconSource("image://icon/example") === "image://icon/example", "Image provider URLs should pass through")
    check(library.iconSource("file:///tmp/icon.svg") === "file:///tmp/icon.svg", "File URLs should pass through")
    check(library.iconSource("omadock-nonexistent-test-icon").length > 0, "Unknown icons should have a fallback")
    var revision = library.iconRevision
    library.refreshIcons()
    check(library.iconRevision === revision + 1, "Theme refresh must invalidate icon bindings")

    var id = "My App $(not-a-command);"
    var args = library.launchArguments(id)
    check(JSON.stringify(args) === JSON.stringify(["uwsm-app", "--", "gtk-launch", "--", id + ".desktop"]), "Launch IDs must stay in one literal argument")
    check(library.launchArguments("org.telegram.desktop")[4] === "org.telegram.desktop.desktop", "Desktop IDs ending in .desktop still need the file suffix")
    check(library.launchArguments("").length === 0, "Empty IDs must not launch anything")

    console.log("PASS: sorting/filtering, dock model, icons, refresh, and safe launch arguments")
    console.log("Native desktop entries available:", liveLibrary.sortedEntries("").length)
    test.changes = 0
    fixture.values = [{id: "new-app", name: "New App"}]
    Qt.callLater(function() {
      try {
        check(test.changes > 0, "Desktop model changes must notify the dock without polling")
        check(library.sortedEntries("")[0].entry.id === "new-app", "Updated applications must be returned")
        console.log("PASS: live application-model change propagation")
        Qt.quit()
      } catch (error) {
        console.error(error)
        Qt.exit(1)
      }
    })
  }

  Timer {
    interval: 250
    running: true
    onTriggered: {
      try { test.run() }
      catch (error) { console.error(error); Qt.exit(1) }
    }
  }
}
