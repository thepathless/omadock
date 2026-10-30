#!/usr/bin/env bash
# Live (NON-INTRUSIVE): issue #75 - a "no overlap" snapshot is confirmed once
# after the motion settles, without a pointer visit or another window event,
# and the dock hides on the fresh answer.
#
# A scrolling layout moves its columns in and out of the viewport without a
# Hyprland window event, so the dock's debounced `hyprctl -j clients` snapshot
# can be taken mid-move and answer "no overlap" while the settled layout covers
# the dock. The fix arms one delayed re-measure after such an answer; this suite
# proves it from outside the dock:
#
#   * the plugin's own DockHost runs in a second Quickshell instance, pinned to
#     a fresh headless output (so the overlap answer is deterministic: no
#     client is on that workspace) against a copy of the config under a
#     redirected HOME;
#   * a hyprctl shim on PATH logs every call, so the suite counts the dock's
#     own `hyprctl -j clients` snapshots rather than reading a claim. After one
#     window-event-shaped request there must be a second snapshot ~1.2 s later
#     (the confirmation) with no pointer and no further event, and no third one
#     after it (the confirmation is one-shot, not a poll);
#   * a fresh "overlap" answer must still take the normal hide path.
#
# On v4.9.0 only the first snapshot happens, so the suite fails there: it is a
# regression test for #75, not a description of the fix.
#
# The owner's side (config md5, monitors and focus, dock state, shell PID, no
# surviving process or scratch directory, no headless output) is re-checked at
# exit, as in the other probe suites.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

SCREEN="omadock-autohide"
OWNER_CFG="${HOME}/.config/omarchy/omadock.json"
SRC_CFG=$(mktemp "${TMPDIR:-/tmp}/omadock-autohide-cfg-XXXXXX") || exit 1
SHIM=$(mktemp -d "${TMPDIR:-/tmp}/omadock-autohide-bin-XXXXXX") || exit 1
HAVE_OUTPUT=""
fail=0
fail() { echo "   FAIL: $*" >&2; fail=1; }
note() { echo "   $*"; }

owner_md5() { md5sum "$OWNER_CFG" 2>/dev/null | cut -d' ' -f1; }
monitor_state() {
  hyprctl -j monitors | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(" ".join(m["name"] + ("*" if m["focused"] else "") for m in d))'
}
owner_dock_state() {
  qs -p /usr/share/omarchy/shell ipc call omadock state 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("visible"), d.get("docks"))'
}

# Every hyprctl call the probe makes goes through this shim, which records the
# nanosecond it ran and forwards to the real binary. The dock's overlap probe
# and its rectangle bookkeeping both run `-j clients`; filtering on the command
# and on the ~1.2 s gap tells the confirmation from everything else.
REAL_HYPRCTL=$(command -v hyprctl) || { echo "   cannot run: no hyprctl on PATH" >&2; exit 1; }
cat > "$SHIM/hyprctl" <<EOF
#!/bin/sh
printf '%s %s\n' "\$(date +%s%N)" "\$*" >> "$SHIM/log"
exec "$REAL_HYPRCTL" "\$@"
EOF
chmod +x "$SHIM/hyprctl"
: > "$SHIM/log"
export PATH="$SHIM:$PATH"

cleanup() {
  if declare -F probe_cleanup >/dev/null; then probe_cleanup >/dev/null 2>&1; fi
  [ -n "$HAVE_OUTPUT" ] && hyprctl output remove "$SCREEN" >/dev/null 2>&1
  rm -f "$SRC_CFG"
  rm -rf "$SHIM"
}
trap cleanup EXIT

echo "-- pre-flight: a headless output with no clients on it"
if hyprctl monitors 2>/dev/null | grep -qE "^(Monitor|  )?${SCREEN}\b"; then
  echo "   REFUSING: an output named $SCREEN already exists" >&2
  exit 1
fi
OWNER_MD5=$(owner_md5)
OWNER_MONITORS=$(monitor_state)
OWNER_DOCK=$(owner_dock_state)

# The probe's config source: the owner's config, pinned to the headless output
# and to a single dock, with both autohide modes on. probe.sh copies this file;
# the owner's own file is never read by the probe or written by this suite.
python3 - "$OWNER_CFG" "$SRC_CFG" "$SCREEN" <<'PY' || exit 1
import json, sys
conf = json.load(open(sys.argv[1]))
conf["screen"] = sys.argv[3]
conf["multiMonitor"] = False
conf["autohide"] = True
conf["intelligentAutohide"] = True
json.dump(conf, open(sys.argv[2], "w"), indent=2)
PY

hyprctl output create headless "$SCREEN" >/dev/null 2>&1 || {
  echo "   cannot run: this compositor would not create a headless output" >&2
  exit 1
}
HAVE_OUTPUT="$SCREEN"
sleep 1
if [ "$(monitor_state)" = "$OWNER_MONITORS" ]; then
  fail "the headless output did not appear in the monitor list"
else
  note "headless output up: $(monitor_state)"
fi
# A headless output that took focus would route the owner's typing to a screen
# they cannot see: hand focus back before anything else, then stop.
OWNER_FOCUSED=$(monitor_state | tr ' ' '\n' | grep '\*$' | tr -d '*')
case "$(monitor_state)" in
  *"${SCREEN}*"*)
    echo "   REGRESSION: the headless output took the owner's focus" >&2
    [ -n "$OWNER_FOCUSED" ] && hyprctl dispatch focusmonitor "$OWNER_FOCUSED" >/dev/null 2>&1
    exit 1 ;;
esac

PROBE_CFG_SRC="$SRC_CFG"
PROBE_BODY="$PWD/autohide-shell.qml"
PROBE_SCREEN="$SCREEN"
export PROBE_CFG_SRC PROBE_BODY PROBE_SCREEN
# shellcheck source=tests/live/probe.sh
. ./probe.sh
probe_start || { probe_cleanup; exit 1; }

probe_test() { qs -p "$PROBE_DIR" ipc call omadock-test "$@"; }
step() { probe_test run "$1" 2>/dev/null; }
jval() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get(sys.argv[1])))' "$2"; }
jplain() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]))' "$2" 2>/dev/null; }

echo
echo "-- one no-overlap snapshot, then a confirmation with no pointer or event"
sleep 0.5
: > "$SHIM/log"
T0=$(date +%s%N)
ARM=$(step autohide-arm) || fail "the arm step did not answer"
[ "$(jval "$ARM" ok)" = "true" ] || fail "the arm step failed ($(jval "$ARM" why))"
[ "$(jplain "$(step autohide-read)" visible)" = "True" ] \
  || fail "the dock was not visible before the confirmation"
sleep 3
# The confirmation timer is 1.2 s; its debounced snapshot lands ~60 ms later.
# Anchor on the arm time instead of on a gap: the dock's rectangle bookkeeping
# also runs `-j clients` after a visibility change, so gaps alone are noisy.
# v4.9.0 has no snapshot in this window at all.
if python3 - "$SHIM/log" "$T0" <<'PY'
import sys
T0 = int(sys.argv[2])
ts = [int(l.split(None, 1)[0]) for l in open(sys.argv[1]) if "-j clients" in l]
hits = [t for t in ts if 1_100_000_000 <= t - T0 <= 1_800_000_000]
print("   snapshots after arm: " + ", ".join("%.2fs" % ((t - T0) / 1e9) for t in sorted(ts)))
sys.exit(0 if hits else 1)
PY
then
  note "the dock re-measured ~1.2 s after the stale answer"
else
  fail "no second overlap snapshot arrived: the stale answer was never re-measured (#75)"
fi
# One-shot: nothing may be scheduled after the confirmation window.
if python3 - "$SHIM/log" "$T0" <<'PY'
import sys
T0 = int(sys.argv[2])
ts = [int(l.split(None, 1)[0]) for l in open(sys.argv[1]) if "-j clients" in l]
sys.exit(0 if [t for t in ts if t - T0 > 1_900_000_000] else 1)
PY
then
  fail "a snapshot ran after the confirmation: it must be one-shot, not a poll"
else
  note "no snapshot after the confirmation"
fi
[ "$(jplain "$(step autohide-read)" overlap)" = "False" ] \
  || fail "the fresh answer was not 'no overlap' on the empty output"

echo
echo "-- a fresh overlap answer still hides the dock"
step autohide-overlap >/dev/null || fail "the overlap step did not answer"
sleep 1
[ "$(jplain "$(step autohide-read)" visible)" = "False" ] \
  || fail "the dock did not hide after an overlap was reported"
note "dock hidden on the fresh answer"

echo
echo "-- the dock's log"
if grep -inE "TypeError|ReferenceError|is not a function|is not defined|Cannot read property|Unable to assign" "$PROBE_DIR/probe.log" | head -5 > "$SHIM/errors" && [ -s "$SHIM/errors" ]; then
  sed 's/^/   /' "$SHIM/errors" >&2
  fail "a runtime error in the dock's log"
else
  note "no runtime error in the dock's log"
fi

echo
echo "-- the owner's side, as it was"
hyprctl output remove "$SCREEN" >/dev/null 2>&1
for _ in $(seq 10); do [ "$(monitor_state)" = "$OWNER_MONITORS" ] && break; sleep 0.3; done
[ "$(monitor_state)" = "$OWNER_MONITORS" ] || fail "the monitor list did not come back"
[ "$(owner_md5)" = "$OWNER_MD5" ] || fail "the owner's omadock.json changed"
note "owner's omadock.json unchanged (md5 $OWNER_MD5), monitors $OWNER_MONITORS"
for _ in $(seq 10); do [ "$(owner_dock_state)" = "$OWNER_DOCK" ] && break; sleep 0.3; done
[ "$(owner_dock_state)" = "$OWNER_DOCK" ] || fail "the owner's own dock changed state"
note "owner's own dock back to: $(owner_dock_state)"

echo
probe_cleanup || exit 1
if [ "$fail" = "0" ]; then
  echo "AUTOHIDE PASSED: a stale no-overlap answer is re-measured once and the dock hides on the fresh answer"
else
  echo "AUTOHIDE FAILED" >&2
fi
exit $fail
