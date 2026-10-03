<div align="center">

# ❖ OMADOCK ・ オマドック

### *A modern, fluid, zero-CPU application dock engineered for Omarchy Linux*

[![Release](https://img.shields.io/github/v/release/thepathless/omadock?style=for-the-badge&logo=github&logoColor=white&labelColor=1e1e2e&color=6c7086)](https://github.com/thepathless/omadock/releases)
[![CI](https://github.com/thepathless/omadock/actions/workflows/ci.yml/badge.svg)](https://github.com/thepathless/omadock/actions/workflows/ci.yml)
[![Omarchy](https://img.shields.io/badge/omarchy-4.0.3+-cba6f7?style=for-the-badge&logo=archlinux&logoColor=white&labelColor=1e1e2e)](https://omarchy.org)
[![Hyprland](https://img.shields.io/badge/compositor-Hyprland-89b4fa?style=for-the-badge&logo=wayland&logoColor=white&labelColor=1e1e2e)](https://hyprland.org)
[![Quickshell](https://img.shields.io/badge/shell-Quickshell_Qt6-a6e3a1?style=for-the-badge&logo=qt&logoColor=white&labelColor=1e1e2e)](https://quickshell.org)
[![License](https://img.shields.io/badge/license-MIT-fab387?style=for-the-badge&labelColor=1e1e2e)](LICENSE)

<br />

<p align="center">
  <img src="assets/preview-desktop.png" alt="Omadock on Omarchy Desktop" width="880" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.4);" />
</p>

<p align="center">
  <a href="#-quick-start"><b>Quick Start</b></a> •
  <a href="#-core-features"><b>Features</b></a> •
  <a href="#-minimized-preview-tiles"><b>Preview Tiles</b></a> •
  <a href="#-customization--theming"><b>Theming</b></a> •
  <a href="#%EF%B8%8F-controls-cheat-sheet"><b>Controls</b></a> •
  <a href="#%EF%B8%8F-configuration-reference"><b>Configuration</b></a> •
  <a href="#-keyboard-shortcuts-via-ipc"><b>Keybindings</b></a> •
  <a href="#-faq"><b>FAQ</b></a> •
  <a href="#support-the-project"><b>Support</b></a>
</p>

</div>

---

## ❤️ Support the project

Omadock is built by **[thepathless](https://github.com/thepathless)**, a medical student in India who codes between classes and clinics. It's free, and it always will be — but building it costs money I don't quite have: monthly AI coding tokens, and a laptop that's falling apart (dead WiFi, sticky keys, a trackpad with a mind of its own) — so I'm saving for a **[Dell XPS 13 (2026)](https://www.dell.com/en-us/blog/year-of-the-linux-laptop-omarchy-on-xps/)**.

If Omadock earns a place on your desktop, [**sponsoring me**](https://github.com/sponsors/thepathless) keeps the AI lights on and the laptop fund growing. Every supporter is honored on the [**supporters wall**](SPONSORS.md) 💝 — with love, no tiers, no perks.

<p align="center">
  <a href="https://github.com/sponsors/thepathless"><img src="https://img.shields.io/badge/Sponsor_%E2%9D%A4%EF%B8%8F-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor ❤️ on GitHub" /></a>
</p>

### 💻 Laptop fund

<img src="assets/laptop-fund.svg" alt="Laptop fund: $0 of $1,000" width="480" />

### 📊 Where donations went

| Month | AI tokens | Laptop fund | Notes |
| :--- | :--- | :--- | :--- |
| — | — | — | Just launched — be the first! 🙏 |

*(running total so far: **−₹499** for my coding-agent subscription — borrowed from my mom 😅. Updated monthly; honesty is the least I can offer)*

**Freebuff wallet (2026-10-03):** OmaDock creator [thepathless](https://github.com/thepathless) reports adding **₹1,000 to their Freebuff wallet** to fund continued development.

To everyone who donates — really, truly, thank you. 🙏

---

## ⚡ Overview

**Omadock (オマドック)** is a fluid, zero-CPU application dock for **[Omarchy](https://omarchy.org/)** — Arch, Hyprland, Quickshell.

Crafted in the spirit of **Omakase (おまかせ)**: wave magnification, live window previews, app groups, multi-monitor docks. Beautiful, opinionated, and strictly **0.00% background CPU**.

<p align="center">
  <img src="assets/screenshot-transparent.png" alt="Omadock Close-up View" width="700" />
</p>

### ✨ Key Highlights

- **🌊 Wave magnification** — cosine-falloff dock physics, or classic zoom. Zero coordinate jumping.
- **🪟 Live window previews** — minimized windows park on the dock as thumbnail cards.
- **🔘 3-state window dots** — active, visible, and minimized at a glance.
- **📁 Folders & groups** — folder stacks with recent files, smart app collections, drag-to-group.
- **🖥️ Multi-monitor** — one dock per monitor, each showing its own monitor's windows.
- **💾 Removable media** — USB drives dock themselves; safe eject included.
- **🔔 Attention glow & chimes** — bouncing alerts and audio pings.
- **🔴 Pinned notification badges** — counts matching active popups on pinned apps; dismiss or expire a popup to clear it. These are not unread-message counts.
- **🖥️ CLI app identity** — Antigravity and btop keep their own icons when launched in a terminal; the terminal icon is only a fallback.
- **⌨️ Keybindings & IPC** — wired for `~/.config/hypr/bindings.lua` out of the box.

---

## 🚀 Quick Start

### Install

```bash
omarchy plugin add https://github.com/thepathless/omadock.git --enable --yes
```

### Update

```bash
omarchy plugin update omadock --yes
```

### Removal / Uninstall

```bash
omarchy plugin remove omadock --yes
```

---

## 🌟 Core Features

### 🔘 1. 3-State Window Indicators

Every icon shows all its windows at a glance: **▬** active · **●** open · **○** minimized.

| Window Count | Indicator Visual | Behavior |
| :--- | :--- | :--- |
| **1–4 windows** | `[ ▬ ] [ ● ] [ ○ ] [ ● ]` | Dedicated indicator dot/bar for every individual window. |
| **5 windows** | `[ ▬ ] [ ● ] [ ● ] [ ● ] [ ● ]` | Micro-dot scaling ($4\text{px}$) fits up to 5 instances cleanly. |
| **6+ windows** | `[ ▬ ] [ ● ] [ ● ] [ ● ] [ +N ]` | First 4 instance dots plus a compact `+N` count badge. |

---

### 🪟 2. Minimized Preview Tiles

When a window is parked on `special:minimized`, Omadock generates a live visual preview tile between your pinned and running applications:

<div align="center">
  <img src="assets/preview-dock.png" alt="Omadock Preview Tiles" width="700" style="border-radius: 8px;" />
</div>

- **📸→🖱️** Thumbnails appear on minimize; **left-click restores** to the active workspace.
- **📍** Right-click a tile: *Restore Here*, *Restore to Original Workspace*, or *Close*.
- **📦** In `"all"` mode, same-app windows stack into one card with a count badge.
- **🧩** Unpinned apps collapse into their tile — the dock stays uncluttered.

**Window previews in tooltips.** Hovering an app shows thumbnails of its
windows, including ones minimized to the dock's hidden workspace. They are
captured into GPU memory only while the tooltip is open and are never
written to disk. Turn them off in Settings → Behavior → Window previews.

---

### 🔄 3. Minimize on Click Modes

Configure how clicking a focused app icon behaves (`omadock.json` or the Settings menu):

1. **`"active"` (Default)**: Minimizes the active window and passes focus to the next instance.
2. **`"all"` (Group Batch)**: Simultaneously minimizes all instances of the application in an atomic batch.
3. **`"off"` (Disabled)**: Keeps all windows visible and cycles focus between open instances.

---

### 🌊 4. Magnification & Hover Effects

Juan Pablo Zamora's raised-cosine falloff magnification, plus shader hover effects — all six modes in `hoverEffect`:

$$\text{scale}(d) = 1 + (\text{peak} - 1) \cdot \frac{1 + \cos\left(\frac{\pi \cdot d}{R}\right)}{2} \quad \text{for } d \le R$$

- **`"wave"`** — the dock ripples under the cursor; zero feedback drift.
- **`"zoom"`** — only the hovered icon grows.
- **`"lift"`** — the hovered icon rises off the dock.
- **`"glow"`** — the hovered icon blooms with light.
- **`"glitch"`** — a shader-driven chromatic tear on hover.
- **`"off"`** — calm, static geometry.

With an icon style active, `iconHoverOriginal` shows the hovered icon as shipped, and `iconHoverReveal` dissolves it back in as a dithered reveal instead of a hard switch.

---

### 📁 5. Pinned Folder Stacks & File Popovers

Pin directories like `~/Downloads`, `~/Projects`, or custom paths directly to your dock:

- **Files popover** — up to 300 entries with icons, sizes, and relative times.
- **View As** — right-click the folder: *Stack* (a list) or *Folder* (a grid of larger icons, with previews for images and for anything your file manager has already thumbnailed), saved per folder.
- **Browse** — click a subfolder to step into it, **‹** to go back; long folders scroll.
- **Sort By** — right-click the folder: Name, Kind, Date Modified, Date Added or Size, saved per folder.
- **Direct opening** — click any file to open it in its default app (`xdg-open`), or jump to its folder.
- **Drag out** — drag a file from the popover into a file manager, browser or chat app.
- **Drop in** — rest a folder from your file manager over the folder section of the dock for a moment, then drop it to pin it (dropping on an app icon opens it with that app instead).
- **Folder picker** — attach custom folders from Settings through the desktop's file chooser (`omarchy-file-select` / XDG portal).

---

### 📁 6. App Group Folders (Smart Collections)

Organize applications into intelligent macOS / iOS-style folders directly on your dock:

- **2×2 live preview grid** with window dots; the popover tray scales 2–4 columns.
- **Drag-to-group, drag-to-pin** — drop one icon on another to make a folder.
- **Inline renaming**, saved instantly.
- **Drag-out extraction** — folders auto-dissolve when one app remains.

---

### 💾 7. Removable Media Auto-Docking

Zero-CPU hardware integration for removable media and USB storage:

- **udev + udisks2** detection of USB drives, SD cards, and external storage.
- **Tooltips** with capacity, label, and mount status; safe eject/unmount with notifications.

---

### 📐 8. Dock Alignment Options

Flexible screen placement tailored to your workflow:

- **`"center"`, `"left"`, `"right"`** along the bottom edge, with smooth cubic transitions.
- **Popovers, tooltips, and menus** self-reposition so nothing clips at screen edges.

#### 🖥️ Multi-Monitor Docks

Enable **Settings → Placement & Alignment → Show on All Monitors** (or `"multiMonitor": true`) to run a dock on every connected monitor:

- **Per-monitor apps** — each dock lists its own monitor's windows (pinned apps everywhere); `"perMonitorApps": false` mirrors everything.
- **Minimized tiles follow their origin** monitor, whichever dock parked them.
- **Hotplug aware**; keybinds act on the focused monitor first.

---

### ⚡ 9. FreeDesktop Jump Lists & Zero-CPU Autohide

Deep Linux desktop and compositor integration:

- **FreeDesktop jump lists** — native quick actions straight from `.desktop` files.
- **Drop files on apps** — drag files (or a folder) onto an app icon to open them with it; the icon lights up only when the app declares their types (`MimeType=` in its desktop entry).
- **Media controls** — right-click an app that plays media (Spotify, a browser playing a video…) for *Now Playing* with previous / play-pause / next, through MPRIS.
- **Intelligent autohide** — 2D AABB overlap tests on Hyprland events only. **0.00% CPU**, always.

---

### 🔔 10. Notification Badges & CLI App Identity

- Pinned icons show a badge counting **matching active notification popups** — the count clears as soon as the popup leaves the stack (dismissed, expired, or replaced). These are not unread-message counts.
- Terminal-launched apps know who they are: **Antigravity** (`agy`) and **btop** keep their own product icons; the terminal's icon is only a fallback for unknown CLI tools.

---

### 🗂 11. Window Preview Cards & Smooth Tooltips

- Hovering an app with several windows shows them as a **card stack of live thumbnails** in the tooltip; the wheel browses the stack (paced by `wheelStepDelay`), a click raises the chosen window.
- Tooltips fade in with a small rise, linger 200 ms after the pointer leaves, and cross-fade from icon to icon along the dock — no re-dwelling as you move.
- Menus, folder stacks, app groups and tooltips live in their own focus-grabbing popup windows while the dock layer hugs the card — dock VRAM cost drops from 194 MiB to 26 MiB.

---

## 🎨 Customization & Theming

Right-click the Omarchy logo or empty dock space to access deep customization.

### 🎛️ Settings Panel

Right-clicking either one opens the full settings panel directly: a sidebar with *Appearance*, *Placement*, *Behavior*, *Effects*, *Size & Spacing*, *Presets*, *Folders* and *App Groups*, with switches, sliders and dropdowns for every option. Changes apply live, so the dock underneath previews them. Close it with <kbd>Esc</kbd>, the close button, or a click outside. The panel can also be opened from a keybind: `omarchy-shell omadock openSettings`.

The settings at a glance:

<div align="center">
  <table>
    <tr>
      <th align="center" width="25%">Settings Menu</th>
      <th align="center" width="25%">Appearance</th>
      <th align="center" width="25%">Placement & Alignment</th>
      <th align="center" width="25%">Behavior & Windows</th>
    </tr>
    <tr>
      <td align="center" valign="top"><img src="assets/preview-settings-1.png" width="200" alt="Main Settings Menu" /></td>
      <td align="center" valign="top"><img src="assets/preview-settings-2.png" width="200" alt="Appearance Settings" /></td>
      <td align="center" valign="top"><img src="assets/preview-settings-3.png" width="200" alt="Placement & Alignment Settings" /></td>
      <td align="center" valign="top"><img src="assets/preview-settings-4.png" width="200" alt="Behavior & Windows Settings" /></td>
    </tr>
    <tr>
      <th align="center" width="25%">Effects & Animations</th>
      <th align="center" width="25%">Size & Spacing</th>
      <th align="center" width="25%">Folders & Stacks</th>
      <th align="center" width="25%">App Folders & Groups</th>
    </tr>
    <tr>
      <td align="center" valign="top"><img src="assets/preview-settings-5.png" width="200" alt="Effects & Animations Settings" /></td>
      <td align="center" valign="top"><img src="assets/preview-settings-6.png" width="200" alt="Size & Spacing Settings" /></td>
      <td align="center" valign="top"><img src="assets/preview-settings-7.png" width="200" alt="Folders & Stacks Settings" /></td>
      <td align="center" valign="top"><img src="assets/preview-settings-8.png" width="200" alt="App Folders & Groups Settings" /></td>
    </tr>
  </table>
</div>

- **Shapes**: `Auto (Theme)`, `Rounded`, `Round (Pill)`, `Square`.
- **Opacity**: `Auto (Theme)`, `100%`, `80%`, `65%`, `35%`, `0% (Transparent Specular)`.
- **Placement & Alignment**: `Center (Default)`, `Left Aligned`, `Right Aligned` along the screen edge.
- **Color Presets**: Theme Auto, Pure Black, Mocha, Deep Slate, Midnight Blue, Dark Navy, Emerald Forest, Velvet Ruby.
- **Icon Sizing**: Small ($28\text{px}$), Medium ($36\text{px}$), Large ($44\text{px}$), Extra Large ($52\text{px}$).
- **App Folders & Groups**: Automatic smart collections from running apps, drag-to-group, in-place title renaming, and column scaling.

---

### 🎨 Presets

*Settings → Presets* saves the current look (background, effects, border, dividers, icons, size and spacing) as a named preset, up to six, each with a small live thumbnail. Apply, update, rename or delete them there, or switch from the dock's right-click menu (*Presets ›*). Presets are kept in `omadock.json` under `presets`. A keybind can apply one by name:

```bash
omarchy-shell omadock applyPreset "Night"
```

## 🖱️ Controls Cheat Sheet

| Gesture / Trigger | Target | Action Executed |
| :--- | :--- | :--- |
| **Left Click** | ❖ Omarchy Logo | Opens Omarchy Application Launcher |
| **Right Click** | ❖ Omarchy Logo | Opens Omadock Preferences Menu |
| **Middle Click** | ❖ Omarchy Logo | Spawns default terminal emulator |
| **Left Click** | Application Icon | Launches app / focuses / restores window |
| **Middle Click** | Application Icon | Launches a **new instance** of the application |
| **Scroll Wheel** | Application Icon | Flips through the app's windows in its tooltip; a click focuses the chosen one |
| **Right Click** | Application Icon | Context menu (Window list, Desktop Actions, Pin, Close) |
| **Left Click** | Folder Stack | Toggles recent-files popover |
| **Right Click** | Folder Stack | Folder options (Open in File Manager, Unpin) |
| **Left Click** | Preview Tile | Restores window to current workspace |
| **Right Click** | Preview Tile | Restore Here / Restore to Original / Close |
| **Drag & Drop** | Pinned Icon | Reorders pinned application position live |
| **Drag & Drop** | Running App | Drag into pinned section to pin live |
| **Drag & Drop** | Dock App Icon | Drag onto another pinned app to create a folder |
| **Left Click** | App Group Folder | Toggles folder popover tray |
| **Right Click** | App Group Folder | Context menu (Rename, Ungroup, Set Columns) |
| **Drag & Drop** | App in Folder | Drag out onto dock to extract / unpin |
| **Left Click** | Removable Drive | Opens drive mountpoint in default file manager |
| **Right Click** | Removable Drive | Context menu to safely eject and unmount |
| **Bottom Edge Hover** | Screen Edge | Reveals autohidden dock instantly |

---

## ⚙️ Configuration Reference

Settings persist in `~/.config/omarchy/omadock.json` and are editable live:

<details open>
<summary><b>View Annotated Configuration Schema</b></summary>
<br />

```json
{
  "alignment": "center",
  "autohide": true,
  "intelligentAutohide": true,
  "showRemovableDrives": true,
  "warnUnsafeRemoval": true,
  "minimizeMode": "active",
  "clickToMinimize": true,
  "showMinimizedTiles": true,
  "opacity": 1.0,
  "shape": "rounded",
  "cornerRadius": -1,
  "bgColor": "theme",
  "showBackground": true,
  "showShadow": true,
  "showBorder": true,
  "borderOpacity": "theme",
  "groupStyle": "rounded",
  "itemSpacing": 4,
  "splitSections": false,
  "sectionSpacing": 18,
  "dividerGeometry": "classic",
  "dividerHeight": 70,
  "dividerStyle": "simple",
  "dividerWidth": 1.5,
  "dividerOpacity": 0.4,
  "iconSize": 0,
  "hoverEffect": "zoom",
  "keepPointer": true,
  "wheelStepDelay": 150,
  "iconHoverReveal": false,
  "showAppsButton": true,
  "showTooltips": true,
  "advancedTooltips": true,
  "launchBounce": true,
  "showUrgentHint": true,
  "urgentOnNotification": true,
  "showNotificationBadges": true,
  "urgentSound": true,
  "urgentSoundName": "bell",
  "folderColor": "theme",
  "revealDelay": 160,
  "tooltipDelay": 450,
  "pinnedFolders": [
    { "path": "~/Downloads", "name": "Downloads", "icon": "folder-download" }
  ],
  "appGroups": [
    { "id": "browsers", "name": "browsers", "apps": ["google-chrome", "brave-browser", "chromium", "firefox", "zen-browser"] }
  ]
}
```

</details>

<br />

| Key | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `alignment` | `string` | `"center"` | Dock placement along screen edge: `"center"`, `"left"`, `"right"`. |
| `screen` | `string` | first monitor | Monitor for the single dock (e.g. `"DP-3"`). With `multiMonitor`, the dock on this monitor plays alert sounds. |
| `multiMonitor` | `bool` | `false` | Runs one dock on every connected monitor. |
| `perMonitorApps` | `bool` | `true` | With `multiMonitor`, each dock lists only the windows on its own monitor. |
| `autohide` | `bool` | `true` | Enables dock autohiding on hover exit. |
| `intelligentAutohide` | `bool` | `true` | Hides dock only when windows overlap its bounding box (AABB). |
| `showRemovableDrives` | `bool` | `true` | Auto-detect and display removable USB thumb drives and storage. |
| `warnUnsafeRemoval` | `bool` | `true` | Notify when a drive is pulled out while still mounted (it was not ejected first). |
| `appGroups` | `array` | `[]` | App Folders / Groups configuration (name, custom icon, app ID list). |
| `groupStyle` | `string` | `"rounded"` | Group tile frame: `"rounded"` (softly rounded rim), `"square"` (rim without rounding) or `"none"` (icons only). |
| `groupIconEffects` | `string` | `"theme"` | Icons in an opened group: `"theme"` follows `iconStyle`, `"none"` keeps them original. The tile on the dock always follows `iconStyle`. |
| `minimizeMode` | `string` | `"active"` | `"active"` (FIFO single), `"all"` (batch group), `"off"` (disabled). |
| `clickToMinimize` | `bool` | derived | Legacy mirror of `minimizeMode !== "off"` for older configs; set `minimizeMode` instead. |
| `showMinimizedTiles` | `bool` | `true` | Displays live screencopy preview tiles for parked windows. |
| `opacity` | `number \| str` | `1.0` | Background opacity: `"theme"`, `1.0`, `0.80`, `0.65`, `0.35`, `0.0`. |
| `shape` | `string` | `"rounded"` | Dock geometry: `"rounded"`, `"round"` (pill), `"square"`, `"theme"`. |
| `cornerRadius` | `number` | `-1` | `-1` follows the shape's natural radius; `≥ 0` pins a pixel radius. |
| `indicatorShape` | `string` | `"theme"` | Dots and bars under icons: `"theme"` (follows `shape`), `"rounded"` or `"square"`. |
| `bgColor` | `string` | `"theme"` | `"theme"`, `"none"`, or custom hex string (`"#1e1e2e"`). |
| `showBackground` | `bool` | `true` | Draws the dock's background fill. `false` leaves the icons floating. |
| `showShadow` | `bool` | `true` | Draws the soft drop shadow under the dock. |
| `showBorder` | `bool` | `true` | Draws the rim around the dock. |
| `borderWidth` | `number` | `1.5` | Rim width in pixels, `1`–`6`. |
| `bgFill` | `string` | `"solid"` | Background fill: `"solid"` (`bgColor`) or `"gradient"`. |
| `gradientPreset` | `string` | `"theme"` | Gradient palette: `"theme"` (accent plus two theme palette colours) or `aurora`, `sunset`, `ocean`, `forest`, `rose`, `lavender`, `ember`, `citrus`, `mono`. |
| `gradientStrength` | `number` | `0.6` | How strongly the gradient colours cover the theme background, `0`–`1`. |
| `grain` | `number` | `0` | Film grain over the background, `0` (off) – `1`. |
| `shadowStrength` | `number` | `0.4` | Shadow opacity, `0.0`–`1.0`. |
| `blur` | `string` | `"system"` | Blur behind the dock: `"system"` (your Hyprland layer rules decide), `"on"` or `"off"` (a runtime layer rule overrides them). |
| `blurSize` | `int` | unset | With `blur: "on"`, Hyprland's blur size `1`–`20`. Hyprland has one blur size for everything, so this applies globally; the previous value (`systemBlurSize`, recorded automatically) comes back when blur leaves `"on"`. |
| `iconStyle` | `string` | `"original"` | `"original"`, `"mono"` (one theme colour, shading kept), `"pixel"` (coarse grid, unsmoothed) or `"dots"` (dithered dot matrix). |
| `iconTint` | `string` | `"text"` | Colour for `mono` and `dots`: the dock's `"text"` colour, the theme `"accent"`, or `"bw"` (near black or near white, whichever contrasts more with the background). Text and accent are lightened or darkened when they would not stand out from the background. |
| `iconGrid` | `int` | `16` | Pixels / dots across an icon for `pixel` and `dots` (`8`–`32`). |
| `iconContrast` | `number` | `0` | `mono` / `dots`: adaptive contrast `0`–`1`, stretched around each icon's own average; high values flatten icons to a simple shape. |
| `iconStrength` | `number` | `1` | `mono` / `dots`: how much of the effect covers the original icon, `0`–`1`. |
| `iconHoverOriginal` | `bool` | `false` | With an icon style on, the hovered icon (dock, group tiles, an opened group) shows as shipped. |
| `iconHoverReveal` | `bool` | `false` | With `iconHoverOriginal`, hover dissolves the original icon back in as a dithered reveal instead of a hard switch. |
| `keepPointer` | `bool` | `true` | Focusing a window from the dock keeps the pointer where it is instead of warping it to the window centre. |
| `folderColor` | `string` | `"theme"` | `"theme"`, `"symbolic"`, `"white"`, `"black"`, `"Yaru-blue"`, etc. |
| `hoverEffect` | `string` | `"zoom"` | Hover mode: magnification `"zoom"` or `"wave"`; effects `"lift"`, `"glow"`, `"glitch"` (shaders); or `"off"`. |
| `dividerGeometry` | `string` | `"classic"` | Section divider length: `"classic"` keeps the original short lines; `"long"` uses the adjustable `dividerHeight` share. |
| `showNotificationBadges` | `bool` | `true` | Count matching active popups on pinned icons (not unread messages); cleared when the notification leaves the popup stack. |
| `revealDelay` | `int` | `160` | Edge dwell time in milliseconds before unhiding ($0$–$2000$). |
| `tooltipDelay` | `int` | `450` | Tooltip hover dwell delay in milliseconds ($0$–$5000$). |
| `wheelStepDelay` | `int` | `150` | Minimum milliseconds between accepted wheel steps while browsing an app's windows ($0$–$1000$). |
| `splitSections` | `bool` | `false` | Splits pinned apps, running apps and folders into separate sections divided by the `divider*` settings. |
| `sectionSpacing` | `number` | `18` | Gap between sections in pixels ($0$–$48$). |

---

## ⌨️ Keyboard Shortcuts via IPC

Omadock registers IPC commands callable directly by Quickshell.

### Automated Setup (Recommended)
Run the bundled keybinding helper script to automatically configure all shortcuts:
```bash
~/.config/omarchy/plugins/omadock/scripts/bind-keys.sh
```

### Manual Setup
Add these keybinds to `~/.config/hypr/bindings.lua`:

```lua
-- Toggle Dock Visibility
o.bind("SUPER + D", "Toggle Omadock", "exec qs -p /usr/share/omarchy/shell ipc call omadock toggleVisibility")

-- Minimize currently focused window to Omadock
o.bind("SUPER + M", "Minimize focused window", "exec qs -p /usr/share/omarchy/shell ipc call omadock minimizeActive")

-- Restore longest-parked window (FIFO)
hl.unbind("SUPER + SHIFT + M")
o.bind("SUPER + SHIFT + M", "Restore oldest minimized", "exec qs -p /usr/share/omarchy/shell ipc call omadock restoreLast")
```

Additional IPC methods available:
- `reveal`: Force dock to slide into view.
- `hide`: Force dock to slide out of view.
- `setAlignment("center" | "left" | "right")`: Change dock alignment dynamically.
- `setPosition("bottom" | "top" | "left" | "right")`: Change dock edge position.
- `openSettings`: Open the settings panel on the focused monitor's dock.
- `openSettingsPage("appearance" | "placement" | "behavior" | "effects" | "size" | "folders" | "groups" | "presets" | "about")`: Open the settings panel on a given page.
- `closeSettings`: Close the settings panel.

> [!NOTE]
> The `-p /usr/share/omarchy/shell` flag is mandatory to target the active Omarchy system shell instance.

---

## ❓ FAQ

<details>
<summary><b>Where are minimized windows stored?</b></summary>
<br />
Windows are placed onto Hyprland's hidden <code>special:minimized</code> workspace. Omadock remembers their origin workspace so you can restore them instantly to where they belong.
</details>

<details>
<summary><b>How do I pin or unpin applications?</b></summary>
<br />
Right-click any running application icon and click <b>Pin to Dock</b>. Pinned applications are stored in <code>~/.config/omarchy/dock.json</code>. You can drag and drop icons along the dock to reorder them live.
</details>

<details>
<summary><b>How do I make the dock completely transparent?</b></summary>
<br />
Right-click the Omarchy logo → <b>Appearance</b> → <b>Background Opacity</b> → <b>Transparent (0%)</b>. The dock renders a clean specular border around the active icons.
</details>

<details>
<summary><b>How do I reload after manual JSON edits?</b></summary>
<br />
Run <code>omarchy restart shell</code> in your terminal to instantly reload the Quickshell engine.
</details>

---

## 🛠️ Diagnostics & Validation

Every pull request runs the test suites, a QML syntax gate and the manifest schema check in CI.

```bash
# Validate manifest compliance against Omarchy 4.0.3+ standards
omarchy plugin validate ~/Projects/omadock

# Same manifest gate CI runs (a faithful mirror of the command above)
./tests/manifest-check.sh .

# Test suites (Node: model + perf + hardening; Python: script helpers)
node --check DockModel.js
node --test tests/unit/*.test.js tests/unit/*.test.mjs
python3 -m unittest discover -s tests/unit -p 'test_*.py'

# Load-time smoke test (probes the running shell)
./tests/smoke-test.sh

# Inspect live compositor journal logs
journalctl --user -xeu omarchy-shell -n 50 --no-pager

# Smoke test IPC integration
qs -p /usr/share/omarchy/shell ipc call omadock minimizeActive
qs -p /usr/share/omarchy/shell ipc call omadock restoreLast
```

---

## 🗂 Repository Layout

| Path | What it is |
| :--- | :--- |
| `Dock.qml` | The dock itself: model refresh, windows, popups, badges, settings state. |
| `DockHost.qml` | Overlay entry point declared by `manifest.json`. |
| `DockModel.js` | Pure model logic and every safety bound (parsing caps, identity resolution). |
| `components/` | QML UI components (dock items, popups, tooltips, settings panel, shaders). |
| `scripts/` | Python helpers (folder/drive scans, notification watcher, keybinding setup) plus `bind-keys.sh`. |
| `shaders/` | Hover/icon-style fragment shaders with precompiled `.qsb` bundles. |
| `tests/unit/` | Node and Python unit suites — what CI runs on every PR. |
| `tests/` | `smoke-test.sh` (live-shell probe) and `manifest-check.sh` (CI manifest gate). |
| `assets/` | README imagery. |
| `.github/workflows/ci.yml` | CI: test suites, QML syntax gate, manifest schema. |

---

## 📄 License

Distributed under the **MIT License**.  
Copyright © 2026 **[thepathless](https://github.com/thepathless)**.

---

## 📋 Releases & Changelog

Full release notes, historical changelogs, and upgrade guides across all versions are available on [**GitHub Releases**](https://github.com/thepathless/omadock/releases).
