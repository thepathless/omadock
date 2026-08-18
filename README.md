# Omadock (`omadock`)

A modern, high-performance, autohiding application dock for [Omarchy](https://omarchy.org) (Quickshell + Hyprland).

## Features

- **Centered Floating Card**: Sits at the bottom of the display with Omarchy theme styling, gaps, and corner rounding.
- **Intelligent Scale-Aware Autohide**: Automatically reveals when the cursor touches the bottom edge and hides when windows overlap the dock area (with full fractional scaling / HiDPI support).
- **Deep Customization Menu (Right-click Omarchy icon)**:
  - **Autohide Mode**: Always Show, Intelligent Autohide, Auto Hide.
  - **Dock Shape**: Rounded, Round (Capsule), Square.
  - **Background Opacity**: Opaque (100%), Glass (80%), Frosted Glass (65%), Translucent (35%), Transparent (0% with border).
  - **Background Color**: Theme (matches active theme), No Color, or 10 curated preset palette swatches.
  - **Icon Size**: Small (28px), Medium (36px), Large (44px), Extra Large (52px).
  - **Icon Spacing**: Compact (2px), Normal (4px), Relaxed (8px).
  - **Toggles**: Show Tooltips.
- **Mouse-Wheel Window Cycling**: Hover over an app icon with multiple open windows and scroll up/down to cycle directly between windows in real time.
- **Zero-CPU Polling**: Pure reactive event-driven architecture using Hyprland IPC & Wayland Toplevel signals.
- **Click Pass-Through Input Masking**: Reveal edge trigger does not swallow or intercept clicks to underlying maximized desktop windows.
- **Multi-Window Support**:
  - Distinct active and multi-instance indicator dots.
  - Left-click cycles through open windows of an active app.
  - Right-click context menu displays individual open window titles for direct window switching.
  - Mouse scroll wheel cycles between open windows in either direction.
- **Drag & Drop Reordering**: Drag pinned app icons to rearrange them live with insertion indicator lines.
- **Context Menus (Omarchy Style)**:
  - **Omarchy Icon (Right-click)**: Hierarchical Omadock Settings submenu.
  - **App Icons (Right-click)**: Launch / New Window, Window Instance List (direct switch), Pin / Unpin, Close Window / All Windows.
- **Apps Launcher Button**: Quick access to Omarchy's apps search and launcher menu (left-click).

---

## Configuration

Omadock works out of the box with sensible defaults and automatically hot-reloads when config files change. All options can also be toggled live via the right-click settings menu on the Omarchy icon.

### Custom Options (`~/.config/omarchy/omadock.json`)

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
  "screen": "eDP-1",
  "iconSize": 36
}
```

| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `autohide` | `boolean` | `true` | Enable autohide on hover reveal. Set `false` for always-visible pinned dock. |
| `intelligentAutohide` | `boolean` | `true` | Automatically hide dock when windows on the current workspace overlap its area. |
| `opacity` | `number` | `1.0` | Background transparency (1.0 = Opaque, 0.8 = Glass, 0.55 = Translucent, 0.0 = Transparent). |
| `shape` | `string` | `"rounded"` | Dock corner radius style (`"rounded"`, `"round"`, or `"square"`). |
| `bgColor` | `string` | `"theme"` | Background color (`"theme"` to match active desktop theme, `"none"` for no color, or hex color code). |
| `itemSpacing` | `number` | `4` | Space in pixels between dock icon slots (`2`, `4`, `8`). |
| `iconSize` | `number` | `0` | Optional custom icon size in pixels (e.g. `28`, `36`, `44`, `52`). |
| `showAppsButton` | `boolean` | `true` | Show or hide the Omarchy apps menu launcher button on the left edge. |
| `showTooltips` | `boolean` | `true` | Show app name tooltips on mouse hover. |
| `screen` | `string` | `""` | Optional monitor name to pin the dock to (defaults to primary monitor). |

### Pinned Apps (`~/.config/omarchy/dock.json`)

Pinned applications are saved in `~/.config/omarchy/dock.json`:

```json
{
  "pinned": [
    "foot",
    "org.gnome.Nautilus",
    "google-chrome"
  ]
}
```

You can also reorder pins via drag-and-drop or pin/unpin via right-click context menu.

---

## Validation & Reloading

To test and reload the dock live:

```bash
omarchy restart shell
```

Check logs for diagnostics:

```bash
journalctl --user -xeu omarchy-shell -n 50
```

---

## License

MIT
