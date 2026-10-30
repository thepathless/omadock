import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../../DockModel.js" as DockModel

// Logic extracted from Dock.qml: stateless functions, the dock root
// is passed in and owns all state. Bodies are verbatim.

QtObject {
  function applyBlurRule(root, force) {
    if (!root.isPrimary) return
    if (force || root.blurMode !== root._appliedBlurMode) {
      var lua = "if _G.omadock_blur_rule then _G.omadock_blur_rule:set_enabled(false) end"
      if (root.blurMode !== "system") {
        lua += " _G.omadock_blur_rule = hl.layer_rule({ match = { namespace = \"^omadock$\" }, blur = "
          + (root.blurMode === "on" ? "true" : "false") + ", blur_popups = "
          + (root.blurMode === "on" ? "true" : "false") + ", ignore_alpha = 0.05 })"
      }
      Quickshell.execDetached(["hyprctl", "eval", lua])
      root._appliedBlurMode = root.blurMode
    }
    // The size can change while the mode stays the same.
    root.applyBlurSize(force)
    // Layer blur is gated by the compositor's own switch. "on" without it
    // renders a flat panel, which is not what the setting promises.
    root.ensureHyprBlur(force)
  }

  function setHyprBlurEnabled(root, on) {
    Quickshell.execDetached(["hyprctl", "eval",
      "hl.config({ decoration = { blur = { enabled = " + (on ? "true" : "false") + " } } })"])
  }

  // Turn the compositor's blur on while the dock's mode is "on", and put the
  // user's own value back when it leaves. The value is probed once, lazily, so
  // a dock that never asks for blur never touches the setting. What the dock
  // changed is remembered in this session only: this runs from the config load
  // path, and a save here rewrote the whole file from memory - which landed
  // over an edit made outside the dock (a preset apply over a restored config,
  // measured 1 run in 5) and made the dock the last writer of every external
  // change. Nothing on this path writes the config; the flag needs no file.
  function ensureHyprBlur(root, force) {
    if (!root.isPrimary) return
    if (root.blurMode === "on") {
      if (!root._blurProbed) {
        root.probeHyprBlur()
        return
      }
      // Already on: that is the user's own value, so there is nothing for the
      // dock to put back when the look stops asking.
      if (root.systemBlurEnabled) return
      if (force || !root._blurEnabledOverride) {
        root.setHyprBlurEnabled(true)
        root._blurEnabledOverride = true
      }
    } else if (root._blurEnabledOverride) {
      root.setHyprBlurEnabled(root.systemBlurEnabled)
      root._blurEnabledOverride = false
    }
  }

  function setHyprBlurSize(root, size) {
    Quickshell.execDetached(["hyprctl", "eval",
      "hl.config({ decoration = { blur = { size = " + Math.round(size) + " } } })"])
  }

  function applyBlurSize(root, force) {
    if (!root.isPrimary) return
    var want = (root.blurMode === "on" && root.blurSize > 0) ? root.blurSize : 0
    if (!force && want === root._appliedBlurSize) return
    if (want > 0) root.setHyprBlurSize(want)
    else if (root._appliedBlurSize > 0 && root.systemBlurSize > 0) root.setHyprBlurSize(root.systemBlurSize)
    root._appliedBlurSize = want
  }

  // currentSize: Hyprland's blur size right now, read by the settings panel;
  // remembered as the system size the first time the dock overrides it.
  function setBlurSize(root, size, currentSize) {
    if (root.systemBlurSize <= 0 && root._appliedBlurSize <= 0 && currentSize > 0)
      root.systemBlurSize = DockModel.boundSystemBlurSize(currentSize)
    root.blurSize = Math.max(1, Math.min(20, Math.round(size)))
    root.applyBlurSize(false)
    root.saveConfig()
  }

  function setBlurMode(root, mode) {
    root.blurMode = mode
    root.applyBlurRule(false)
    root.saveConfig()
  }

  // Plain value settings from the settings panel: set, persist.
  function setOption(root, key, value) {
    root[key] = value
    root.saveConfig()
  }

  // Leaving "theme" for "custom" starts from the rim's width and opacity, so
  // the lines look the same until changed.
  function setDividerStyle(root, style) {
    if (style === "custom" && root.dividerStyle === "theme") {
      root.dividerWidth = root.borderWidth
      root.dividerOpacity = Math.round(root.rimAlpha * 100) / 100
    }
    root.dividerStyle = style
    root.saveConfig()
  }

  // "theme" dividers follow the rim, so they turn "custom" when it goes
  // away: they keep their look and stay adjustable.
  function setShowBorder(root, show) {
    if (!show && root.dividerStyle === "theme") root.setDividerStyle("custom")
    root.showBorder = show
    root.saveConfig()
  }

  function setDockScreen(root, name) {
    root.screenName = name || ""
    root.saveConfig()
  }

  function setAutohideMode(root, mode) {
    if (mode === "always") {
      root.autohide = false
      root.intelligentAutohide = false
    } else if (mode === "intelligent") {
      root.autohide = true
      root.intelligentAutohide = true
    } else if (mode === "autohide") {
      root.autohide = true
      root.intelligentAutohide = false
    }
    root.saveConfig()
    root.syncVisibility()
  }

  function setDockOpacity(root, val) {
    root.dockOpacity = val
    root.saveConfig()
  }

  function setBorderOpacity(root, val) {
    root.borderOpacity = val
    root.saveConfig()
  }

  function setHoverEffect(root, mode) {
    root.hoverEffect = mode
    root.saveConfig()
  }

  function setDockShape(root, shape) {
    root.dockShape = shape
    root.saveConfig()
  }

  function setDockBgColor(root, col) {
    root.dockBgColor = col
    root.saveConfig()
  }

  function setIconSize(root, sz) {
    root.configuredIconSize = sz
    root.saveConfig()
  }

  function setItemSpacing(root, sp) {
    root.itemSpacing = sp
    root.saveConfig()
  }

  function setUrgentSoundName(root, name) {
    name = DockModel.cleanSoundName(name)
    root.urgentSoundName = name
    root.urgentSound = name !== "none"
    if (name !== "none" && !root.isDndActive) {
      Quickshell.execDetached(["canberra-gtk-play", "-i", name])
    }
    root.saveConfig()
  }
}
