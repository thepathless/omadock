import QtQuick
import qs.Commons
import qs.Ui

// Settings page: icon style, tint, grid, contrast and icon size/spacing rows.
// Instantiated by SettingsPanel, which injects root (the Dock, for
// values and setters) and panel (page/edit state).

Column {
  property var root: null
  property var panel: null
  width: parent.width


  SectionLabel { text: "Icons" }

  ChoiceRow {
    key: "iconStyle"
    label: "Icon style"
    hint: "Monochrome and dot matrix take one colour from the theme."
    options: [
      { value: "original", label: "Original" },
      { value: "mono", label: "Monochrome" },
      { value: "pixel", label: "Pixel" },
      { value: "dots", label: "Dot matrix" }
    ]
    value: root ? root.iconStyle : "original"
    onPicked: function(v) { root.setOption("iconStyle", v) }
  }
  ChoiceRow {
    key: "iconTint"
    label: "Icon colour"
    visible: root ? (root.iconStyle === "mono" || root.iconStyle === "dots") : false
    options: [
      { value: "text", label: "Text" },
      { value: "accent", label: "Accent" },
      { value: "bw", label: "B/W" }
    ]
    value: root ? root.iconTint : "text"
    onPicked: function(v) { root.setOption("iconTint", v) }
  }
  SliderRow {
    key: "iconGrid"
    label: root && root.iconStyle === "dots" ? "Dots across" : "Pixels across"
    hint: "Fewer is chunkier."
    visible: root ? (root.iconStyle === "pixel" || root.iconStyle === "dots") : false
    minimum: 8
    maximum: 32
    step: 1
    value: root ? root.iconGrid : 16
    onCommitted: function(v) { root.setOption("iconGrid", Math.round(v)) }
  }
  SliderRow {
    key: "iconContrast"
    label: "Contrast"
    hint: "Separates the symbol from its backdrop; high values flatten icons to a simple, poster-like shape."
    visible: root ? (root.iconStyle === "mono" || root.iconStyle === "dots") : false
    minimum: 0
    maximum: 1
    step: 0.05
    displayScale: 100
    suffix: "%"
    value: root ? root.iconContrast : 0
    onCommitted: function(v) { root.setOption("iconContrast", Math.round(v * 100) / 100) }
  }
  SliderRow {
    key: "iconStrength"
    label: "Strength"
    hint: "How much of the effect covers the original icon."
    visible: root ? (root.iconStyle === "mono" || root.iconStyle === "dots") : false
    minimum: 0
    maximum: 1
    step: 0.05
    displayScale: 100
    suffix: "%"
    value: root ? root.iconStrength : 1
    onCommitted: function(v) { root.setOption("iconStrength", Math.round(v * 100) / 100) }
  }
  SwitchRow {
    key: "iconHoverOriginal"
    label: "Show original on hover"
    hint: "The icon under the pointer drops the style and shows as shipped. Icons in an opened group follow this too."
    visible: root ? root.iconStyle !== "original" : false
    checked: root ? root.iconHoverOriginal : false
    onToggled: root.setOption("iconHoverOriginal", !root.iconHoverOriginal)
  }
  SwitchRow {
    key: "iconHoverReveal"
    label: "Dithered reveal"
    hint: "The original icon appears cell by cell, rising from the bottom, instead of all at once."
    visible: root ? (root.iconHoverOriginal && (root.iconStyle === "mono" || root.iconStyle === "dots")) : false
    checked: root ? root.iconHoverReveal : false
    onToggled: root.setOption("iconHoverReveal", !root.iconHoverReveal)
  }

  SectionLabel { text: "Size & Spacing" }

  SliderRow {
    key: "iconSize"
    label: "Icon size"
    minimum: 24
    maximum: 64
    step: 2
    suffix: " px"
    value: root ? root.iconSize : 36
    onCommitted: function(v) { root.setIconSize(Math.round(v)) }
  }
  SliderRow {
    key: "itemSpacing"
    label: "Spacing"
    hint: "Gap between icons."
    minimum: 0
    maximum: 16
    step: 1
    suffix: " px"
    value: root ? root.itemSpacing : 4
    onCommitted: function(v) { root.setItemSpacing(Math.round(v)) }
  }
}
