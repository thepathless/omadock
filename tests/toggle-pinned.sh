#!/usr/bin/env bash
# Unit test for DockModel.togglePinned (pin / unpin from the context menus).
#
# The bug it guards: a pin stored under one id ("hermes") and an entry that has
# since been renamed ("com.nousresearch.hermes") are one app to buildEntries,
# but togglePinned matched ids exactly — so "Unpin from Dock" left the old pin
# and appended the new id, showing the app twice.
#
# Read-only and self-contained: it only evaluates DockModel.js, never the shell.
# Skips (exit 0) when node is not installed, since the plugin does not need it.
#
# Usage: tests/toggle-pinned.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed"
  exit 0
fi

exec node tests/toggle-pinned.js
