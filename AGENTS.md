# AGENTS.md — Omadock

Omarchy Quattro **shell plugin** (`kind: overlay`) built on Quickshell QML + Hyprland IPC.
The entire codebase is two files: `Dock.qml` (~4.7k-line monolith, entrypoint per `manifest.json`) and `DockModel.js` (stateless helpers). No build system, no package manager, no test suite.

## Dev loop (non-obvious)

- This repo IS the live plugin: `~/.config/omarchy/plugins/omadock` is a symlink here. Edit in place.
- Reload after edits: `omarchy-shell shell rescanPlugins` (plugin-only) or `omarchy restart shell` (clean).
  - `omarchy plugin reload` does **not** exist.
  - Save-triggered auto-reload does **not** work: the shell's plugin watcher doesn't traverse the symlink.
- Runtime logs: `journalctl --user -xeu omarchy-shell -n 50`.

## Validation gates (run before committing)

```bash
/usr/lib/qt6/bin/qmllint Dock.qml          # qmllint is NOT on PATH; qs-module import warnings are noise — syntax errors are the signal
omarchy plugin validate ~/Projects/omadock # MUST target the repo path, NOT the plugins symlink (symlinks fail validation); passes silently
```

Plus manual verification — there is no automated test suite:

- Visual check after `omarchy restart shell` (layout/magnification/menus can only be confirmed on screen).
- IPC smoke test: `qs ipc call omadock minimizeActive` and `restoreLast`.
- Idle CPU must stay at **0.00%**: everything is event-driven off Hyprland's IPC socket; never add polling timers.

## Plugin compliance invariants (marketplace)

- Every `Text` node rendering dynamic strings (window titles, app names, tooltips) MUST set `textFormat: Text.PlainText`.
- QML-only plugins: no install-time hooks, no writing outside `~/.config/`. User config lives in `~/.config/omarchy/omadock.json`; pinned apps in `~/.config/omarchy/dock.json`.
- Root files `manifest.json`, `LICENSE`, `README.md`, `preview.png` are mandatory; README must retain its Install / Update / Removal sections.
- Bump `version` in `manifest.json` for releases.

## Architecture notes

- Dock row order (fixed by design): logo → pinned apps → tile separator → minimized-window preview tiles → separator → running apps → folder separator → pinned folders. `dockCard` self-sizes from `row.implicitWidth`.
- Magnification: wave mode grows layout width/height via a `magnifyScale` bound width; zoom mode scales inner content in place. Geometry comes from `slotHomeCenter()` / `magnifyScaleAt()` — tile-width correction (`tiles are wider than iconSlot`) matters or the wave peak drifts.
- Minimized-window tiles use `ScreencopyView { live: false }` + `captureFrame()`: a failed export emits `stopped` which destroys the capture context; retrying on a dead context only warns. Recovery requires re-assigning `captureSource` to force re-negotiation.
- Right-click menus share ONE `contextMenu` popup keyed on `contextAppId` (special value `"__dock_settings__"` opens preferences) — don't create per-item menu components.
- Minimized windows are parked on the `special:minimized` workspace; restore must return them to their original workspace.
- Minimized-window tiles intentionally have **no** running-indicator dot beneath them (removed by design decision 2026-08-24) — don't re-add one when touching the tile delegate.

## Workflow

- Commits follow `feat(scope):` / `fix(scope):` conventional style (`feat(tiles): ...`).
