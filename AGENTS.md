# OmaDock Agent Instructions & Architecture Guide

> **CRITICAL INSTRUCTION FOR ALL AI CODING AGENTS**:
> Read this document thoroughly before inspecting or modifying any code in this repository.

---

## 1. Dual-Branch Repository Topology

OmaDock uses a dual-environment Git worktree topology to separate the user's stable daily-driver desktop dock from in-progress experimental features.

```
/home/suva/Projects/omadock/
├── [Branch: main (STABLE)]  <---------------- Active System Daily Driver & Public GitHub Release
│   ├── Dock.qml              (Stable v3.1.16)
│   ├── DockModel.js
│   ├── manifest.json         (Version: 3.1.16)
│   ├── components/
│   ├── assets/
│   ├── switch.sh             (Switcher utility)
│   └── AGENTS.md             (This guide)
│
└── experiment/ [Git Worktree -> Branch: experimental (CUTTING-EDGE)]  <-- Feature Development Lab
    ├── Dock.qml              (v3.4.0 / Wave physics, iOS/Android folders, jump lists)
    ├── DockModel.js
    ├── manifest.json
    ├── components/
    └── assets/
```

### Purpose of Each Environment

| Directory | Git Branch | Status | Description |
| :--- | :--- | :--- | :--- |
| `/home/suva/Projects/omadock` | `main` | **STABLE** | Production-ready, verified codebase (currently `v3.1.16`). This is what runs on the user's desktop by default and what is published to `origin/main` on GitHub. |
| `/home/suva/Projects/omadock/experiment` | `experimental` | **DEV / TESTBED** | Active development environment (currently `v3.4.0`). Where new physics, animations, folder reorganizations, and architectural refactors are created and iterated on. |

---

## 2. Invariants for AI Agents

1. **Root Isolation Invariant**:
   - **NEVER** write unverified experimental code or unstable refactors into the root directory.
   - Any new feature request, bug investigation, or visual experiment **MUST** be implemented inside `/home/suva/Projects/omadock/experiment`.

2. **Daily Driver Stability Invariant**:
   - The user relies on OmaDock for everyday desktop productivity. Root `main` must remain rock-solid, crash-free, and fully functional at all times.

3. **Live Desktop Switching**:
   - When developing or testing features inside `experiment/`, switch the desktop dock to the experimental profile:
     ```bash
     omadock-switch experiment
     ```
   - Before ending a session or whenever the user wants their stable desktop restored:
     ```bash
     omadock-switch stable
     ```
   - Check which profile is currently live on screen:
     ```bash
     omadock-switch status
     ```

4. **Promotion to Stable Gate**:
   - Merging changes from `experimental` into `main` requires:
     1. Empirical verification that all features work without regression.
     2. Clean Quickshell logs with zero QML runtime exceptions (`quickshell log -p /usr/share/omarchy/shell -t 30`).
     3. Strict user approval before merging into `main`.

5. **Remote Push Permission Gate**:
   - **NEVER execute `git push` without explicit, prior user confirmation in chat.**
   - Public installations (`omarchy plugin add https://github.com/thepathless/omadock.git`) clone `origin/main`. Only stable, thoroughly verified releases are pushed to GitHub `main`.

---

## 3. Desktop Switcher Tool (`omadock-switch` / `./switch.sh`)

The switcher script manages the active desktop symlink at `~/.config/omarchy/plugins/omadock` and reloads the Omarchy shell:

```bash
# Check active mode and git state
omadock-switch status

# Switch desktop to stable v3.1.16 (main)
omadock-switch stable

# Switch desktop to experimental dev (experimental)
omadock-switch experiment

# Toggle between stable and experimental
omadock-switch
```

---

## 4. System Architecture & Diagnostics

- **Compositor**: Hyprland (Wayland) on Omarchy
- **Shell**: Quickshell (`/usr/share/omarchy/shell`)
- **Plugin ID**: `omadock`
- **Plugin Manifest**: `manifest.json` (schemaVersion 1, kind: `overlay`, entryPoints: `Dock.qml`)
- **Active Symlink**: `~/.config/omarchy/plugins/omadock`
- **Shell Reload Command**: `omarchy restart shell`
- **Shell IPC Inspection**:
  ```bash
  qs -p /usr/share/omarchy/shell ipc show | grep -A 5 "target omadock"
  ```
- **Shell Live Logs**:
  ```bash
  quickshell log -p /usr/share/omarchy/shell -t 30
  ```
- **Keybinding Setup**: Managed via `setup.sh` updating `~/.config/hypr/bindings.lua`.
