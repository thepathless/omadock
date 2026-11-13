#!/usr/bin/env bash
# Live (NON-INTRUSIVE): the dock steps aside under the scratchpad, and only
# while Hyprland says the scratchpad is the workspace in front.
#
# The state has one owner (FloatingDockWatch.scratchpadOpen -> DockFloating.js)
# and one consumer (the dock layer's `visible` in Dock.qml). This suite proves
# that pair on a real compositor: a disposable headless output gives the probe
# dock its own screen (tests/live/headless.sh + probe.sh), and the suite opens
# Omarchy's own scratchpad the way its binding does
# (`hl.dsp.workspace.toggle_special("scratchpad")`, /usr/share/omarchy/default/
# hypr/bindings/tiling.lua:30) on that output only.
#
# What is asserted, in order:
#  * the probe's layer surface is on its output to begin with;
#  * opening the scratchpad there removes that surface, while the owner's own
#    monitor never shows a special workspace;
#  * closing it puts the surface back;
#  * a dock that starts with the scratchpad already open never sees an
#    activespecial event at all, and still resolves hidden: the state is read
#    out of Hyprland's monitor object, not remembered from an event that could
#    be lost. The other half of the same rule is the fail-safe - no monitor, no
#    ipc object or a malformed one answers "closed" (tests/unit/floating.test.mjs
#    pins every unknown shape), so an unknown or disconnected state shows the
#    dock instead of stranding it off screen.
#
# Fails closed: no headless output, no probe on it, or a layer that never
# changes is a failure, never a pass. The owner's config md5, shell PID,
# monitor list, focus and cursor position are re-checked at exit.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

OWNER_CFG="${HOME}/.config/omarchy/omadock.json"
SCREEN=""
OWNER_MONITORS=""
OWNER_CURSOR=""

monitors_signature() {
  hyprctl -j monitors | python3 -c 'import json,sys
rows = []
for m in json.load(sys.stdin):
    rows.append("%s %sx%s+%s+%s%s special=%s" % (m["name"], m["width"], m["height"], m["x"], m["y"],
        "*" if m.get("focused") else "", (m.get("specialWorkspace") or {}).get("name", "")))
print(" | ".join(rows))'
}

# The Hyprland name of the output the probe lives on. Hyprland can truncate a
# long name, so an exact match is tried first and a prefix match second.
probe_monitor() {
  hyprctl -j monitors | python3 -c 'import json,sys
want = sys.argv[1]
names = [m["name"] for m in json.load(sys.stdin)]
for name in names:
    if name == want: print(name); sys.exit(0)
for name in names:
    if want.startswith(name): print(name); sys.exit(0)
sys.exit(1)' "$SCREEN"
}

# 0 while the probe's own layer surface exists on its output. A hidden
# PanelWindow unmaps its wlr layer surface (measured: the surface leaves
# `hyprctl -j layers` and its exclusive zone is released), so the entry
# disappears. Filtered by the probe's PID: the owner's running dock also puts
# an `omadock` layer on a new output, and that one is not this suite's subject.
layer_mapped() {
  local pid
  pid=$(probe_pids | head -1)
  [ -n "$pid" ] || return 1
  hyprctl -j layers | python3 -c 'import json,sys
monitor, pid = sys.argv[1], sys.argv[2]
levels = (json.load(sys.stdin).get(monitor) or {}).get("levels") or {}
for items in levels.values():
    for entry in items:
        if entry.get("namespace") == "omadock" and str(entry.get("pid")) == pid: sys.exit(0)
sys.exit(1)' "$(probe_monitor)" "$pid"
}

probe_special() {
  hyprctl -j monitors | python3 -c 'import json,sys
for m in json.load(sys.stdin):
    if m["name"] == sys.argv[1]:
        print((m.get("specialWorkspace") or {}).get("name", "")); sys.exit(0)' "$(probe_monitor)"
}

owner_focused_monitor() {
  hyprctl -j monitors | python3 -c 'import json,sys
print(next((m["name"] for m in json.load(sys.stdin) if m.get("focused")), ""))'
}

wait_layer() {  # wait_layer mapped|gone <what>
  local want=$1 what=$2 i
  for i in $(seq 50); do
    if [ "$want" = mapped ]; then layer_mapped && return 0
    else layer_mapped || return 0; fi
    sleep 0.2
  done
  echo "   the layer was still $( [ "$want" = mapped ] && echo 'gone' || echo 'up' ) $what after 10s" >&2
  return 1
}

wait_special() {  # wait_special <name> <what>
  local want=$1 what=$2 i now
  for i in $(seq 50); do
    now=$(probe_special)
    [ "$now" = "$want" ] && return 0
    sleep 0.2
  done
  echo "   the probe's output showed special '$now', not '$want', $what" >&2
  return 1
}

# Omarchy's own scratchpad binding, aimed at the probe's output: focus it, call
# the binding's dispatcher, hand focus straight back. The workspace stays on the
# output it was opened on.
toggle_scratchpad() {
  local mon owner
  mon=$(probe_monitor) || { echo "scratchpad: no monitor for $SCREEN" >&2; return 1; }
  owner=$(owner_focused_monitor)
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$mon\" })" >/dev/null 2>&1 || {
    echo "scratchpad: could not focus $mon" >&2; return 1; }
  sleep 0.2
  hyprctl dispatch 'hl.dsp.workspace.toggle_special("scratchpad")' >/dev/null 2>&1 || {
    echo "scratchpad: the toggle_special dispatcher failed" >&2
    [ -n "$owner" ] && hyprctl dispatch "hl.dsp.focus({ monitor = \"$owner\" })" >/dev/null 2>&1
    return 1; }
  [ -n "$owner" ] && hyprctl dispatch "hl.dsp.focus({ monitor = \"$owner\" })" >/dev/null 2>&1
  sleep 0.2
}

# The pointer, last: a focus change warps it, and so does removing an output,
# so it is restored after both have happened (restore_owner below only puts the
# workspaces and the focus back).
restore_pointer() {
  local owner x y
  owner=$(owner_focused_monitor 2>/dev/null) || owner=""
  [ -n "$owner" ] && hyprctl dispatch "hl.dsp.focus({ monitor = \"$owner\" })" >/dev/null 2>&1
  [ -n "$OWNER_CURSOR" ] || return 0
  x=${OWNER_CURSOR%,*}
  y=${OWNER_CURSOR#*,}
  hyprctl dispatch "hl.dsp.cursor.move({ x = ${x// /}, y = ${y// /} })" >/dev/null 2>&1
}

restore_owner() {
  local mon owner
  mon=$(probe_monitor 2>/dev/null) || mon=""
  owner=$(owner_focused_monitor 2>/dev/null) || owner=""
  if [ -n "$mon" ] && [ "$(probe_special 2>/dev/null)" != "" ]; then
    hyprctl dispatch "hl.dsp.focus({ monitor = \"$mon\" })" >/dev/null 2>&1
    sleep 0.2
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("scratchpad")' >/dev/null 2>&1
    sleep 0.2
  fi
  [ -n "$owner" ] && hyprctl dispatch "hl.dsp.focus({ monitor = \"$owner\" })" >/dev/null 2>&1
  return 0
}

# shellcheck source=tests/live/headless.sh
. tests/live/headless.sh
OWNER_MONITORS=$(monitors_signature)
OWNER_CURSOR=$(hyprctl cursorpos)
headless_start "$OWNER_CFG" || exit 1
SCREEN="$PROBE_SCREEN"
# shellcheck source=tests/live/probe.sh
. tests/live/probe.sh

cleanup() {
  restore_owner >/dev/null 2>&1
  if declare -F probe_cleanup >/dev/null; then probe_cleanup >/dev/null 2>&1; fi
  headless_stop >/dev/null 2>&1
}
trap cleanup EXIT

fail() {
  echo "SCRATCHPAD FAILED: $*" >&2
  declare -F probe_log_tail >/dev/null && probe_log_tail >&2
  restore_owner >/dev/null 2>&1
  declare -F probe_cleanup >/dev/null && probe_cleanup >/dev/null 2>&1
  headless_stop >/dev/null 2>&1
  exit 1
}
note() { echo "   $*"; }

# probe_start records the headless config copy as the "owner" it re-checks;
# point it back at the real file, so teardown fails on any change to the
# owner's own config (tests/live/headless.sh documents the same step).
pin_owner() {
  PROBE_OWNER_CFG="$OWNER_CFG"
  PROBE_OWNER_MD5=$(md5sum "$OWNER_CFG" | cut -d' ' -f1)
}

command -v hyprctl >/dev/null || fail "no hyprctl on PATH"
command -v jq >/dev/null || true
probe_monitor >/dev/null || fail "the headless output is not in Hyprland's monitor list"

probe_start || fail "the probe dock did not start on $SCREEN"
pin_owner
[ "$(probe_special)" = "" ] || fail "the probe's output already shows a special workspace"

echo "-- the dock's surface is on its own output"
layer_mapped || fail "the probe dock drew no layer surface on $SCREEN"
note "$SCREEN carries the omadock layer; the owner's monitors are untouched"

echo "-- the scratchpad takes the dock's place"
toggle_scratchpad || fail "could not open the scratchpad on $SCREEN"
wait_special "special:scratchpad" "after the toggle" || fail "the scratchpad did not open"
wait_layer gone "while the scratchpad was open" || fail "the dock stayed on screen under the scratchpad"
note "special:scratchpad on $SCREEN; the omadock layer went away"
[ "$(hyprctl -j monitors | python3 -c 'import json,sys
print("".join((m.get("specialWorkspace") or {}).get("name","") for m in json.load(sys.stdin) if m["name"] != sys.argv[1]))' "$(probe_monitor)")" = "" ] \
  || fail "the owner's monitor was left showing a special workspace"

echo "-- closing the scratchpad brings the dock back"
toggle_scratchpad || fail "could not close the scratchpad on $SCREEN"
wait_special "" "after the second toggle" || fail "the scratchpad stayed open"
wait_layer mapped "after the scratchpad closed" || fail "the dock did not come back"
note "the layer is back with no special workspace on that output"

echo "-- a dock that starts under the scratchpad never sees the event, and still knows"
toggle_scratchpad || fail "could not reopen the scratchpad"
wait_special "special:scratchpad" "after the second open" || fail "the scratchpad did not reopen"
wait_layer gone "before the restart" || fail "the dock stayed on screen under the scratchpad"
probe_cleanup || fail "the stopped probe left something behind"
probe_start || fail "the probe dock did not restart under the scratchpad"
pin_owner
wait_layer gone "after a restart under the open scratchpad" || fail "the restarted dock drew over the scratchpad"
note "no activespecial reached the restarted dock, and its layer stayed away: the state came from Hyprland"

echo "-- and it returns as soon as the scratchpad closes"
toggle_scratchpad || fail "could not close the scratchpad after the restart"
wait_special "" "after the restart's close" || fail "the scratchpad stayed open"
wait_layer mapped "after the restarted dock's scratchpad closed" || fail "the restarted dock did not come back"
note "the layer returned after the restart too"

echo "-- teardown"
restore_owner
probe_cleanup || fail "the probe session left something behind"
headless_stop || fail "the headless output did not go away"
# Compared after the output is gone: while it exists the list still carries it.
for i in $(seq 15); do
  [ "$(monitors_signature)" = "$OWNER_MONITORS" ] && break
  sleep 0.3
done
[ "$(monitors_signature)" = "$OWNER_MONITORS" ] || fail "the owner's monitor list did not come back"
for i in $(seq 8); do
  restore_pointer
  sleep 0.25
  [ "$(hyprctl cursorpos)" = "$OWNER_CURSOR" ] && break
done
[ "$(hyprctl cursorpos)" = "$OWNER_CURSOR" ] || fail "the owner's cursor did not come back"
note "monitors, focus and cursor restored: $OWNER_MONITORS"
echo "SCRATCHPAD PASSED"
