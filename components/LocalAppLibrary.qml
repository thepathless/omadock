import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../DockModel.js" as DockModel
import "../DockIcons.js" as DockIcons
import "../DockIconTheme.js" as DockIconTheme

// Fallback standalone application library for host capability gates (e.g.
// Omarchy 4.x scoped plugins) plus the absolute-path icon index (see
// AGENTS.md "Icon Resolution"). Non-visual helper component: the dock root
// passes itself as rootRef; the scan process and its coalescing watcher are
// private to this component.

  Item {
    id: localAppLibrary

    property var rootRef: null
    width: 0
    height: 0

    signal appsChanged()

    // The desktop's icon theme and the themes installed beside it. The theme
    // belongs to the system (gsettings' icon-theme plus the GTK/KDE files
    // scripts/icon-theme.sh writes), never to omadock.json: every app shares
    // it, so this component reads it, applies it and scans through it. The
    // index below is theme-first, so the dock draws the same artwork as every
    // other app; the rest of the themes stay as a fallback so a theme that is
    // named but not installed still renders.
    property string iconTheme: ""
    property var themes: []
    property string themeError: ""
    // True while the WhiteSur download runs, so the button can say so.
    readonly property bool themeInstalling: iconThemeInstall.running
    // A theme that lands while a scan is walking the old chain queues exactly
    // one more pass: the first scan starts at load, before gsettings answers,
    // and would otherwise leave fallback artwork in the index for good.
    property bool rescanPending: false
    // The staged Omarchy theme's icons.theme, for a host without gsettings.
    readonly property string stagedTheme: (rootRef && rootRef.themeIconsFileRef)
      ? String(rootRef.themeIconsFileRef.text || "").trim() : ""

    function probeTheme() { if (!iconThemeProbe.running) iconThemeProbe.running = true }

    function setIconTheme(id) {
      if (!DockIconTheme.safeId(id) || id === localAppLibrary.iconTheme) return
      if (iconThemeApply.running) {
        // A second click while the first apply is in flight must say so, not
        // silently leave the picker showing a value the desktop never got.
        localAppLibrary.themeError = "An icon theme change is already running."
        return
      }
      localAppLibrary.themeError = ""
      iconThemeApply.pending = id
      iconThemeApply.command = ["bash", localAppLibrary.helperPath("icon-theme.sh"), "apply", id]
      iconThemeApply.running = true
    }

    // The one theme the dock can fetch for you: WhiteSur (the macOS look).
    // scripts/icon-theme.sh installs it into ~/.local/share/icons and applies
    // it, so both the picker and the setting land in one click. A host without
    // network leaves themeError set and nothing else changes.
    function installWhiteSur() {
      if (iconThemeInstall.running) return
      localAppLibrary.themeError = ""
      iconThemeInstall.running = true
    }

    Process {
      id: iconThemeProbe
      running: false
      command: ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"]
      stdout: StdioCollector { id: iconThemeProbeOut; waitForEnd: true }
      onExited: function(code) {
        var value = String(iconThemeProbeOut.text || "").trim().replace(/^["']|["']$/g, "")
        if (code === 0 && DockIconTheme.safeId(value)) localAppLibrary.iconTheme = value
        else localAppLibrary.useStagedIconTheme()
      }
    }

    function useStagedIconTheme() {
      var t = String(localAppLibrary.stagedTheme || "").trim()
      if (t && DockIconTheme.safeId(t)) localAppLibrary.iconTheme = t
    }

    Process {
      id: iconThemeApply
      property string pending: ""
      running: false
      stderr: StdioCollector { id: iconThemeApplyErr; waitForEnd: true }
      onExited: function(code) {
        if (code !== 0) {
          localAppLibrary.themeError = String(iconThemeApplyErr.text || "").trim() || "Could not apply the icon theme."
          // The list may still name a theme that was removed or left partial
          // after it was read; ask again so the picker matches the disk.
          localAppLibrary.refreshThemes()
          return
        }
        localAppLibrary.iconTheme = iconThemeApply.pending
        // If a scan is already running, refreshIcons queues exactly one more
        // pass; the applied theme is not lost behind a scan of the old chain.
        localAppLibrary.refreshIcons()
      }
    }

    Process {
      id: iconThemeInstall
      running: false
      command: ["bash", localAppLibrary.helperPath("icon-theme.sh"), "install"]
      stdout: StdioCollector { id: iconThemeInstallOut; waitForEnd: true }
      stderr: StdioCollector { id: iconThemeInstallErr; waitForEnd: true }
      onExited: function(code) {
        var applied = String(iconThemeInstallOut.text || "").trim()
        if (code !== 0 || !DockIconTheme.safeId(applied)) {
          localAppLibrary.themeError = String(iconThemeInstallErr.text || "").trim() || "Could not install WhiteSur."
          localAppLibrary.refreshThemes()
          return
        }
        localAppLibrary.iconTheme = applied
        localAppLibrary.refreshIcons()
        localAppLibrary.refreshThemes()
      }
    }

    // Absolute-path icon index, mirroring the host AppLibrary. Qt's themed
    // lookup resolves against the *configured* icon theme, so a theme that is
    // named but not installed (e.g. Omarchy's vantablack -> "Yaru-gray", which
    // yaru-icon-theme no longer ships) makes Quickshell.iconPath() return ""
    // for every name and the dock renders blank slots. The host's own menu
    // survives that because it consults this index first; the fallback library
    // has to do the same or it is strictly more fragile than the host.
    property var iconIndex: ({})

    function sortedEntries(query) {
      try {
        var values = DesktopEntries.applications.values
        if (!values) return []
        return values.filter(function(e) { return !e.noDisplay })
      } catch (e) {
        console.warn("[omadock] Failed reading desktop entries:", e)
        return []
      }
    }

    function entryName(entry) {
      if (!entry) return ""
      var target = (entry && entry.entry) ? entry.entry : entry
      var n = String(target.name || "")
      return n !== "" ? n : String(target.id || "")
    }

    function iconSource(icon) {
      var value = String(icon || "")
      if (value === "") return localAppLibrary.fallbackIcon()
      if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
      if (value.charAt(0) === "/") return Util.fileUrl(value)
      // Reading iconIndex registers the dependency, so swapping the property
      // after a scan re-evaluates every binding that called through here.
      var found = localAppLibrary.iconIndex[value]
      if (found) return Util.fileUrl(found)
      var themed = ""
      try {
        themed = Quickshell.iconPath(value, true)
      } catch (e) {
        console.warn("[omadock] Failed resolving themed icon path:", value, e)
      }
      if (themed && themed.length > 0) return themed
      return localAppLibrary.fallbackIcon()
    }

    // Generic placeholder, resolved through the same index so it survives a
    // broken theme too. Returns "" only if nothing at all is on disk, which
    // callers already treat as "draw nothing".
    function fallbackIcon() {
      var found = localAppLibrary.iconIndex["application-x-executable"]
      if (found) return Util.fileUrl(found)
      var themed = ""
      try {
        themed = Quickshell.iconPath("application-x-executable", true)
      } catch (e) {
        console.warn("[omadock] Failed resolving fallback icon path:", e)
      }
      return themed || ""
    }

    function refreshIcons() {
      if (iconIndexScan.running) {
        localAppLibrary.rescanPending = true
        return
      }
      iconIndexScan.running = true
    }

    // The panel asks for this when it opens and after a failed apply. If a
    // read is already in flight it may have started before a theme was removed,
    // so queue exactly one more pass: an ignored request would leave the list
    // advertising a theme the disk no longer has.
    property bool themeRescanPending: false

    function refreshThemes() {
      if (iconThemeScan.running) {
        localAppLibrary.themeRescanPending = true
        return
      }
      localAppLibrary.themeRescanPending = false
      iconThemeScan.running = true
    }

    function helperPath(name) {
      return decodeURIComponent(Qt.resolvedUrl("../scripts/" + name).toString().replace(/^file:\/\//, ""))
    }

    // The active theme and the themes it inherits from, as directory names.
    // DockIconTheme.chain has already rejected anything that is not a plain id,
    // so these can name directories in the scan below.
    function themeChain() { return DockIconTheme.chain(localAppLibrary.iconTheme, localAppLibrary.themes) }

    // The active theme's directories are searched for BOTH formats before any
    // other theme is consulted, so a theme's PNG beats another theme's SVG;
    // within each group SVGs come first, which keeps the first hit per name
    // scalable. awk keeps only that first hit (QML would otherwise parse
    // ~23 600 lines instead of ~2 300).
    function iconIndexScanCommand() {
      var first = []
      var chain = localAppLibrary.themeChain()
      for (var i = 0; i < chain.length; i++) {
        first.push("$HOME/.icons/" + chain[i])
        first.push("$HOME/.local/share/icons/" + chain[i])
        // System themes ship here; XDG_DATA_DIRS' extra roots are reached by
        // the generic pass below.
        first.push("/usr/share/icons/" + chain[i])
        first.push("/usr/local/share/icons/" + chain[i])
      }
      var all = first.slice()
      all.push("$HOME/.icons", "$HOME/.local/share/icons")
      return [
        'first="' + first.join(" ") + '";',
        'dirs="' + all.join(" ") + '";',
        'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
        '{ for base in $first; do',
        '  [[ -d $base ]] || continue;',
        '  for ext in svg png; do',
        '    find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" -o -path "*/places/*" -o -path "*/mimetypes/*" \\) -name "*.$ext" 2>/dev/null;',
        '  done;',
        'done;',
        'for base in $dirs; do',
        '  [[ -d $base ]] || continue;',
        '  for ext in svg png; do',
        '    find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" -o -path "*/places/*" -o -path "*/mimetypes/*" \\) -name "*.$ext" 2>/dev/null;',
        '  done;',
        'done;',
        'for ext in svg png; do find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null; done; } | awk -F/ \'{ n = $NF; sub(/\\.[^.]*$/, "", n); if (!(n in seen)) { seen[n] = 1; print } }\''
      ].join(' ')
    }

    function launch(desktopId, name) {
      var id = String(desktopId || "")
      if (id === "") return
      // Always append .desktop — DesktopEntry.id strips the extension, so
      // ids like org.telegram.desktop need it re-added to resolve correctly.
      // Redirect stdout and stderr to /dev/null so spawned applications don't inherit
      // transient QProcess pipes that close when gtk-launch exits (causing EPIPE crashes).
      var args = ["bash", "-c", "exec uwsm-app -- gtk-launch -- \"$1\" >/dev/null 2>&1", "_", id + ".desktop"]
      var desktop = DockModel.entryFor(rootRef.appRows, id)
      // GTK's generic terminal launch loses the CLI app-id, so a known CLI
      // product would come back wearing its terminal's identity. Route only
      // those two through Omarchy's TUI wrapper with the already parsed argv;
      // every other terminal entry keeps its normal launch path.
      if (desktop && DockModel.isKnownCli(id) && desktop.runInTerminal && desktop.command && desktop.command.length > 0) {
        var tuiCommand = ["omarchy-launch-tui", "--app-id=org.omarchy." + id].concat(DockModel.toArray(desktop.command))
        args = ["bash", "-c", 'cd -- "$1" || exit; shift; exec "$@" >/dev/null 2>&1',
                "_", desktop.workingDirectory || Quickshell.env("HOME")].concat(tuiCommand)
      }
      // gtk-launch exits non-zero up front when the desktop file no longer
      // resolves (stale pin, uninstalled app), but execDetached cannot
      // observe exit codes. Launches run through launchProc so failures
      // surface a notification instead of bouncing silently. The overlap
      // fallback keeps rare concurrent clicks fire-and-forget; the probe
      // itself exits within milliseconds.
      if (launchProc.running) {
        Quickshell.execDetached(args)
        return
      }
      launchProc.pendingName = String(name || id)
      launchProc.command = args
      launchProc.running = true
    }

    // One-shot scans only: started on load, on app-list changes and on theme
    // changes. Nothing polls, so the dock stays at 0% CPU when idle.
    Process {
      id: iconIndexScan
      command: ["bash", "-c", localAppLibrary.iconIndexScanCommand()]
      // One collected read, parsed once: a callback per line cost ~23 600
      // GUI-thread calls on every start and theme change.
      stdout: StdioCollector { id: iconIndexOut; waitForEnd: true }
      onExited: {
        localAppLibrary.iconIndex = DockIcons.parseIconIndex(iconIndexOut.text)
        localAppLibrary.appsChanged()
        if (localAppLibrary.rescanPending) {
          localAppLibrary.rescanPending = false
          Qt.callLater(function() { localAppLibrary.refreshIcons() })
        }
      }
    }

    // Installed themes, read once and again whenever the panel asks. The
    // script is the same one that applies a theme, so listing and applying
    // cannot drift apart.
    Process {
      id: iconThemeScan
      running: false
      command: ["bash", localAppLibrary.helperPath("icon-theme.sh"), "list"]
      stdout: StdioCollector { id: iconThemeScanOut; waitForEnd: true }
      onExited: function(code) {
        if (code === 0) localAppLibrary.themes = DockIconTheme.parseList(iconThemeScanOut.text)
        if (localAppLibrary.themeRescanPending) {
          // running is still true inside onExited; defer so the queued read
          // starts after it clears, instead of refreshThemes queueing itself
          // again for ever.
          localAppLibrary.themeRescanPending = false
          Qt.callLater(function() { localAppLibrary.refreshThemes() })
        }
      }
    }

    onIconThemeChanged: localAppLibrary.refreshIcons()
    Component.onCompleted: localAppLibrary.refreshThemes()

    // Coalesces bursts of app-list changes (one package install touches many
    // entries) into a single rescan.
    Timer {
      id: iconIndexDebounce
      interval: 750
      onTriggered: localAppLibrary.refreshIcons()
    }

    Connections {
      target: (rootRef.appLibrary === localAppLibrary && typeof DesktopEntries !== "undefined") ? DesktopEntries : null
      function onApplicationsChanged() {
        iconIndexDebounce.restart()
        localAppLibrary.appsChanged()
      }
    }
}
