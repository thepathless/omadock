#!/usr/bin/env bash
# Helpers for tests/live/presets.sh, sourced after probe.sh (they call its
# probe_ipc/probe_wait_presets). Kept out of the suite so its shell ratchet can
# hold while the suite gains the headless-output bootstrap.

# Make room for $1 more saved presets (default one) on a copy that may already
# hold the maximum six - an ordinary config, and the copy is disposable (the
# suite removes saved presets from it anyway). Called before a section takes
# its snapshot, so the snapshot is the state that section compares against.
ensure_slot() {
  local need=${1:-1} saved victim
  while :; do
    saved=$(probe_ipc presets | python3 -c '
import json, sys
print(sum(1 for r in json.load(sys.stdin) if not r.get("builtin")))
')
    [ "$saved" -le $((6 - need)) ] && return 0
    victim=$(probe_ipc presets | python3 -c '
import json, sys
rows = [r["id"] for r in json.load(sys.stdin) if not r.get("builtin")]
print(rows[0] if rows else "")
')
    [ -n "$victim" ] || return 1
    probe_ipc deletePreset "$victim" >/dev/null || return 1
    probe_wait_presets out "$victim"
    echo "   (six presets already saved - removed $victim from the copy)" >&2
  done
}
