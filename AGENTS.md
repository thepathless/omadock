# AGENTS.md — Omadock

Omarchy Quattro **shell plugin** (`kind: overlay`) built with Quickshell QML + Hyprland IPC.  
The entire plugin is **two files**: `Dock.qml` (~4.7k-line monolith, declared as entry point in `manifest.json`) and `DockModel.js` (pure stateless helpers — no QML state). No build system. No package manager. No test suite.

---

## 🗂 Repository Layout

```
omadock/
├── Dock.qml           # Complete plugin — all QML components and logic
├── DockModel.js       # Pure JS helpers (id normalization, entry building, pin reorder, folder icons)
├── manifest.json      # Omarchy plugin manifest (schemaVersion: 1, kind: overlay)
├── LICENSE            # MIT
├── README.md          # User-facing documentation
├── preview.png        # Marketplace / README hero image (update on major visual changes)
├── assets/            # Settings screenshots and alternate preview images
│   ├── preview-dock.png
│   ├── preview-desktop.png
│   └── preview-settings-{1..5}.png
└── screenshots/       # Raw capture archive (not referenced by README)
```

---

## ⚙️ Dev Loop

This repo **is** the live plugin.  
`~/.config/omarchy/plugins/omadock` is a **symlink** pointing here — edit in place, no deploy step.

```bash
# After any QML/JS edit, reload the shell:
omarchy restart shell                        # Clean full reload (safest)
omarchy-shell shell rescanPlugins            # Plugin-only rescan (faster, less reliable)

# Inspect runtime errors / warnings:
journalctl --user -xeu omarchy-shell -n 80 --no-pager

# Verify the plugin is registered:
omarchy plugin list --json | jq '.[] | select(.id == "omadock")'

# Smoke-test IPC keybinds:
qs ipc call omadock minimizeActive
qs ipc call omadock restoreLast
```

> **Note:** `omarchy plugin reload` does **not** exist.  
> **Note:** Save-triggered auto-reload does **not** work — the shell watcher does not traverse symlinks.


> **Note:** `omarchy restart shell` **does** exist. Use it everytime you make any changes to the plugin to reload the plugin to show the changes live to the user.


---

## ✅ Validation Gates (run before every commit)

```bash
# 1. Manifest schema compliance (MUST pass silently — target the REPO path, NOT the symlink)
omarchy plugin validate ~/Projects/omadock

# 2. QML syntax lint (qmllint is NOT on PATH; qs-module import warnings are noise — syntax errors matter)
/usr/lib/qt6/bin/qmllint Dock.qml

# 3. Manual verification (no automated test suite):
#    a. Visual layout after `omarchy restart shell` — confirm magnification, menus, tiles render correctly.
#    b. IPC smoke: qs ipc call omadock minimizeActive && qs ipc call omadock restoreLast
#    c. Idle CPU MUST stay at 0.00% — verify with `top` or `htop` while dock is idle.
```

---

## 🔒 Non-Negotiable Plugin Invariants

These rules are enforced by the Omarchy marketplace CI and the `omarchy-plugin-dev` skill:

| Rule | What | Why |
|------|------|-----|
| **Text.PlainText** | Every `Text {}` element displaying dynamic strings (window titles, app names, notifications, tooltips) **MUST** declare `textFormat: Text.PlainText` | Qt6 `AutoText` default parses HTML; a malicious window title with `<img src=...>` would load remote assets in the unsandboxed shell process |
| **Zero-CPU idle** | No polling timers in the event loop — all state updates must be event-driven off Hyprland IPC (`rawEvent`, `onValuesChanged`) | Polling prevents CPU C-state sleep, wasting battery |
| **No sudo / pkexec** | Plugin code and launch scripts must never escalate privileges | Sandbox / marketplace invariant |
| **No symlinks** | Plugin directory must contain only regular files | Marketplace validation rejects symlinks |
| **Config paths only** | User data lives exclusively in `~/.config/omarchy/omadock.json` (settings) and `~/.config/omarchy/dock.json` (pinned apps) | Non-destructive user config invariant |

---

## 🏗 Architecture Notes

### Dock Row Order (fixed by design)
```
[ logo ] → [ pinned apps ] → [left tile divider] → [ minimized preview tiles ] → [right divider] → [ running apps ] → [folder divider] → [ pinned folders ]
```
- Left tile divider: shown only when `pinnedSection.length > 0 && hasTiles`
- Right divider: shared with the pinned|running separator, shown only when `pinnedSection.length > 0 && visibleRunningCount > 0`
- `visibleRunningCount` = running entries minus unpinned apps whose windows are ALL minimized (`DockModel.allWindowsMinimized`) — those collapse to zero width and are represented by tiles, so they must not hold dividers open (fixes the "two dividers around a lone tile" bug, 2026-08-24)
- Prevents doubled lines when a middle section is empty.
- `dockCard` self-sizes from `row.implicitWidth` — never hard-code a width.

### Magnification
- **Wave mode**: `magnifyScale` is bound to item `width`, so the whole row grows. Geometry comes from `slotHomeCenter()` / `magnifyScaleAt()`. The tile-width correction (`tileWidth` vs `iconSlot`) is critical — skip it and the wave peak drifts.
- **Zoom mode**: scales inner icon content in-place; layout is stable.
- Home centers are computed in **unmagnified window coordinates** — nothing magnification changes feeds back, so the wave cannot chase itself.

### Context Menu
- **One shared `contextMenu` popup**, keyed by `contextAppId`. Special value `"__dock_settings__"` opens preferences.
- Never create per-item menu component instances — causes memory and input leaks.

### Minimized-Window Preview Tiles
- `ScreencopyView { live: false }` + `captureFrame()` — a **failed export** emits `stopped` which destroys the capture context.
- Re-assigning `captureSource` forces re-negotiation on recovery.
- Minimized windows are parked on `special:minimized`; the origin workspace is stored in `minimizedOrigins[address]` at park time. **Default restore targets the user's currently active workspace**; "Restore to Original" (tile context menu) passes `useOrigin=true` to send windows back via `minimizedOrigins`.
- **No running-indicator dot under tile delegates** — removed by design decision 2026-08-24. Do not re-add.
- **Unpinned + fully-minimized apps hide their running icon** (`isFullyTiled` → width 0); the tile is the single representation. Divider gating uses `visibleRunningCount` for the same reason — keep both derived from `DockModel.allWindowsMinimized` so they can never disagree.

### Urgency / Notification System
- `urgentMap` mixes two key shapes: `"0x…"` per-window addresses + bare `appId` strings (from notification service).
- Address keys are pruned on window close; appId keys survive until the user clicks.
- **Foreground Suppression Rule**: urgency is suppressed if the window is already the active foreground window.
- **Startup Suppression Rule**: urgency is suppressed for windows that opened within the last 3 seconds (`recentOpenedWindowAddrs` expiry).

### IPC Keybind Targets (`qs ipc call omadock <fn>`)
- `minimizeActive` — park the currently focused window to `special:minimized`
- `restoreLast` — restore the oldest-parked window across all apps (FIFO)

---

## 📦 Release Checklist

- [ ] Bump `version` in `manifest.json` (semver, e.g. `"2.8.0"`)
- [ ] Update version badge in `README.md`
- [ ] Replace `preview.png` if there are major visual changes
- [ ] Run all validation gates above
- [ ] `git tag v<version> && git push origin main --tags`
- [ ] `omarchy plugin validate ~/Projects/omadock` passes silently

---

## ✍️ Commit Style

Conventional commits, scope = affected area:

```
feat(tiles): add group-restore from tile context menu
fix(autohide): debounce overlap check on workspace switch
fix(urgency): suppress startup window urgency within 3s grace period
chore(release): bump version to 2.8.0
docs: update AGENTS.md dev loop
```
