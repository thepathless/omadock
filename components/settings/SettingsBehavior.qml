import QtQuick
import qs.Commons
import qs.Ui
import "../strings"

// Settings page: visibility, click behaviour, attention and tooltip rows.
// Instantiated by SettingsPanel, which injects root (the Dock, for
// values and setters) and panel (page/edit state).

Column {
  property var root: null
  property var panel: null
  width: parent.width


  SectionLabel { title: "Clicking an app" }

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
  SettingsSection {
    title: Tr.t("settings.windowTuning", "Advanced window behavior")
  SwitchRow {
    key: "keepPointer"
    label: "Keep pointer in place"
    hint: "Don't move the mouse pointer onto the window a click brings up."
    checked: root ? root.keepPointer : true
    onToggled: root.setOption("keepPointer", !root.keepPointer)
  }
  ChoiceRow {
    key: "restoreWorkspace"
    label: "Restore on"
    hint: "Where a minimized window comes back to. Windows restores it to the workspace it was minimized from."
    options: [
      { value: "current", label: "Current workspace" },
      { value: "origin", label: "Original workspace" }
    ]
    value: root ? root.restoreWorkspace : "current"
    onPicked: function(v) { root.setOption("restoreWorkspace", v) }
  }
  SwitchRow {
    key: "restoreSlot"
    label: "Restore original slot"
    hint: "Put the window back in the place it held in the tiling layout, not at the end. Only when the layout has not changed in the meantime."
    checked: root ? root.restoreSlot : false
    onToggled: root.setOption("restoreSlot", !root.restoreSlot)
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

  }

  SectionLabel { title: "Attention" }

  SwitchRow {
    key: "badges"
    label: "Notification badges"
    hint: "Count active notification popups on pinned apps; clears on dismissal or expiry."
    checked: root ? root.showNotificationBadges : true
    onToggled: root.setOption("showNotificationBadges", !root.showNotificationBadges)
  }
  SettingsSection {
    title: Tr.t("settings.badgeTuning", "Advanced badge styling")
  ChoiceRow {
    key: "badgeStyle"
    label: "Badge style"
    hint: "A count pill or a plain dot on the icon."
    options: [
      { value: "count", label: "Count" },
      { value: "dot", label: "Dot" }
    ]
    value: root ? root.badgeStyle : "count"
    onPicked: function(v) { root.setOption("badgeStyle", v) }
  }
  ChoiceRow {
    key: "badgePosition"
    label: "Badge position"
    hint: "The corner of the icon the badge sits on."
    options: [
      { value: "top-right", label: "Top right" },
      { value: "top-left", label: "Top left" },
      { value: "bottom-right", label: "Bottom right" },
      { value: "bottom-left", label: "Bottom left" }
    ]
    value: root ? root.badgePosition : "top-right"
    onPicked: function(v) { root.setOption("badgePosition", v) }
  }
  ChoiceRow {
    key: "badgeColor"
    label: "Badge color"
    hint: "Accent, urgent red, or a neutral pill."
    options: [
      { value: "accent", label: "Accent" },
      { value: "urgent", label: "Urgent" },
      { value: "neutral", label: "Neutral" }
    ]
    value: root ? root.badgeColor : "accent"
    onPicked: function(v) { root.setOption("badgeColor", v) }
  }
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
  SettingsSection {
    title: Tr.t("settings.soundTuning", "Alert sound")
  SettingRow {
    key: "urgentSound"
    label: "Urgent sound"

    Dropdown {
      width: Style.space(200)
      showLabel: false
      options: [
        { value: "bell", label: Tr.t("setting.urgentSound.option.bell", "Bell") },
        { value: "message-new-instant", label: Tr.t("setting.urgentSound.option.message-new-instant", "Message chime") },
        { value: "complete", label: Tr.t("setting.urgentSound.option.complete", "Complete ding") },
        { value: "dialog-information", label: Tr.t("setting.urgentSound.option.dialog-information", "Information pop") },
        { value: "dialog-warning", label: Tr.t("setting.urgentSound.option.dialog-warning", "Warning alert") },
        { value: "phone-incoming-call", label: Tr.t("setting.urgentSound.option.phone-incoming-call", "Phone ring") },
        { value: "alarm-clock-elapsed", label: Tr.t("setting.urgentSound.option.alarm-clock-elapsed", "Alarm beeps") },
        { value: "none", label: Tr.t("setting.urgentSound.option.none", "Mute") }
      ]
      value: root ? (root.urgentSound ? root.urgentSoundName : "none") : "bell"
      onChanged: function(v) { root.setUrgentSoundName(v) }
    }
  }

  }

  SectionLabel { title: "Previews & Tooltips" }

  SwitchRow {
    key: "tooltips"
    label: "Tooltips"
    checked: root ? root.showTooltips : true
    onToggled: root.setOption("showTooltips", !root.showTooltips)
  }
  SettingsSection {
    title: Tr.t("settings.tooltipTuning", "Advanced tooltip timing")
  SliderRow {
    key: "tooltipDelay"
    label: "Tooltip delay"
    minimum: 0
    maximum: 2000
    step: 50
    suffix: " ms"
    value: root ? root.tooltipDelay : 450
    onCommitted: function(v) { root.setOption("tooltipDelay", Math.round(v)) }
  }
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
