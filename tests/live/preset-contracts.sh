#!/usr/bin/env bash
# NON-INTRUSIVE: exercise this tree, not the owner's already-running shell.
# A disposable HOME on a headless output; no clicks, screenshots or restarts.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OWNER_CFG="${PROBE_CFG_SRC:-$HOME/.config/omarchy/omadock.json}"
OWNER_MD5=$(md5sum "$OWNER_CFG" | cut -d' ' -f1)
. tests/live/headless.sh
cleanup() {
  if declare -F probe_cleanup >/dev/null; then probe_cleanup; fi
  headless_stop
}
trap cleanup EXIT
headless_start "$OWNER_CFG" || exit 1
. tests/live/probe.sh
PROBE_BODY="$PWD/tests/live/preset-contracts-shell.qml"
export PROBE_BODY
fail() { echo "PRESET CONTRACTS FAILED: $*" >&2; probe_log_tail >&2; exit 1; }
probe_start || fail "probe did not load"
PROBE_OWNER_CFG="$OWNER_CFG"
PROBE_OWNER_MD5="$OWNER_MD5"
call() { qs -p "$PROBE_DIR" ipc call omadock-contracts "$@"; }
[ "$(call prepare)" = "ok" ] || fail "fixture preparation"

# Retry bindings/row animations as well as writes; a call returning ok alone
# is not evidence that setup, the active binding and geometry have landed.
check() {
  call read | python3 -c '
import json, sys
r = json.load(sys.stdin)
name, mode = sys.argv[1:]
setup = {
 "Windows": ("panel", "taskbar", False, False, False, "active", True),
 "macOS": ("dock", "center", True, True, True, "off", True),
 "thepathless:ristretto": ("dock", "center", True, True, True, "active", True)
}
keys = ("layout", "alignment", "autohide", "intelligentAutohide", "showMinimizedTiles", "minimizeMode", "showAppsButton")
ids = {"Windows": "builtin_windows", "macOS": "builtin_macos", "thepathless:ristretto": "builtin_thepathless_ristretto"}
if mode == "active":
    assert tuple(r[k] for k in keys) == setup[name], r
    assert r["active"] == ids[name], r
    assert not r["showTooltips"] and not r["advancedTooltips"], r
elif mode == "inactive":
    assert r["active"] == "", r
elif mode == "geometry":
    g = r.get("geometry")
    assert g, r
    assert abs(g["groupCenter"] - g["panelCenter"]) <= 1, g
    assert abs(g["rightEdge"] - g["panelRight"]) <= 1, g
    assert g["rightGroupStart"] > g["appsRight"], g
    if name == "Start":
        assert g["startShown"], g
        assert abs(g["firstApp"] - g["startRight"] - g["spacing"]) <= 1, g
    else:
        assert not g["startShown"], g
elif mode == "saved":
    assert r["active"].startswith("preset_"), r
    assert (r["layout"], r["alignment"], r["minimizeMode"], r["showMinimizedTiles"]) == ("dock", "right", "off", True), r
' "$1" "$2"
}
wait_check() {
  local i
  for i in $(seq 35); do
    check "$@" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  check "$@"
  fail "$*"
}
apply() {
  [ "$(probe_ipc applyPreset "$1")" = "ok" ] || fail "apply $1"
  wait_check "$1" active
  probe_wait_cfg 'import json,sys
c=json.load(open(sys.argv[1])); name=sys.argv[2]
assert c["layout"] == ("panel" if name == "Windows" else "dock")
assert c["minimizeMode"] == ("off" if name == "macOS" else "active")
assert c["showMinimizedTiles"] == (name != "Windows")' "$1" || fail "persisted $1 setup"
}

# Clear saved presets only on the disposable copy, so name shadowing or an
# appearance tie in the owners config cannot mask a shipped contract.
probe_ipc presets | python3 -c 'import json,sys
for p in json.load(sys.stdin):
    if not p.get("builtin"): print(p["id"])' > "$PROBE_DIR/saved-ids"
while read -r id; do
  [ "$(probe_ipc deletePreset "$id")" = "ok" ] || fail "clear copied saved preset"
done < "$PROBE_DIR/saved-ids"
for from in Windows macOS thepathless:ristretto; do
  for to in Windows macOS thepathless:ristretto; do
    apply "$from"
    apply "$to"
    echo "   $from -> $to: setup, active binding and persisted behavior correct"
  done
done

apply Windows
wait_check Start geometry
call read
[ "$(call adjust showAppsButton false)" = "ok" ] || fail "hide Start"
wait_check Windows inactive
wait_check NoStart geometry
call read
apply Windows
for spec in layout:dock alignment:left minimizeMode:off autohide:true intelligentAutohide:true showMinimizedTiles:true showAppsButton:false; do
  IFS=: read -r key value <<< "$spec"
  [ "$(call adjust "$key" "$value")" = "ok" ] || fail "adjust $key"
  wait_check Windows inactive
  apply Windows
done
echo "   every Windows setup control clears the active mark; reapply restores it"

saved=$(probe_ipc savePreset "contract-saved-look")
[ -n "$saved" ] || fail "save appearance copy"
probe_wait_presets in "$saved" || fail "saved copy did not persist"
for spec in layout:dock alignment:right minimizeMode:off showMinimizedTiles:true; do
  IFS=: read -r key value <<< "$spec"
  [ "$(call adjust "$key" "$value")" = "ok" ] || fail "custom setup"
done
[ "$(probe_ipc applyPreset contract-saved-look)" = "ok" ] || fail "apply saved copy"
wait_check copy saved
[ "$(probe_ipc deletePreset "$saved")" = "ok" ] || fail "delete saved copy"
wait_check Windows inactive
echo "   saved copy stays appearance-only, wins the active tie and leaves custom setup intact"

if grep -inE 'TypeError|ReferenceError|is not a function|is not defined|Unable to assign|Failed parsing|Binding loop|Error:' "$(probe_log)"; then
  fail "runtime or parse errors"
fi
probe_cleanup || exit 1
headless_stop || exit 1
trap - EXIT
echo "PRESET CONTRACTS PASSED (clean log; owner config, shell and monitors unchanged)"
