# Omadock (`omadock`)

<p align="center">
  <img src="assets/preview-dock.png" alt="Omadock Preview" width="600" />
</p>

<p align="center">
  <b>A modern, high-performance application dock for <a href="https://omarchy.org">Omarchy</a> (Quickshell + Hyprland).</b>
</p>

<p align="center">
  <a href="https://github.com/thepathless/omadock/releases"><img src="https://img.shields.io/badge/release-v1.4.4-blue?style=flat-square" alt="Release" /></a>
  <a href="https://omarchy.org"><img src="https://img.shields.io/badge/omarchy-shell_plugin-blueviolet?style=flat-square" alt="Omarchy" /></a>
  <a href="https://hyprland.org"><img src="https://img.shields.io/badge/Wayland-Hyprland-00a4dc?style=flat-square" alt="Hyprland" /></a>
  <a href="https://quickshell.org"><img src="https://img.shields.io/badge/Quickshell-Qt6_QML-41cd52?style=flat-square" alt="Quickshell" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License" /></a>
</p>

---

## Overview

**Omadock** is a lightweight, zero-CPU application dock crafted natively for Omarchy. It brings smooth autohide behaviors, intelligent window overlap detection, multi-window cycling via mouse wheel, live drag-and-drop icon reordering, and a deep hierarchical customization suite directly accessible from the dock.

<p align="center">
  <img src="assets/preview-desktop.png" alt="Omadock Desktop Preview" width="900" />
</p>

---

## ⚡ Installation & Management

### Install (Single Command)
Install and enable **Omadock** in Omarchy with a single command:

```bash
omarchy plugin add https://github.com/thepathless/omadock.git --enable --yes
```

### Update
Update to the latest release at any time:

```bash
omarchy plugin update omadock --yes
```

### Removal / Uninstall
To disable and completely remove Omadock from Omarchy:

```bash
omarchy plugin remove omadock --yes
```

---

## ✨ Features

### 🎯 Zero-CPU Reactive Autohide & Tiling Adaptation
- **Scale-Aware Thresholding**: Automatically calculates fractional scaling across HiDPI monitors to detect bottom edge cursor reveal.
- **Intelligent Window Overlap Detection**: Debounced, event-driven Hyprland client inspections with **0% continuous CPU polling**.
- **Tiling Window Adaptation**: When in **Always Show** mode, Omadock sets a Wayland `exclusiveZone`, ensuring tiled Hyprland windows reserve bottom space and never overlap the dock.
- **Click Pass-Through Input Masking**: The trigger reveal zone passes through clicks to underlying desktop applications without swallowing inputs.

### 🎨 Deep Right-Click Customization Suite
Right-click the leftmost Omarchy icon to open the native settings menu:
- **Autohide Modes**:
  - `Always Show` — Stays permanently visible with active window margin reservation.
  - `Intelligent Autohide` — Stays visible on empty workspaces; hides smoothly when windows overlap.
  - `Auto Hide` — Standard edge-reveal dock.
- **Dock Corner Shapes**:
  - `Rounded` — Modern 14px rounded rectangle.
  - `Round` — Full capsule / pill curvature (`height / 2`).
  - `Square` — Sharp minimalist edges (`0px`).
- **Background Opacity**:
  - `Opaque (100%)`
  - `Glass (80%)`
  - `Frosted Glass (65%)`
  - `Translucent (35%)`
  - `Transparent (0%)` *(retains outer card outline border)*
- **Background Color Picker**:
  - `Theme (Default)` — Automatically tracks active Omarchy desktop theme colors (`Color.bar.background`).
  - `No Color` — Clean transparent base fill.
  - `Preset Palette Swatches` — 10 curated colors (Pure Black, Mocha, Deep Slate, Midnight Blue, Dark Navy, Emerald Forest, Espresso, Velvet Ruby, Midnight Purple, Slate Grey).
- **Icon Sizing & Spacing**:
  - Sizes: `Small (28px)`, `Medium (36px)`, `Large (44px)`, `Extra Large (52px)`.
  - Spacing: `Compact (2px)`, `Normal (4px)`, `Relaxed (8px)`.
- **Toggles**:
  - `Show Tooltips` — Toggle hover name tooltips.

### 🪟 Multi-Window Management & Mouse-Wheel Cycling
- **Mouse-Wheel Window Cycling**: Hover over an application with multiple open windows and scroll up or down to cycle focus between instances in real time.
- **Active & Multi-Instance Indicators**: Clean Omarchy-styled dots show running state and active window status.
- **Direct Window Switching**: Right-click any app icon to view open window titles and switch directly to a specific instance or open a new window.

### 🔄 Live Drag-and-Drop Reordering
- Click and drag pinned app icons to rearrange them live.
- Real-time insertion indicator lines guide placement.
- Automatically saves new pin order to `~/.config/omarchy/dock.json`.

---

## ⚙️ Configuration Reference

All settings can be toggled interactively via the right-click menu or configured manually in `~/.config/omarchy/omadock.json`:

```json
{
  "autohide": true,
  "intelligentAutohide": true,
  "showAppsButton": true,
  "showTooltips": true,
  "opacity": 1.0,
  "shape": "rounded",
  "bgColor": "theme",
  "itemSpacing": 4,
  "screen": "",
  "iconSize": 36
}
```

| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `autohide` | `boolean` | `true` | Enable autohide on hover reveal. Set `false` for always-visible dock. |
| `intelligentAutohide` | `boolean` | `true` | Hide dock only when windows on the current workspace overlap its area. |
| `opacity` | `number` | `1.0` | Background transparency (`1.0`, `0.80`, `0.65`, `0.35`, `0.0`). |
| `shape` | `string` | `"rounded"` | Corner shape style (`"rounded"`, `"round"`, or `"square"`). |
| `bgColor` | `string` | `"theme"` | Base color (`"theme"`, `"none"`, or custom hex string e.g. `"#1e1e2e"`). |
| `itemSpacing` | `number` | `4` | Spacing in pixels between icons (`2`, `4`, `8`). |
| `iconSize` | `number` | `0` | Icon size in pixels (`28`, `36`, `44`, `52` or `0` for auto). |
| `showAppsButton` | `boolean` | `true` | Show or hide the Omarchy apps launcher button on the left edge. |
| `showTooltips` | `boolean` | `true` | Show app name tooltips on mouse hover. |
| `screen` | `string` | `""` | Optional monitor name to pin the dock to (defaults to focused monitor). |

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

## ⌨️ Controls & Interactions

| Action | Target | Description |
| :--- | :--- | :--- |
| **Left Click** | Omarchy Icon | Opens Omarchy Application Search Menu |
| **Right Click** | Omarchy Icon | Opens **Omadock Settings** menu |
| **Left Click** | App Icon | Launches app or switches / cycles windows |
| **Mouse Wheel** | App Icon | Cycles forward/backward between open windows |
| **Right Click** | App Icon | Shows open window list, Pin/Unpin, and Close actions |
| **Drag & Drop** | App Icon | Reorders pinned application icons |
| **Bottom Edge Hover** | Screen Bottom | Reveals autohidden dock |

---

## 🛠️ Diagnostics & Validation

To test and hot-reload changes:

```bash
omarchy restart shell
```

Validate plugin manifest schema:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/omadock
```

Inspect live logs:

```bash
journalctl --user -xeu omarchy-shell -n 50
```

---

## 📄 License

Distributed under the [MIT License](LICENSE). Copyright (c) 2026 Suvadeep Mondal.

