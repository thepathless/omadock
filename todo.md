# OmaDock — Work Plan & Progress Log

**Created:** 2026-08-23 22:30
**Session context:** Recovery + feature completion after the row-surgery incident
(`~/Projects/conversations/omadock-row-surgery-23-08-26-2054-PM.md`).
**Current live state:** Layout repaired and verified on screen by user (2026-08-23, after `omarchy restart shell`).

**Status legend:** `[ ]` pending · `[x]` done & verified · `[~]` skipped (user decision) · `[!]` blocked

---

## 1. DONE & VERIFIED — no further work

- [x] **Row-surgery layout repair** — the python block-move had orphaned `separator` / `runningSection`
  Repeater / `folderSeparator` / `foldersRepeater` outside the Row's closing brace, painting folders over
  the Omarchy logo. Splice repair landed on disk; loaded via shell restart; user confirmed on screen.
  Live order (kept as-is per user): `[logo][pinned][tileSep][tiles][sep][running][folderSep][folders]`
- [x] **Logo tooltip** says "Omarchy" (was "Apps") — `Dock.qml` logo `DockIconButton`
- [x] **Logo left-click** opens the Omarchy menu (`omarchy-menu toggle root`), not the apps menu
- [x] **Logo middle-click** opens a terminal (`omarchy-launch-terminal`)
- [x] **Logo scroll** switches workspaces (`cycleWorkspace` → `hl.dsp.focus({ workspace = "e+1"/"e-1" })`)
- [x] **Minimize → dock tile** with a snapshot of the window (single-frame `ScreencopyView`, `live: false`)
- [x] **Tile click** restores that exact window; **right-click** shows Restore/Close (functional —
  UI redesign tracked in 2.3)
- [x] **IPC targets** `omadock.minimizeActive` / `omadock.restoreLast` exist (`IpcHandler` in Dock.qml)

---

## 2. REMAINING WORK

### 2.1 Tile hover magnification (zoom + wave) — `[ ]`

**Why:** Tiles are the only dock element that stays frozen while pinned icons, running icons, and
folders magnify on hover. User request: tiles must follow the same zoom/wave animations.

**Reference pattern** — `DockFolderItem` (Dock.qml ~:882-935):
- `width: root.iconSlot * (root.waveHover ? fitem.magnifyScale : 1)` (wave grows layout width)
- `magnifyScale`: wave → `root.magnifyScaleAt(homeCenter)`; zoom → hovered ? `root.zoomPeak` : 1;
  `hoverEffect === "off"` → 1
- `Behavior on magnifyScale { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }`
- Zoom mode scales the inner content (`iconContainer.scale`), not the layout item

**Code spec for the tile delegate (Dock.qml ~:3196-3450):**
1. Add `homeCenter` via `root.slotHomeCenter(...)` with the **width correction**:
   `extraLeftWidth = index * root.tileWidth + (root.tileWidth - root.iconSlot) / 2`
   (tiles are `1.5 × iconSlot` wide; without this the wave peak drifts ~half a slot per preceding tile —
   derived from the folders' `tilesFixedWidth` precedent)
2. Add `magnifyScale` exactly per the folder pattern (hover source: `tileArea.containsMouse`)
3. Add the same `Behavior on magnifyScale` (110 ms OutQuad)
4. Wave: `width`/`height` × `magnifyScale` — **both** dims so preview aspect ratio holds;
   existing `anchors.verticalCenter` keeps it centered in the Row
5. Zoom: wrap the visual stack (2 stacked-card rects, main rect, `ScreencopyView`, app badge) in an
   `Item { scale: root.waveHover ? 1 : tile.magnifyScale }` — tooltip, action menu, and `MouseArea`
   stay **outside** the wrapper so hover geometry and tooltip size stay unscaled (mirrors folder icons)

**Verify:** hover in zoom + wave modes with ≥1 tile; neighbors shift smoothly in wave; tile returns
to rest; no clipped preview; `hoverEffect "off"` disables.

### 2.2 Group tile stack look ("All Windows" minimize mode) — `[ ]`

**Why:** In `minimizeMode: "all"` an app's windows compress into ONE tile (single preview + count
badge — user accepts this behavior). But the "stack" hint behind group tiles is nearly invisible:
two Rectangles at alpha 0.06 / 0.04 with tiny negative margins (Dock.qml ~:3235-3254). User wants it
to visibly read as a stack of windows.

**Code spec:** rework the two stacked-card layers — clearer offsets, higher-contrast borders
(`Util.alpha(root.dockForeground, …)` up from 0.14/0.10), fills up from 0.06/0.04, cards peeking
visibly behind the top preview. Exact values tuned live with user screenshot feedback.

**Verify:** minimize 2+ windows of one app in "All" mode → tile clearly reads as stacked cards;
badge count still legible; single-window tiles unchanged.

### 2.3 Tile right-click menu → Omarchy menu design — `[ ]`

**Why:** Current tile action menu is a cramped in-tile Rectangle with two text rows (Dock.qml
~:3365-3431) — visually inconsistent with every other dock right-click menu.

**Code spec:** delete the in-tile `tileMenu`; extend the dock's existing `contextMenu` popup
(Dock.qml :3616, `BorderSurface` + `ContextRow` rows, anchored above `dockCard`, x clamped to
window) with a tile mode — same mechanism as the `"__dock_settings__"` special context:
- state e.g. `contextTile` (tile identity/address) set from the tile's right-click handler
- rows: `ContextRow { text: "Restore" }` and `ContextRow { text: "Close"; danger: true }`
  (`ContextRow` component at :625 already supports `danger` styling)
- closes on outside click / action, identical to app context menus

**Verify:** right-click tile → menu pixel-consistent with app menus; Restore/Close act on the
right window(s); Escape/outside click dismisses.

### 2.4 Polish A — stop the screencopy capture error spam — `[ ]` (do AFTER 2.1–2.3)

**Why:** Journal fills with `ScreencopyView … Cannot capture frame, as no recording context is ready.`
Root cause (quickshell source `src/wayland/screencopy/view.cpp:135-139`): a failed export emits
`stopped` → quickshell **destroys the context** (`hyprland_screencopy.cpp:130-132`); the tile's retry
timer then calls `captureFrame()` on the dead context, which can only warn — it never recreates the
session. Feature still works for most tiles (snapshot visible in user's screenshot), this is
robustness only.

**Code spec:** in the tile's `requestFrame()`/retry tick (Dock.qml ~:3277-3295): re-assign
`captureSource` (set `null`, then back to the toplevel) to force `createContext()` re-negotiation;
keep ≤6 event-driven attempts at 140 ms; stop the moment `hasContent` is true.

**Verify:** minimize/restore repeatedly → no warning bursts in `journalctl --user`; every tile
eventually shows snapshot or silent badge fallback.

### 2.5 Polish B — fix `Unable to assign [undefined] to QString` — `[ ]` (do AFTER 2.1–2.3)

**Why:** One transient binding error at shell start (journal 2026-08-23 19:30, `Dock.qml[3246:13]`
in the pre-fix file). Some tile text binding receives `undefined` for rare windows.

**Code spec:** reproduce while tailing `journalctl --user -f` (minimize/restore various apps,
incl. windows with empty titles); pin the exact binding; add safe fallback (`|| ""` guards /
`String(...)` coercion) at the offending site(s).

**Verify:** no QString warnings across a minimize/restore stress loop.

### 2.6 Full test sweep — `[ ]` (after all above)

- Logo: tooltip / left / middle / scroll (re-verify after changes)
- Tiles: single restore, group restore-all, close, magnify in both hover modes
- Minimize modes: off / active / all — settings menu toggles persist
- Drag-reorder pinned apps with tiles present (drop indicator x correct)
- IPC: `qs ipc call omadock minimizeActive` / `restoreLast`
- Edge cases: zero minimized, all apps minimized, rapid minimize-restore, multi-workspace restores
- Idle CPU 0.00%; `qmllint` syntax-clean (import warnings expected — qs modules not on lint path);
  `omarchy plugin validate` green; `Text.PlainText` invariant on any new Text node

### 2.7 Ship — `[ ]`

- `git stash` rollback anchor **before** first code change (not yet taken)
- Granular commits: (1) tile magnification, (2) group stack look, (3) tile menu redesign,
  (4) screencopy recovery, (5) QString guard
- Update README if behavior/UI changed; journal entry + `INDEX.md` row

---

## 3. SKIPPED (user decision 2026-08-23)

- [~] **SUPER+M minimize keybind, auto-registered on plugin install.**
  Research verdict: true install-time hooks don't exist — Omarchy plugins are QML-only
  (`PluginRegistry.qml` has no install lifecycle; marketplace forbids writing user configs), and
  Hyprland owns all keybinds (`hyprland_global_shortcuts_v1` registers the *action*; the compositor
  bind line is still separate). A runtime auto-bind was designed (`hyprctl -j binds` check →
  `hyprctl keyword bind SUPER, M, exec, qs ipc call omadock minimizeActive`, re-applied each shell
  start, zero file writes) but user opted to leave the keybind out entirely.
  Manual fallback if ever wanted: one line in `~/.config/hypr/bindings.lua`:
  `o.bind("SUPER + M", "Minimize active window", "qs ipc call omadock minimizeActive")`
  (`SUPER + M` verified free of conflicts in defaults + user overrides).

---

## 4. Key technical reference (for any future session)

- **Plugin reload:** `omarchy-shell shell rescanPlugins` (plugin-only) or `omarchy restart shell`
  (clean). `omarchy plugin reload` does NOT exist. Auto-reload-on-save does NOT work for this repo —
  the shell's inotify watcher (`PluginRegistry.qml:636-651`) does not traverse the
  `~/.config/omarchy/plugins/omadock → ~/Projects/omadock` symlink.
- **Row structure (current, verified):** `DockIconButton`(:3105) → pinned `Repeater`(:3119) →
  `tileSeparator`(:3183) → `minimizedTilesRepeater`(:3192) → `separator`(:3453) → running
  `Repeater`(:3462) → `folderSeparator`(:3485) → `foldersRepeater`(:3494) → ROW-END(:3514).
  `dockCard.width = row.implicitWidth + insets` — card self-sizes; centering automatic.
- **Magnify math:** `slotHomeCenter(elementIndex, slotsBefore, sepCount, extraLeftWidth)` (:1132);
  `magnifyScaleAt(homeCenter)` :1155; wave grows layout width, zoom scales content in place.
- **Screencopy:** `ScreencopyView { captureSource: win.waylandToplevel; live: false }` +
  `captureFrame()`; context dies on `stopped`; dead-context `captureFrame()` = warning only.
- **Context menu system:** `contextMenu` BorderSurface :3616 + `ContextRow` :625; special contexts
  keyed on `contextAppId` (e.g. `"__dock_settings__"`); `openContext()` :2826 / `closeContext()`.

## 5. Verification log

| Date | Check | Result |
|---|---|---|
| 2026-08-23 | awk Row skeleton (8 children, correct order) | PASS |
| 2026-08-23 | duplicate-ID grep after surgery | PASS (none) |
| 2026-08-23 | qmllint | syntax-clean (qs import warnings expected) |
| 2026-08-23 | `omarchy plugin validate` | PASS (silent) |
| 2026-08-23 | User visual: layout after shell restart | PASS (folders right, logo first) |
| 2026-08-23 | User visual: logo tooltip/menu/middle/scroll | PASS |
| 2026-08-23 | User visual: minimize → tile snapshot | PASS |
