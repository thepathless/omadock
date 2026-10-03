import QtQuick
import qs.Commons
import qs.Ui

// Settings page: alignment and monitor rows.
// Instantiated by SettingsPanel, which injects root (the Dock, for
// values and setters) and panel (page/edit state).

Column {
  property var root: null
  property var panel: null
  width: parent.width


  SectionLabel { text: "Position" }

  ChoiceRow {
    key: "alignment"
    label: "Alignment"
    options: [
      { value: "left", label: "Left" },
      { value: "center", label: "Center" },
      { value: "right", label: "Right" }
    ]
    value: root ? (root.alignment || "center") : "center"
    onPicked: function(v) { root.setDockAlignment(v) }
  }

  SectionLabel { text: "Monitors" }

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
    label: root && root.multiMonitor ? "Primary monitor" : "Monitor"
    hint: root && root.multiMonitor
      ? "Plays the alert sounds."
      : "Automatic picks the first connected output."

    Dropdown {
      width: Style.space(200)
      showLabel: false
      options: {
        var list = [{ value: "", label: "Automatic" }]
        var screens = root ? root.realScreens : []
        for (var i = 0; i < screens.length; i++)
          list.push({ value: screens[i].name, label: screens[i].name + (screens[i].model ? " — " + screens[i].model : "") })
        if (root && root.screenName && !root.screenForName(root.screenName))
          list.push({ value: root.screenName, label: root.screenName + " (disconnected)" })
        return list
      }
      value: root ? root.screenName : ""
      onChanged: function(v) { root.setDockScreen(v) }
    }
  }
}
