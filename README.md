# Omadock (`omadock`)

<p align="center">
  <img src="assets/preview-dock.png" alt="Omadock Preview" width="600" />
</p>

<p align="center">
  <b>A modern, high-performance application dock for <a href="https://omarchy.org">Omarchy</a> (Quickshell + Hyprland).</b>
</p>

<p align="center">
  <a href="https://github.com/thepathless/omadock/releases"><img src="https://img.shields.io/badge/release-v1.5.0-blue?style=for-the-badge" alt="Release" /></a>
  <a href="https://omarchy.org"><img src="https://img.shields.io/badge/omarchy-shell_plugin-blueviolet?style=for-the-badge" alt="Omarchy" /></a>
  <a href="https://hyprland.org"><img src="https://img.shields.io/badge/Wayland-Hyprland-00a4dc?style=for-the-badge" alt="Hyprland" /></a>
  <a href="https://quickshell.org"><img src="https://img.shields.io/badge/Quickshell-Qt6_QML-41cd52?style=for-the-badge" alt="Quickshell" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="License" /></a>
</p>

---

## 📖 Overview

**Omadock** is a lightweight, zero-CPU application dock crafted natively for **Omarchy Linux**. It bridges smooth macOS-like aesthetic elegance with the power and speed of the **Hyprland** tiling compositor.

Whether you run a single browser window or tile dozens of terminals across multiple workspaces, Omadock gives you instant visual state feedback, intuitive mouse-wheel window cycling, granular sequential minimization, real-time attention alerts, live drag-and-drop pin reordering, and a deep right-click customization suite.

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

## 🌟 Beginner's Feature Guide (How It Works)

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
- **Minimized Window `[ ○ ]`**: Instantly turns into a **hollow circle ring** the moment a window is minimized or hidden.

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
  (Sequential / Granular)      (Group Batch / Hide)        (macOS / Classic)
```

1. **🛡️ Active Window (Sequential FIFO — *Default*)**:
   - **Minimizing**: Clicking the focused app minimizes *only that single active window*, immediately passing focus to the next window. You can minimize Window 1, then Window 2, one by one.
   - **Restoring**: Clicking the icon restores your minimized windows chronologically (*Window 1 first, then Window 2*).
2. **📦 All Windows (Group Batch / Workplace Clear)**:
   - Clicking minimizes **all open windows of that app simultaneously in 1 click**, clearing your workspace.
   - Clicking again restores all windows together to their exact previous tiling positions.
3. **🚫 Disabled (`off`)**:
   - Clicking an active application never minimizes; it simply cycles focus to the next instance.

> **💡 How to switch modes**: Right-click the Omarchy launcher logo (or empty dock space) → Click **Minimize On Click** → Choose your preferred mode!

---

### 📜 4. Interactive Tooltips & Mouse-Wheel Selection
When an app has multiple windows open (or some are minimized):
1. **Hover your mouse** over the dock icon: A rich tooltip appears listing all active and minimized windows (`[1] Main — GitHub`, `[2] Settings [minimized]`).
2. **Scroll your mouse wheel up or down**: A glowing cursor (`›`) cycles through the window list live!
3. **Left-click the dock icon**: Omadock will **directly un-minimize and focus that exact chosen window**!

---

### 🔔 5. Notification Urgency & Audio Chimes
- When a background application receives an urgent notification or mention (e.g., Slack, Discord, Matrix, WhatsApp), its dock icon **hops and bounces in real-time** with a glowing urgent pulse!
- **Stereo Audio Feedback**: Plays a selectable notification chime (`Message`, `Complete`, `Info`, `Warning`, `Bell`, or `Mute`).
- **Zero Distraction Invariant**: If you are already actively working inside that window in the foreground, urgency animations are automatically suppressed so they never distract your typing.

---

### 🎨 6. Specular Glassmorphism & Deep Customization
Right-click the leftmost Omarchy icon to open the full visual settings menu:

- **Achromatic Specular Glassmorphism**: Transparent dock mode features a crisp `1.5px` high-contrast specular rim and subtle dark drop shadow, remaining readable over bright white or dark wallpapers alike.
- **Corner Shapes**: `Auto (Theme)`, `Rounded` (modern curves), `Round` (full pill), or `Square` (sharp minimalist).
- **Background Opacity**: `Auto (Theme)`, `100% (Opaque)`, `80% (Glass)`, `65% (Frosted)`, `35% (Translucent)`, or `0% (Transparent)`.
- **Custom Color Swatches**: 10 curated color presets (Pure Black, Mocha, Deep Slate, Midnight Blue, Dark Navy, Emerald Forest, Velvet Ruby, etc.) plus automatic foreground luminance contrast.
- **Icon Sizing & Spacing**: Choose between `Small (28px)`, `Medium (36px)`, `Large (44px)`, or `Extra Large (52px)`, and customize icon gaps (`Compact`, `Normal`, `Relaxed`).
- **Magnification Effects**: Smooth raised-cosine `Wave` hover, single-icon `Zoom` peak, or `Off`.

<p align="center">
  <img src="assets/preview-settings-1.png" alt="Omadock Settings Menu 1" width="220" />
  &nbsp;
  <img src="assets/preview-settings-2.png" alt="Omadock Settings Menu 2" width="260" />
  &nbsp;
  <img src="assets/preview-settings-3.png" alt="Omadock Settings Menu 3" width="215" />
  &nbsp;
  <img src="assets/preview-settings-4.png" alt="Omadock Settings Menu 4" width="215" />
</p>

---

### 🎯 7. Zero-CPU Autohide & Tiling Adaptation
- **0.00% Idle CPU**: Uses Hyprland's native IPC event bus — zero polling loops, ensuring maximum battery life.
- **Tiling Window Reservation**: In **Always Show** mode, Omadock sets a Wayland `exclusiveZone` so your tiled Hyprland windows reserve bottom space and never overlap the dock.
- **Intelligent Autohide**: Stays visible on empty workspaces; smoothly slides out of the way only when open windows overlap the dock area.

---

### 🔄 8. Live Drag-and-Drop Pin Reordering
- Click and drag any pinned app icon horizontally along the dock to reorder it.
- A real-time insertion indicator shows the exact drop location.
- Automatically persists your custom pin order across reboots in `~/.config/omarchy/dock.json`.

---

## 🖱️ Master Controls Cheat Sheet

| Action | Target | What Happens |
| :--- | :--- | :--- |
| **Left Click** | Omarchy Icon | Opens the Omarchy Application Search Menu |
| **Right Click** | Omarchy Icon / Dock Space | Opens **Omadock Preferences** menu |
| **Left Click** | App Icon | Launches app, focuses active window, or minimizes/restores |
| **Middle Click** | App Icon | Opens a **new window / instance** of the application |
| **Mouse Wheel Scroll** | App Icon | Cycles focus between open windows or scrolls tooltip selector |
| **Right Click** | App Icon | Opens application menu (window list, Pin/Unpin, Quit) |
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
  "urgentSoundName": "message-new-instant",
  "revealDelay": 160,
  "tooltipDelay": 450
}
```

| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `autohide` | `boolean` | `true` | Enable autohide on hover reveal. Set `false` for always-visible dock. |
| `intelligentAutohide` | `boolean` | `true` | Hide dock only when windows on the current workspace overlap its area. |
| `opacity` | `number \| string` | `1.0` | Background transparency (`"theme"`, `1.0`, `0.80`, `0.65`, `0.35`, `0.0`). |
| `shape` | `string` | `"rounded"` | Corner shape style (`"rounded"`, `"round"`, or `"square"`). |
| `bgColor` | `string` | `"theme"` | Base color (`"theme"`, `"none"`, or custom hex string e.g. `"#1e1e2e"`). A custom hex value also switches dock glyphs and indicators to whichever side reads against it. |
| `itemSpacing` | `number` | `4` | Spacing in pixels between icons (`2`, `4`, `8`). |
| `iconSize` | `number` | `0` | Icon size in pixels (`28`, `36`, `44`, `52` or `0` for auto). |
| `showAppsButton` | `boolean` | `true` | Show or hide the Omarchy apps launcher button on the left edge. |
| `showTooltips` | `boolean` | `true` | Show app name tooltips on mouse hover. |
| `screen` | `string` | `""` | Optional monitor name to pin the dock to (defaults to the first monitor). |
| `hoverEffect` | `string` | `"zoom"` | Hover growth: `"zoom"` grows only the icon under the pointer and leaves the layout still, `"wave"` runs a raised-cosine falloff across neighbours and lets the row carry the extra width, `"off"` disables it. |
| `clickToMinimize` | `boolean` | `false` | Clicking the focused single-window app parks it on a hidden `special:minimized` workspace; clicking again restores it. |
| `showUrgentHint` | `boolean` | `true` | Pulse the indicator and icon ring when a window demands attention. |
| `revealDelay` | `number` | `160` | Milliseconds the pointer must dwell on the screen edge before an autohidden dock reveals. `0` reveals immediately. |
| `tooltipDelay` | `number` | `450` | Milliseconds of hover before a tooltip appears. `0` shows it immediately. |

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
**A:** Hyprland doesn't have a traditional desktop taskbar, so Omadock parks minimized windows on a dedicated hidden workspace (`special:minimized`). When you click the dock icon, Omadock brings the window back to your active workspace in its exact original dimensions.

### Q: How do I make the dock completely transparent?
**A:** Right-click the Omarchy icon → **Appearance** → **Background Opacity** → Select **Transparent (0%)**. Omadock will render a clean, floating specular glass border around your icons.

### Q: How do I reload the dock after editing config files?
**A:** Run `omarchy restart shell` in your terminal. Quickshell will hot-reload the dock in under 1 second.

---

## 🛠️ Diagnostics & Development

Validate plugin compliance against official Omarchy Quattro standards:

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

