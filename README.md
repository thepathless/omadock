# Omadock (`omadock`)

<p align="center">
  <img src="assets/preview-dock.png" alt="Omadock Preview" width="600" />
</p>

<p align="center">
  <b>A modern, high-performance application dock for <a href="https://omarchy.org">Omarchy</a> (Quickshell + Hyprland).</b>
</p>

<p align="center">
  <a href="https://github.com/thepathless/omadock/releases"><img src="https://img.shields.io/badge/release-v2.7.0-blue?style=for-the-badge" alt="Release" /></a>
  <a href="https://omarchy.org"><img src="https://img.shields.io/badge/omarchy-shell_plugin-blueviolet?style=for-the-badge" alt="Omarchy" /></a>
  <a href="https://hyprland.org"><img src="https://img.shields.io/badge/Wayland-Hyprland-00a4dc?style=for-the-badge" alt="Hyprland" /></a>
  <a href="https://quickshell.org"><img src="https://img.shields.io/badge/Quickshell-Qt6_QML-41cd52?style=for-the-badge" alt="Quickshell" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="License" /></a>
</p>

---

## 📖 Overview

**Omadock** is a lightweight, zero-CPU application dock crafted natively for **Omarchy Linux**. It bridges clean, modern aesthetic elegance with the speed and power of the **Hyprland** tiling compositor.

Whether you run a single browser window or tile dozens of terminals across multiple workspaces, Omadock gives you instant visual state feedback, intuitive mouse-wheel window cycling, granular sequential minimization, real-time attention alerts, live drag-and-drop pin reordering, pinned folder stacks, native desktop jump lists, and a deep right-click customization suite.

<p align="center">
  <img src="assets/preview-desktop.png" alt="Omadock Desktop Preview" width="900" />
</p>

---

## ⚡ Quick Start (Single-Command Setup)

### 📥 Install & Enable
Run this single command in your terminal to download, validate, and enable Omadock:

```bash
omarchy plugin add https://github.com/thepathless/omadock.git --enable --yes
```

### 🔄 Update to Latest Release
To pull the newest updates and improvements at any time:

```bash
omarchy plugin update omadock --yes
```

### 🗑️ Uninstall / Remove
To disable and cleanly remove Omadock from your system:

```bash
omarchy plugin remove omadock --yes
```

---

## 🌟 Feature Guide & Architecture

### 🔘 1. The 3-State Window Indicator System
Underneath each running application icon, Omadock draws clean indicator dots that tell you the exact state of every single window at a glance:

```
  ┌─────────────────────────────────────────────────────────────┐
  │  INDICATOR LEGEND:                                          │
  │   [ ▬ ] Active / Focused Window   (Illuminated Theme Bar)   │
  │   [ ● ] Open / Visible Window     (Solid High-Contrast Dot) │
  │   [ ○ ] Minimized / Parked Window (Hollow Circle Ring)      │
  └─────────────────────────────────────────────────────────────┘
```

- **Active Focused Window `[ ▬ ]`**: Expands into an illuminated pill bar in your active theme's accent color so you immediately know which application has your keyboard focus.
- **Open Visible Window `[ ● ]`**: Shows as a crisp solid silver/white circle for every open window sitting on your desktop.
- **Minimized Window `[ ○ ]`**: Instantly turns into a **hollow circle ring** the moment a window is minimized or parked.

---

### 🔢 2. Adaptive Multi-Window Scaling
No matter how many windows or tiled terminals you have open, Omadock's indicators scale intelligently without overflowing the dock or cluttering your screen:

| Window Count | What You See Under the Icon | Description |
| :--- | :--- | :--- |
| **1 to 4 Windows** (e.g. 2x2 tiled grid) | `[ ▬ ] [ ● ] [ ○ ] [ ● ]` | Every window gets its own full-size individual dot or active bar. |
| **5 Windows** | `[ ▬ ] [ ● ] [ ● ] [ ● ] [ ● ]` | Micro-dot compression (`4px` dots) fits 5 instances seamlessly. |
| **6+ Windows** (e.g. 10 windows) | `[ ▬ ] [ ● ] [ ● ] [ ● ] [ +6 ]` | Displays the first 4 window states + a sleek miniature `+N` count badge. |

---

### 🔄 3. Minimize on Click (3 Powerful Modes)
Clicking the dock icon of an application you are currently using can minimize and restore windows according to your personal workflow preference:

```
                         ┌─────────────────────────────────┐
                         │   Click On Focused Dock Icon    │
                         └──────────────┬──────────────────┘
                                        │
             ┌──────────────────────────┼──────────────────────────┐
             ▼                          ▼                          ▼
     [ Active Window ]           [ All Windows ]             [ Disabled ]
  (Sequential / Granular)      (Group Batch / Hide)        (Standard / Classic)
```

1. **🛡️ Active Window (Sequential FIFO — *Default*)**:
   - **Minimizing**: Clicking the focused app minimizes *only that single active window*, immediately passing focus to the next window. You can minimize Window 1, then Window 2, one by one — each landing as a live preview tile on the dock.
   - **Restoring**: Click the window's **preview tile** on the dock to bring back exactly that window (see 4b below).
2. **📦 All Windows (Group Batch / Workplace Clear)**:
   - Clicking minimizes **all open windows of that app simultaneously in 1 click**, clearing your workspace — each window becomes its own preview tile.
   - Bring any of them back individually by clicking its tile, or right-click the app icon for per-window controls.
3. **🚫 Disabled (`off`)**:
   - Clicking an active application never minimizes; it simply cycles focus to the next instance.

> **💡 Intelligent Window Focus & Workspace Navigation**: Left-clicking any running app brings its window to the foreground. If the window is minimized on `special:minimized`, Omadock unminimizes and focuses it instantly; if it resides on another workspace and is unfocused, Omadock smoothly takes you to that workspace and focuses the window.

---

### 📜 4. Interactive Tooltips & Mouse-Wheel Selection
When an app has multiple windows on screen:
1. **Hover your mouse** over the dock icon: A rich tooltip appears listing all its windows (minimized ones live as preview tiles instead — see 4b).
2. **Scroll your mouse wheel up or down**: A glowing cursor (`›`) cycles through the window list live!
3. **Left-click the dock icon**: Omadock will **directly focus that exact chosen window**!

---

### 🪟 4b. Live Minimized-Window Preview Tiles
Minimized windows appear as **live preview tiles** in a dedicated dock section — pinned apps on the left, running unpinned apps on the right, just like macOS:
- Each tile shows a **real snapshot of the window**, with an app badge and full title tooltip on hover.
- **Click a tile** to restore that exact window to its original workspace.
- **Right-click a tile** for **Restore / Close** actions.
- In **All Windows** minimize mode, each app's windows compress into a single stacked group tile (badge shows the count; click restores the whole set).
- Toggle via Settings → **Minimized Window Previews** (or `showMinimizedTiles`).

---

### ⚡ 5. FreeDesktop Desktop Actions (Jump Lists)
Right-click application icons to access native XDG quick actions directly from the context menu:
- **Web Browsers**: Open New Incognito / Private Window.
- **Code Editors & Terminals**: Open New Empty Window or open recent workspaces.
- **Communication Apps**: Start New Chat, Compose Message, or change status.
- **Web Apps & PWAs**: Open in browser or native window modes.

---

### 🗂️ 6. Pinned Folder Stacks & Recent Files
Keep your most important project directories and downloads right at your fingertips:
- **1-Click Popover**: Click any pinned folder (`~/Downloads`, `~/Documents`, `~/Projects`, or custom directories) to reveal a sleek popover of recent files.
- **File Metadata & Type Icons**: Displays clean mimetype icons, file sizes, and relative modification times (`Just now`, `5m ago`, `2h ago`).
- **Direct Launching**: Single-click any file to open it with default desktop applications via `xdg-open`, or click **Open in File Manager** at the bottom.
- **Folder Chooser Integration**: Add any folder easily from Omadock Settings → **Folders & Stacks ›** using a native GTK folder picker.

---

### 🎨 7. Themed Folder Colors & Monochrome Symbolic Outlines
Customise folder icons to seamlessly match your Omarchy theme:
- **Auto Theme Sync**: Automatically adapts folder colors to the active Omarchy theme.
- **Yaru Color Swatches**: Curated presets including Sage, Olive, Magenta, Purple, Blue, Red, and Yellow.
- **Monochrome Symbolic Outlines**: Renders crisp, minimalist monochrome outline glyphs for dark, vantablack, or minimal setups.

---

### 🔔 8. Notification Urgency & Audio Chimes
- When a background application receives an urgent notification or mention (e.g., Slack, Discord, Matrix, WhatsApp), its dock icon **hops and bounces in real-time** with a glowing urgent pulse!
- **Stereo Audio Feedback**: Plays a selectable notification chime (`Message`, `Complete`, `Info`, `Warning`, `Bell`, or `Mute`).
- **Foreground Suppression Invariant**: If you are already actively working inside that window in the foreground, urgency animations are automatically suppressed so they never distract your typing.
- **Omarchy DND Integration**: Fully respects Omarchy's system-wide **Do Not Disturb** mode. When DND is toggled from your top status bar, sound alerts are automatically muted.

---

### 🎨 9. Specular Glassmorphism & Deep Customization
Right-click the leftmost Omarchy icon to open the full visual settings menu:

- **Achromatic Specular Glassmorphism**: Transparent dock mode features a crisp `1.5px` high-contrast specular rim and subtle dark drop shadow, remaining readable over bright white or dark wallpapers alike.
- **Corner Shapes**: `Auto (Theme)`, `Rounded` (modern curves), `Round` (full pill), or `Square` (sharp minimalist).
- **Background Opacity**: `Auto (Theme)`, `100% (Opaque)`, `80% (Glass)`, `65% (Frosted)`, `35% (Translucent)`, or `0% (Transparent)`.
- **Custom Color Swatches**: 10 curated color presets (Pure Black, Mocha, Deep Slate, Midnight Blue, Dark Navy, Emerald Forest, Velvet Ruby, etc.) plus automatic foreground luminance contrast.
- **Icon Sizing & Spacing**: Choose between `Small (28px)`, `Medium (36px)`, `Large (44px)`, or `Extra Large (52px)`, and customize icon gaps (`Compact`, `Normal`, `Relaxed`).
- **Magnification Effects**: Smooth raised-cosine `Wave` hover, single-icon `Zoom` peak, or `Off`.

<p align="center">
  <img src="assets/preview-settings-1.png" alt="Omadock Main Settings" width="180" />
  &nbsp;
  <img src="assets/preview-settings-2.png" alt="Appearance & Opacity" width="220" />
  &nbsp;
  <img src="assets/preview-settings-3.png" alt="Behavior & Minimize Modes" width="180" />
  &nbsp;
  <img src="assets/preview-settings-4.png" alt="Icon Sizing & Gaps" width="180" />
  &nbsp;
  <img src="assets/preview-settings-5.png" alt="Folders & Stacks Settings" width="180" />
</p>

---

### 🎯 10. Zero-CPU Autohide & Tiling Adaptation
- **0.00% Idle CPU**: Uses Hyprland's native IPC event bus — zero polling loops, ensuring maximum battery life.
- **Tiling Window Reservation**: In **Always Show** mode, Omadock sets a Wayland `exclusiveZone` so your tiled Hyprland windows reserve bottom space and never overlap the dock.
- **Intelligent Autohide**: Stays visible on empty workspaces; smoothly slides out of the way only when open windows overlap the dock area.

---

### 🔄 11. Live Drag-and-Drop Pin Reordering
- Click and drag any pinned app icon horizontally along the dock to reorder it.
- A real-time insertion indicator shows the exact drop location.
- Automatically persists your custom pin order across reboots in `~/.config/omarchy/dock.json`.

---

## 🖱️ Master Controls Cheat Sheet

| Action | Target | What Happens |
| :--- | :--- | :--- |
| **Left Click** | Omarchy Icon | Opens the Omarchy Application Search Menu |
| **Right Click** | Omarchy Icon / Dock Space | Opens **Omadock Preferences** menu |
| **Left Click** | App Icon | Launches app, focuses active window, switches workspace, or minimizes/restores |
| **Middle Click** | App Icon | Opens a **new window / instance** of the application |
| **Mouse Wheel Scroll** | App Icon | Cycles focus between open windows or scrolls tooltip/context selector |
| **Right Click** | App Icon | Opens application menu (window list, Desktop Actions, Pin/Unpin, Quit) |
| **Left Click** | Pinned Folder Icon | Toggles the folder's recent files stack popover |
| **Right Click** | Pinned Folder Icon | Opens folder options (Open in File Manager, Unpin Folder) |
| **Click & Drag** | Pinned Icon | Reorders application position live |
| **Bottom Screen Hover** | Screen Bottom Edge | Reveals autohidden dock smoothly |

---

## ⚙️ Configuration Reference

All settings can be adjusted graphically via the right-click menu or edited directly in `~/.config/omarchy/omadock.json`:

```json
{
  "autohide": true,
  "intelligentAutohide": true,
  "minimizeMode": "active",
  "opacity": 1.0,
  "shape": "rounded",
  "bgColor": "theme",
  "itemSpacing": 4,
  "iconSize": 36,
  "hoverEffect": "zoom",
  "showAppsButton": true,
  "showTooltips": true,
  "showUrgentHint": true,
  "urgentSound": true,
  "urgentSoundName": "bell",
  "folderColor": "theme",
  "revealDelay": 160,
  "tooltipDelay": 450,
  "pinnedFolders": [
    { "path": "~/Downloads", "name": "Downloads", "icon": "folder-download" },
    { "path": "~/Documents", "name": "Documents", "icon": "folder-documents" }
  ]
}
```

| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `autohide` | `boolean` | `true` | Enable autohide on hover reveal. Set `false` for always-visible dock. |
| `intelligentAutohide` | `boolean` | `true` | Hide dock only when windows on the current workspace overlap its area. |
| `opacity` | `number \| string` | `1.0` | Background transparency (`"theme"`, `1.0`, `0.80`, `0.65`, `0.35`, `0.0`). |
| `shape` | `string` | `"rounded"` | Corner shape style (`"rounded"`, `"round"`, or `"square"`). |
| `bgColor` | `string` | `"theme"` | Base color (`"theme"`, `"none"`, or custom hex string e.g. `"#1e1e2e"`). |
| `folderColor` | `string` | `"theme"` | Folder icon color mode (`"theme"`, `"symbolic"`, `"white"`, `"black"`, `"Yaru-sage"`, `"Yaru-blue"`, etc.). |
| `itemSpacing` | `number` | `4` | Spacing in pixels between icons (`2`, `4`, `8`). |
| `iconSize` | `number` | `0` | Icon size in pixels (`28`, `36`, `44`, `52` or `0` for auto). |
| `showAppsButton` | `boolean` | `true` | Show or hide the Omarchy button on the left edge: left-click opens the Omarchy menu, scroll switches workspaces, middle-click opens a terminal, right-click opens dock settings. |
| `showTooltips` | `boolean` | `true` | Show app name tooltips on mouse hover. |
| `showMinimizedTiles` | `boolean` | `true` | Show minimized windows as live preview tiles between pinned and running apps; click restores that exact window, right-click offers Restore/Close. |
| `screen` | `string` | `""` | Optional monitor name to pin the dock to (defaults to primary monitor). |
| `hoverEffect` | `string` | `"zoom"` | Hover effect: `"zoom"` (single peak), `"wave"` (raised-cosine falloff), or `"off"`. |
| `clickToMinimize` | `boolean` | legacy | Legacy alias kept for compatibility — derived from `minimizeMode`. Configure `minimizeMode` instead. |
| `minimizeMode` | `string` | `"active"` | Master minimize control: `"active"` (Sequential FIFO), `"all"` (Group Batch), or `"off"` (Disabled). |
| `launchBounce` | `boolean` | `true` | Animate the icon with a launch bounce while an app starts. |
| `advancedTooltips` | `boolean` | `true` | Rich tooltips listing up to 8 windows; scroll to cycle, click to open. |
| `urgentOnNotification` | `boolean` | `true` | Trigger dock urgency when a desktop notification arrives for the app. |
| `showUrgentHint` | `boolean` | `true` | Pulse indicator and icon bounce when an app demands attention. |
| `urgentSound` | `boolean` | `true` | Enable or disable urgency audio chimes (automatically silenced in DND mode). |
| `urgentSoundName` | `string` | `"bell"` | System sound name (`"bell"`, `"message-new-instant"`, `"complete"`, `"dialog-information"`, etc.). |
| `revealDelay` | `number` | `160` | Edge dwell time in ms before autohidden dock reveals. |
| `tooltipDelay` | `number` | `450` | Hover dwell time in ms before rich window tooltips appear. |
| `pinnedFolders` | `array` | `[...]` | List of pinned folder objects (`path`, `name`, `icon`). |

### Keyboard Bindings via IPC
Omadock exposes dock actions to Quickshell's IPC bus, so you can bind them anywhere in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + M", "Minimize focused window", "exec qs ipc call omadock minimizeActive")
o.bind("SUPER + SHIFT + M", "Restore oldest minimized", "exec qs ipc call omadock restoreLast")
```

Available targets: `minimizeActive` (park the focused window), `restoreLast` (bring back the longest-parked window).

### Pinned Applications (`~/.config/omarchy/dock.json`)

```json
{
  "pinned": [
    "foot",
    "org.gnome.Nautilus",
    "google-chrome",
    "code"
  ]
}
```

---

## ❓ Frequently Asked Questions (FAQ)

### Q: How do I pin or unpin an application?
**A:** Open the app, right-click its icon on the dock, and click **Pin to Dock** (or **Unpin from Dock**). You can also drag pinned icons to reorder them!

### Q: Where do minimized windows go?
**A:** Hyprland doesn't have a traditional desktop taskbar, so Omadock parks minimized windows on a dedicated hidden workspace (`special:minimized`). Each parked window shows up as a **live preview tile** in the dock's center-right section — click the tile to restore that exact window to its original workspace. Right-click a tile to close it, or right-click the app icon for its full window list.

### Q: How do I make the dock completely transparent?
**A:** Right-click the Omarchy icon → **Appearance** → **Background Opacity** → Select **Transparent (0%)**. Omadock will render a clean, floating specular glass border around your icons.

### Q: How do I reload the dock after editing config files?
**A:** Run `omarchy restart shell` in your terminal. Quickshell will hot-reload the dock in under 1 second.

---

## 🛠️ Diagnostics & Development

Validate plugin compliance against official Omarchy standards:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/omadock
```

Inspect live compositor logs:

```bash
journalctl --user -xeu omarchy-shell -n 50
```

---

## 📄 License

Distributed under the [MIT License](LICENSE). Copyright (c) 2026 Suvadeep Mondal.


