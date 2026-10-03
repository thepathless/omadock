import QtQuick
import qs.Commons
import qs.Ui

// Settings page: visibility, click behaviour, attention and tooltip rows.
// Instantiated by SettingsPanel, which injects root (the Dock, for
// values and setters) and panel (page/edit state).

Column {
  property var root: null
  property var panel: null
  width: parent.width


  SectionLabel { text: "Visibility" }

  ChoiceRow {
    key: "autohide"
    label: "Autohide"
    hint: "Intelligent hides only when a window overlaps the dock."
    options: [
      { value: "always", label: "Always show" },
      { value: "intelligent", label: "Intelligent" },
      { value: "autohide", label: "Autohide" }
    ]
    value: root ? (!root.autohide ? "always" : (root.intelligentAutohide ? "intelligent" : "autohide")) : "always"
    onPicked: function(v) { root.setAutohideMode(v) }
  }
  SliderRow {
    key: "revealDelay"
    label: "Reveal delay"
    hint: "How long the pointer rests on the edge before the dock slides in."
    enabled: root ? root.autohide : false
    opacity: enabled ? 1 : 0.45
    minimum: 0
    maximum: 1000
    step: 10
    suffix: " ms"
    value: root ? root.revealDelay : 160
    onCommitted: function(v) { root.setOption("revealDelay", Math.round(v)) }
  }

  SectionLabel { text: "Clicking an app" }

  ChoiceRow {
    key: "minimizeMode"
    label: "Minimize on click"
    hint: "Clicking the focused app's icon parks its windows."
    options: [
      { value: "off", label: "Off" },
      { value: "active", label: "Active window" },
      { value: "all", label: "All windows" }
    ]
    value: root ? root.minimizeMode : "active"
    onPicked: function(v) { root.setOption("minimizeMode", v) }
  }
  SwitchRow {
    key: "keepPointer"
    label: "Keep pointer in place"
    hint: "Don't move the mouse pointer onto the window a click brings up."
    checked: root ? root.keepPointer : true
    onToggled: root.setOption("keepPointer", !root.keepPointer)
  }
  SliderRow {
    key: "wheelStepDelay"
    label: "Wheel step delay"
    hint: "Scrolling over an app flips through its windows; this paces the steps."
    minimum: 0
    maximum: 500
    step: 10
    suffix: " ms"
    value: root ? root.wheelStepDelay : 150
    onCommitted: function(v) { root.setOption("wheelStepDelay", Math.round(v)) }
  }

  SectionLabel { text: "Attention" }

  SwitchRow {
    key: "badges"
    label: "Notification badges"
    hint: "Count active notification popups on pinned apps; clears on dismissal or expiry."
    checked: root ? root.showNotificationBadges : true
    onToggled: root.setOption("showNotificationBadges", !root.showNotificationBadges)
  }
  SwitchRow {
    key: "urgentHint"
    label: "Urgent highlights"
    hint: "Mark apps whose windows ask for attention."
    checked: root ? root.showUrgentHint : true
    onToggled: root.setOption("showUrgentHint", !root.showUrgentHint)
  }
  SwitchRow {
    key: "urgentOnNotification"
    label: "Urgent on notification"
    hint: "A notification from an app marks its icon."
    checked: root ? root.urgentOnNotification : true
    onToggled: root.setOption("urgentOnNotification", !root.urgentOnNotification)
  }
  SettingRow {
    key: "urgentSound"
    label: "Urgent sound"

    Dropdown {
      width: Style.space(200)
      showLabel: false
      options: [
        { value: "bell", label: "Bell" },
        { value: "message-new-instant", label: "Message chime" },
        { value: "complete", label: "Complete ding" },
        { value: "dialog-information", label: "Information pop" },
        { value: "dialog-warning", label: "Warning alert" },
        { value: "phone-incoming-call", label: "Phone ring" },
        { value: "alarm-clock-elapsed", label: "Alarm beeps" },
        { value: "none", label: "Mute" }
      ]
      value: root ? (root.urgentSound ? root.urgentSoundName : "none") : "bell"
      onChanged: function(v) { root.setUrgentSoundName(v) }
    }
  }

  SectionLabel { text: "Previews & Tooltips" }

  SwitchRow {
    key: "tooltips"
    label: "Tooltips"
    checked: root ? root.showTooltips : true
    onToggled: root.setOption("showTooltips", !root.showTooltips)
  }
  SliderRow {
    key: "tooltipDelay"
    label: "Tooltip delay"
    enabled: root ? root.showTooltips : true
    opacity: enabled ? 1 : 0.45
    minimum: 0
    maximum: 2000
    step: 50
    suffix: " ms"
    value: root ? root.tooltipDelay : 450
    onCommitted: function(v) { root.setOption("tooltipDelay", Math.round(v)) }
  }
  SwitchRow {
    key: "windowPreviews"
    label: "Window previews"
    hint: "Thumbnails of an app's windows in its tooltip; scroll over the icon to flip through them."
    checked: root ? root.advancedTooltips : true
    onToggled: root.setOption("advancedTooltips", !root.advancedTooltips)
  }
  SwitchRow {
    key: "minimizedTiles"
    label: "Minimized window tiles"
    hint: "Show parked windows as preview tiles in the dock."
    checked: root ? root.showMinimizedTiles : true
    onToggled: root.setOption("showMinimizedTiles", !root.showMinimizedTiles)
  }
}
