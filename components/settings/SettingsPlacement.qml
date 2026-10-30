import QtQuick
import qs.Commons
import qs.Ui
import "../strings"
import "../../DockLayout.js" as DockLayout

// Settings page: alignment and monitor rows.
// Instantiated by SettingsPanel, which injects root (the Dock, for
// values and setters) and panel (page/edit state).

Column {
  property var root: null
  property var panel: null
  width: parent.width


  SectionLabel { title: "Position" }

  ChoiceRow {
    key: "layout"
    label: "Layout"
    hint: "Panel spans the screen's full width along the bottom edge."
    options: [
      { value: "dock", label: "Dock" },
      { value: "panel", label: "Panel" }
    ]
    value: root ? root.layout : "dock"
    onPicked: function(v) { root.setDockLayout(v) }
  }
  ChoiceRow {
    key: "alignment"
    label: "Alignment"
    // The Omarchy ButtonGroup has no disabled state: Both sides is left
    // out where it cannot apply, and the hint says why.
    readonly property bool spreadOk: root ? DockLayout.spreadAvailable(root.layout, root.splitSections) : false
    readonly property bool panelOk: root ? DockLayout.normalizeLayout(root.layout) === "panel" : false
    hint: root && root.alignment === "taskbar"
      ? (panelOk
        ? Tr.t("setting.alignment.hintTaskbar", "Start at the left edge, app icons centred and the clock on the right.")
        : Tr.t("setting.alignment.hintTaskbarNeedsPanel", "Taskbar needs the Panel layout; centred until then."))
      : !spreadOk
        ? (root && root.alignment === "spread"
          ? Tr.t("setting.alignment.hintSpreadCentred", "Both sides needs Split sections (Appearance); centred until then.")
          : Tr.t("setting.alignment.hintSpreadNeedsSplit", "Both sides needs Split sections (Appearance)."))
        : (root && root.alignment === "spread" ? Tr.t("setting.alignment.hintSpread", "Folders and drives go to the right edge.") : "")
    options: {
      var list = [
        { value: "left", label: "Left" },
        { value: "center", label: "Center" },
        { value: "right", label: "Right" }
      ]
      if (spreadOk) list.push({ value: "spread", label: "Both sides" })
      if (panelOk) list.push({ value: "taskbar", label: "Taskbar" })
      return list
    }
    // A stored Both sides that cannot apply marks what the dock draws.
    value: root ? (spreadOk ? (root.alignment || "center") : root.placement.align) : "center"
    onPicked: function(v) { root.setDockAlignment(v) }
  }

  SectionLabel { title: "Monitors" }

  SwitchRow {
    key: "multiMonitor"
    label: "Show on all monitors"
    hint: "One dock per connected monitor."
    checked: root ? root.multiMonitor : false
    onToggled: root.setOption("multiMonitor", !root.multiMonitor)
  }
  SwitchRow {
    key: "perMonitorApps"
    label: "Only this monitor's apps"
    hint: "Each dock lists the windows on its own monitor; pinned apps show everywhere."
    visible: root ? root.multiMonitor : false
    checked: root ? root.perMonitorApps : true
    onToggled: root.setOption("perMonitorApps", !root.perMonitorApps)
  }
  SettingRow {
    key: "monitorSelect"
    label: root && root.multiMonitor ? Tr.t("setting.monitorSelect.labelPrimary", "Primary monitor") : Tr.t("setting.monitorSelect.labelSingle", "Monitor")
    hint: root && root.multiMonitor
      ? Tr.t("setting.monitorSelect.hintPrimary", "Plays the alert sounds.")
      : Tr.t("setting.monitorSelect.hintSingle", "Automatic picks the first connected output.")

    Dropdown {
      width: Style.space(200)
      showLabel: false
      options: {
        var list = [{ value: "", label: Tr.t("setting.monitorSelect.option.automatic", "Automatic") }]
        var screens = root ? root.realScreens : []
        for (var i = 0; i < screens.length; i++)
          list.push({ value: screens[i].name, label: screens[i].name + (screens[i].model ? " — " + screens[i].model : "") })
        if (root && root.screenName && !root.screenForName(root.screenName))
          list.push({ value: root.screenName, label: Tr.t("setting.monitorSelect.disconnected", "%1 (disconnected)").arg(root.screenName) })
        return list
      }
      value: root ? root.screenName : ""
      onChanged: function(v) { root.setDockScreen(v) }
    }
  }
}
