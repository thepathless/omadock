#!/usr/bin/env bash
# Live: every IPC function round-trips and leaves the dock mapped with a
# clean log. Backs up omadock.json and restores it on exit. No input.
#
# *** INTRUSIVE - this one drives the dock on the OWNER'S DESKTOP. ***
# It opens the full-screen settings overlay on the running dock (a click or a
# key press during the run fails it), it writes the running dock's config file
# in place, and it exercises the code the running dock LOADED - not this tree,
# because the launcher runs Quickshell with QS_DISABLE_FILE_WATCHER=1. It is
# kept for the wiring only a real dock can show: the settings panel's open and
# page state, setLayout/setAlignment, and itemGeometry of the live items.
#
# Anything else belongs in a suite built on tests/live/probe.sh, which runs the
# plugin's own DockHost.qml in a second Quickshell instance against a copy of
# the config and never touches the desktop: tests/live/presets.sh is the model.
set -u
cd "$(dirname "$0")/../.."
. tests/live/common.sh
wait_ready || exit 1
CFG=$HOME/.config/omarchy/omadock.json
bak=$(mktemp); cp "$CFG" "$bak"
restore() { omarchy-shell omadock closeSettings >/dev/null 2>&1; cp "$bak" "$CFG"; rm -f "$bak" "$bak.presets"; }
trap restore EXIT
since=$(date '+%Y-%m-%d %H:%M:%S')
ipc() { omarchy-shell omadock "$@"; }
st() { ipc state | python3 -c "import json,sys; print(json.load(sys.stdin)[sys.argv[1]])" "$1"; }
# The settings panel is a full-screen overlay that takes keyboard focus and
# closes on any click or Escape, so input during the run fails the test.
fail() { echo "IPC ROUND-TRIP FAILED: $* (a click or key press during the run closes settings)" >&2; exit 1; }

ipc openSettings; sleep 1
[ "$(st settingsOpen)" = True ] || fail "openSettings"
for page in appearance placement behavior effects size presets folders groups about; do
  ipc openSettingsPage "$page"; sleep 0.4
  [ "$(st settingsPage)" = "$page" ] || fail "openSettingsPage $page"
done
ipc closeSettings; sleep 0.5
[ "$(st settingsOpen)" = False ] || fail "closeSettings"

v=$(st visible)
ipc toggleVisibility; sleep 0.5; ipc toggleVisibility; sleep 0.5
[ "$(st visible)" = "$v" ] || fail "toggleVisibility twice"
ipc reveal; sleep 0.5

[ "$(ipc applyPreset no-such-preset-xyz)" = "not found" ] || fail "applyPreset unknown"
[ "$(ipc applyPreset "$(python3 -c 'print("x" * 10000)')")" = "not found" ] || fail "applyPreset 10k name"

# Presets: save the look on screen under a chosen name, list it, remove it.
# The list lives in omadock.json, which this script restores on exit.
pid=$(ipc savePreset verify_ipc_roundtrip)
[ -n "$pid" ] || fail "savePreset (six presets already saved? remove one to run this test)"
ipc presets | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert any(p['name'] == 'verify_ipc_roundtrip' and p['id'] == sys.argv[1] for p in d), d
" "$pid" || fail "presets() lists the saved one"
[ "$(ipc deletePreset "$pid")" = "ok" ] || fail "deletePreset"
ipc presets | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert not any(p['id'] == sys.argv[1] for p in d), d
" "$pid" || fail "presets() dropped the removed one"
[ "$(ipc deletePreset "$pid")" = "not found" ] || fail "deletePreset twice"

# The rule DockPresets.merge settles: one name is never a shipped look *and* a
# saved preset at once, and the entry the user saved is never hidden from the
# list. Two saved presets sharing a name are the user's own config, not this
# rule -- a hand-edited or restored omadock.json is left as it is -- so the
# clash is only counted against the shipped rows. Red on a dock that loaded its
# QML before a change to DockPresets.js: this host disables QML file watching,
# so the running dock only picks the rule up on the next restart.
ipc presets > "$bak.presets"
python3 - "$CFG" "$bak.presets" <<'PY' || fail "a name is a shipped look and a saved preset at once"
import json, sys
key = lambda r: str(r["name"]).strip().lower()
rows = json.load(open(sys.argv[2]))
saved_rows = [r for r in rows if not r.get("builtin")]
shipped = {key(r) for r in rows if r.get("builtin")}
clash = sorted(n for n in {key(r) for r in saved_rows} if n in shipped)
if clash:
    raise SystemExit("listed as a shipped look and a saved preset at once: %s" % ", ".join(clash))
saved = [str(p.get("name", "")).strip().lower() for p in (json.load(open(sys.argv[1])).get("presets") or [])]
listed = {key(r) for r in saved_rows}
missing = [n for n in saved if n not in listed]
if missing:
    raise SystemExit("saved presets missing from the list: %s" % ", ".join(missing))
PY

# The shipped looks ride with the dock: listed, marked, and not removable.
bid=$(ipc presets | python3 -c "
import json, sys
d = [p for p in json.load(sys.stdin) if p.get('builtin')]
if not d: sys.exit(1)
print(d[0]['id'])
") || fail "presets() does not list a shipped look"
[ "$(ipc deletePreset "$bid")" = "not found" ] || fail "a shipped preset is not removable"

align=$(python3 -c "import json; print(json.load(open('$CFG')).get('alignment', 'center'))")
ipc setAlignment "$align"; sleep 0.5

layout=$(python3 -c "import json; print(json.load(open('$CFG')).get('layout', 'dock'))")
ipc setLayout panel; sleep 0.5
[ "$(st layout)" = panel ] || fail "setLayout panel"
ipc setAlignment spread; sleep 0.5
[ "$(st align)" = spread ] || [ "$(st align)" = left ] || fail "setAlignment spread in panel"
ipc setLayout bogus; sleep 0.5
[ "$(st layout)" = dock ] || fail "setLayout bogus -> dock"
# Autohide may have hidden the dock again (itemGeometry is empty while hidden).
ipc setLayout "$layout"; ipc setAlignment "$align"; sleep 0.5; ipc reveal; sleep 0.2
ipc itemGeometry | python3 -c "import json,sys; assert len(json.load(sys.stdin)) > 0" || fail "itemGeometry empty"
bash tests/smoke-test.sh >/dev/null || fail "smoke test"
if journalctl --user --since "$since" | grep -iE "omadock/.*(error|TypeError|ReferenceError|is not a)"; then
  fail "errors in the log"
fi
echo "IPC ROUND-TRIP PASSED"
