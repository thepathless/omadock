import QtQuick
import qs.Commons
import qs.Ui

// Settings page: hover motion, launch bounce, shadow and blur/grain rows.
// Instantiated by SettingsPanel, which injects root (the Dock, for
// values and setters) and panel (page/edit state).

Column {
  property var root: null
  property var panel: null
  width: parent.width


  SectionLabel { text: "Motion" }

  ChoiceRow {
    key: "hoverEffect"
    label: "Hover effect"
    options: [
      { value: "zoom", label: "Zoom" },
      { value: "wave", label: "Wave" },
      { value: "lift", label: "Lift" },
      { value: "glow", label: "Glow" },
      { value: "glitch", label: "Glitch" },
      { value: "off", label: "None" }
    ]
    value: root ? root.hoverEffect : "zoom"
    onPicked: function(v) { root.setHoverEffect(v) }
  }
  SwitchRow {
    key: "launchBounce"
    label: "Launch bounce"
    hint: "Bounce the icon while an app is starting."
    checked: root ? root.launchBounce : true
    onToggled: root.setOption("launchBounce", !root.launchBounce)
  }

  SectionLabel { text: "Shadow" }

  SwitchRow {
    key: "showShadow"
    label: "Shadow"
    hint: "Under the dock; with the background off, under each icon."
    checked: root ? root.showShadow : true
    onToggled: root.setOption("showShadow", !root.showShadow)
  }
  SliderRow {
    key: "shadowStrength"
    label: "Strength"
    visible: root ? root.showShadow : true
    minimum: 0
    maximum: 1
    step: 0.05
    displayScale: 100
    suffix: "%"
    value: root ? root.shadowStrength : 0.4
    onCommitted: function(v) { root.setOption("shadowStrength", Math.round(v * 100) / 100) }
  }

  // Blur and grain paint on the background card, so the rows keep
  // the old gating and show only while the background is on.
  Column {
    width: parent.width
    visible: root ? root.showBackground : true

    SectionLabel { text: "Blur & Grain" }

    SwitchRow {
      key: "blurSystem"
      label: "Blur from system"
      hint: "Leave blur behind the dock to your Hyprland layer rules."
      checked: root ? root.blurMode === "system" : true
      onToggled: root.setBlurMode(root.blurMode === "system" ? "on" : "system")
    }
    SwitchRow {
      key: "blur"
      label: "Blur"
      hint: panel.systemBlurEnabled
        ? "Frosted glass behind the dock."
        : "Hyprland blur is off (decoration:blur:enabled), so this has no visible effect."
      visible: root ? root.blurMode !== "system" : false
      checked: root ? root.blurMode === "on" : false
      onToggled: root.setBlurMode(root.blurMode === "on" ? "off" : "on")
    }
    SliderRow {
      key: "blurSize"
      label: "Blur strength"
      hint: "Hyprland has one blur size for everything, so this also changes it for windows and other panels. Back to your own value when blur leaves this mode."
      visible: root ? root.blurMode === "on" : false
      minimum: 1
      maximum: 20
      step: 1
      value: root ? (root.blurSize > 0 ? root.blurSize : (panel.currentBlurSize > 0 ? panel.currentBlurSize : 6)) : 6
      onCommitted: function(v) { root.setBlurSize(v, panel.currentBlurSize) }
    }
    SliderRow {
      key: "grain"
      label: "Grain"
      hint: "Film grain over the background. Works on solid, translucent and blurred backgrounds alike."
      minimum: 0
      maximum: 1
      step: 0.05
      displayScale: 100
      suffix: "%"
      value: root ? root.grain : 0
      onCommitted: function(v) { root.setOption("grain", Math.round(v * 100) / 100) }
    }
  }
}
