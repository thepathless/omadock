#!/bin/bash
# OmaDock keybinding setup — idempotent, safe to run multiple times
set -euo pipefail

BINDINGS="${HOME}/.config/hypr/bindings.lua"

if [ ! -f "$BINDINGS" ]; then
  echo "Error: $BINDINGS not found. Is Hyprland/Omarchy installed?" >&2
  exit 1
fi

# Check if toggleVisibility is already configured
if grep -q "omadock toggleVisibility" "$BINDINGS" 2>/dev/null; then
  echo "✓ OmaDock keybindings are already configured in $BINDINGS"
  exit 0
fi

# If old Antigravity block exists with minimizeActive but without toggleVisibility,
# update it cleanly, or append the full block.
cat >> "$BINDINGS" << 'EOF'

-- >>> ADDED BY OMADOCK <<<
-- OmaDock IPC keybindings (idempotent, safe to re-run setup.sh)
o.bind("SUPER + D", "Toggle Omadock", "exec qs -p /usr/share/omarchy/shell ipc call omadock toggleVisibility")
o.bind("SUPER + M", "Minimize focused window", "exec qs -p /usr/share/omarchy/shell ipc call omadock minimizeActive")
hl.unbind("SUPER + SHIFT + M")
o.bind("SUPER + SHIFT + M", "Restore oldest minimized", "exec qs -p /usr/share/omarchy/shell ipc call omadock restoreLast")
-- <<< ADDED BY OMADOCK <<<
EOF

echo "✓ OmaDock keybindings successfully added to $BINDINGS"
echo "  SUPER + D         → Toggle dock visibility"
echo "  SUPER + M         → Minimize focused window"
echo "  SUPER + SHIFT + M → Restore oldest minimized window"
echo ""
echo "Reloading Hyprland configuration..."
if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload
  echo "✓ Hyprland reloaded!"
fi
