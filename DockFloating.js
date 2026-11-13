// Which dock a floating workspace gets. Omarchy 4.5 added a floating layout
// (Super+L cycles tiling, scrolling, floating) and its own dock,
// omarchy.dock, which shows only on floating workspaces, over this one.
// "hide-omarchy" switches Omarchy's dock off and keeps omadock everywhere;
// "hide-omadock" switches it back on and hides omadock on floating
// workspaces; "both" leaves Omarchy's dock alone. Plain JS, node-tested like
// the other modules.

var CHOICES = ["hide-omarchy", "hide-omadock", "both"]

function normalizeChoice(value) {
  return CHOICES.indexOf(value) !== -1 ? value : "hide-omarchy"
}

// The value the layout commands write: `mode = "floating"` in <id>.lua
// (omarchy-hyprland-workspace-layout-toggle), `default = "floating"` in
// default.lua (omarchy-hyprland-workspace-layout-default).
var FILE_VALUE = { mode: /mode = "([a-z]+)"/, "default": /default = "([a-z]+)"/ }

function fileValue(text, key) {
  var match = FILE_VALUE[key].exec(String(text || ""))
  return match ? match[1] : ""
}

// Read as omarchy-hyprland-workspace-layout-current does: the workspace's own
// file, else the default. Special and named workspaces (id < 1) keep no mode.
function isFloating(workspaceId, workspaceText, defaultText) {
  if (!(workspaceId >= 1)) return false
  return (fileValue(workspaceText, "mode") || fileValue(defaultText, "default")) === "floating"
}

// Whether the monitor is showing the scratchpad. The dock hides only on a
// positive answer from Hyprland's own monitor state: a missing monitor, a
// missing or malformed ipc object, or any other special workspace reads as
// "closed", so a lost event, a failed refresh or a restarted compositor can
// never leave the dock off screen.
function scratchpadOpen(monitor) {
  var ipc = monitor && monitor.lastIpcObject
  var special = ipc && ipc.specialWorkspace
  var name = special && typeof special.name === "string" ? special.name : ""
  return name === "special:scratchpad" || name === "scratchpad"
}

// The `omarchy plugin` action ("enable" / "disable") that brings omarchy.dock
// in line with the choice, given shell.json's text, or "" when nothing is to
// change: it already matches, the choice is "both", or the text is not a
// config object (unreadable or over its cap), so its state is unknown.
function omarchyDockAction(choice, shellText) {
  if (choice === "both") return ""
  var config = null
  try { config = JSON.parse(shellText) } catch (e) { return "" }
  if (!config || typeof config !== "object" || Array.isArray(config)) return ""
  var disabled = Array.isArray(config.disabledPlugins) && config.disabledPlugins.indexOf("omarchy.dock") !== -1
  if (choice === "hide-omadock") return disabled ? "enable" : ""
  return disabled ? "" : "disable"
}
