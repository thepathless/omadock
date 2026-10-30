#!/usr/bin/env bash
# Live (NON-INTRUSIVE): the preset surface, end to end, on a second Quickshell
# instance running this working tree's DockHost.qml (see tests/live/probe.sh).
#
# This is the safe live test: it never touches the desktop, the config or the
# shell the owner is using. The probe runs against a copy of omadock.json under
# a redirected HOME on its own headless output - the Windows preset carries the
# taskbar's always-visible panel, which must live on a screen with no glass
# attached - and the owner's md5 and shell PID are re-checked at exit. Use it
# instead of the running dock: the launcher disables QML watching.
#
# Covers: presets() shape (one active at most, every saved preset listed, no
# shipped/saved name clash), the probe dock's state/itemGeometry, applyPreset
# by NAME for every shipped look (the label and taskbar placements included),
# the id-is-not-a-name trap, deletePreset ok/not found with the config rewrite,
# save-then-remove leaving other presets and keys intact, a hostile name stored
# bounded and clean, an outside edit still landing, and no torn-read parse.
set -u
cd "$(dirname "$0")/../.."

OWNER_CFG="${PROBE_CFG_SRC:-$HOME/.config/omarchy/omadock.json}"
# shellcheck source=tests/live/headless.sh
. tests/live/headless.sh
headless_start "$OWNER_CFG" || exit 1
# shellcheck source=tests/live/probe.sh
. tests/live/probe.sh
# shellcheck source=tests/live/presets-support.sh
. tests/live/presets-support.sh

WORK=""
cleanup() {
  if declare -F probe_cleanup >/dev/null; then probe_cleanup >/dev/null 2>&1; fi
  headless_stop >/dev/null 2>&1
}
trap cleanup EXIT

fail() {
  echo "PRESETS FAILED: $*" >&2
  [ -n "$WORK" ] && probe_log_tail >&2
  probe_cleanup >/dev/null 2>&1
  headless_stop >/dev/null 2>&1
  exit 1
}

# A presets() listing - or a config's saved presets - may carry each name once:
# the list is keyed by name, so a repeated name is the bug. One owner for the
# shape, run on the listing before and after a removal and on the config.
assert_unique_preset_names() {
  python3 - "$1" <<'PY' || fail "a duplicate preset name in $1"
import json, sys
data = json.load(open(sys.argv[1]))
rows = data if isinstance(data, list) else (data.get("presets") or [])
names = [str(r.get("name", "")).strip().lower() for r in rows]
dupes = sorted({n for n in names if names.count(n) > 1})
assert not dupes, "a name is carried more than once: %s" % dupes
PY
}

# The bound a saved name is stored under is DockModel's (MAX_PRESET_NAME): read
# it out of the module, not repeated here, so the guard cannot drift from the
# rule - the unit suite reads the same constant.
MAX_PRESET_NAME=$(node -e '
const fs = require("node:fs"), vm = require("node:vm");
const ctx = vm.createContext({ console, Quickshell: { iconPath: () => "" } });
vm.runInContext(fs.readFileSync("DockModel.js", "utf8"), ctx);
console.log(ctx.MAX_PRESET_NAME);
' 2>/dev/null)
case "$MAX_PRESET_NAME" in
  "" | *[!0-9]*) fail "could not read MAX_PRESET_NAME out of DockModel.js" ;;
esac

probe_start || { probe_cleanup >/dev/null 2>&1; exit 1; }
# probe_start recorded the synthetic source as the "owner" it re-checks; point
# that back at the real file so the exit check guards the user's config.
PROBE_OWNER_CFG="$OWNER_CFG"
PROBE_OWNER_MD5=$(md5sum "$OWNER_CFG" | cut -d' ' -f1)
WORK="$PROBE_DIR/work"
mkdir -p "$WORK"
CFG=$(probe_cfg)
ORIG="$PROBE_DIR/owner-config.json"
BEFORE="$WORK/presets-before.json"

# ---------------------------------------------------------------------------
echo "-- presets() shape"
probe_ipc presets > "$BEFORE"
assert_unique_preset_names "$BEFORE"
python3 - "$BEFORE" "$ORIG" <<'PY' || fail "presets() shape"
import json, sys
rows = json.load(open(sys.argv[1]))
owner = json.load(open(sys.argv[2]))
key = lambda r: str(r.get("name", "")).strip().lower()
names = [key(r) for r in rows]
assert names, "presets() is empty"
for r in rows:
    assert r.get("id"), "a row without an id: %r" % r
# At most one row carries the active mark - two would be a bug. None is honest:
# the default look on a fresh config matches no preset, so no row is active.
active = [r for r in rows if r.get("active")]
assert len(active) <= 1, "expected at most one active row, got %d" % len(active)
shipped = {key(r) for r in rows if r.get("builtin")}
saved = {key(r) for r in rows if not r.get("builtin")}
assert shipped, "no shipped look is listed"
given = {key(p) for p in (owner.get("presets") or [])}
assert given <= saved, "saved presets missing from the list: %s" % sorted(given - saved)
clash = sorted(given & shipped)
assert not clash, "a name is a shipped look and a saved preset at once: %s" % clash
print("   %d rows: %d shipped + %d saved, one name each, active = %s"
      % (len(rows), len(shipped), len(saved), active[0]["id"] if active else "none (the look on screen matches no preset)"))
PY

# ---------------------------------------------------------------------------
# The dock under the probe is a real one: it answers the surface the running
# dock answers, from its own config copy. Cheap, and it is what tells a broken
# harness (a dock that never loaded, or one whose settings panel was left open)
# apart from a broken assertion.
#
# What it cannot show: items. A dock that is not visible builds none - `items`
# is 0 and itemGeometry is [] for as long as the probe stays hidden, which is
# the whole point of the probe. Geometry assertions that need real items belong
# on the running dock (tests/live/layout.sh, tests/live/indicators.sh), so only
# the shape is asserted here.
echo "-- the dock under the probe is live and answering"
probe_ipc state | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert isinstance(d.get("docks"), int) and d["docks"] >= 1, "docks: %r" % d.get("docks")
assert d.get("visible") is False, "the probe must stay hidden"
assert d.get("settingsOpen") is False, "the probe must keep its settings panel closed"
assert isinstance(d.get("items"), int) and d["items"] >= 0, "items: %r" % d.get("items")
assert isinstance(d.get("activePreset"), str), "activePreset: %r" % d.get("activePreset")
assert isinstance(d.get("layout"), str) and d["layout"], "layout: %r" % d.get("layout")
print("   state: %d dock(s), hidden, %d item(s) while hidden, layout=%s"
      % (d["docks"], d["items"], d["layout"]))
' || fail "state shape"
probe_ipc itemGeometry | python3 -c '
import json, sys
items = json.load(sys.stdin)
assert isinstance(items, list), "itemGeometry is not a list: %r" % type(items).__name__
for i in items:
    assert isinstance(i.get("x"), (int, float)) and isinstance(i.get("w"), (int, float)), i
print("   itemGeometry: %d item(s) (a hidden dock builds none)" % len(items))
' || fail "itemGeometry shape"

# ---------------------------------------------------------------------------
echo "-- applyPreset by name, every shipped look"
python3 - "$BEFORE" <<'PY' > "$WORK/shipped-looks.tsv"
import json, sys
for r in json.load(open(sys.argv[1])):
    if r.get("builtin"):
        print("%s\t%s" % (r["name"], r["id"]))
PY
while IFS=$'\t' read -r name id; do
  [ -n "$name" ] || continue
  out=$(probe_ipc applyPreset "$name")
  [ "$out" = "ok" ] || fail "applyPreset \"$name\" -> $out"
  sleep 0.7
  active=$(probe_ipc state | python3 -c 'import json,sys; print(json.load(sys.stdin)["activePreset"])')
  # Applying a look puts exactly one row on the active mark, and it is that row.
  [ "$active" = "$id" ] || fail "after applying \"$name\" the active row is \"$active\", expected \"$id\""
  probe_ipc presets | python3 -c '
import json, sys
rows = json.load(sys.stdin)
marked = [r["id"] for r in rows if r.get("active")]
assert marked == [sys.argv[1]], "active rows after apply: %s" % marked
' "$id" || fail "\"$name\" left the wrong number of active rows"
  echo "   applyPreset \"$name\" -> ok (active $active)"
done < "$WORK/shipped-looks.tsv"

# The two name looks must land their label keys, not just take the active mark:
# a preset's label look is applied through DockLabels.pickLabelLook, which keeps
# a value only when it is one the labels accept.
echo "-- the shipped looks reach the config"
for spec in "macOS:hover:pill:theme" "Windows:off:none:theme"; do
  IFS=: read -r name mode bg font <<<"$spec"
  out=$(probe_ipc applyPreset "$name")
  [ "$out" = "ok" ] || fail "applyPreset \"$name\" -> $out"
  sleep 1.2
  python3 - "$CFG" "$name" "$mode" "$bg" "$font" <<'PY' || fail "the $name look did not reach the config"
import json, sys
cfg = json.load(open(sys.argv[1]))
name, mode, bg, font = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
if name == "Windows":
    assert (cfg.get("layout"), cfg.get("alignment"), cfg.get("autohide"), cfg.get("showMinimizedTiles")) == ("panel", "center", False, False), "taskbar setup"
for field, want in (("labelMode", mode), ("labelBackground", bg), ("labelFont", font)):
    got = cfg.get(field)
    assert got == want, "%s: %s is %r, expected %r" % (name, field, got, want)
print("   %s applied: labelMode=%s labelBackground=%s labelFont=%s"
      % (name, mode, bg, font))
PY
done

echo "-- a name is required, an id is not one"
[ "$(probe_ipc applyPreset "no-such-look-xyz")" = "not found" ] || fail "an unknown name must answer not found"
first_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["id"])' "$BEFORE")
[ "$(probe_ipc applyPreset "$first_id")" = "not found" ] \
  || fail "applyPreset takes the documented name; ids belong to presets()/deletePreset"

# ---------------------------------------------------------------------------
# Deleting. The copy is disposable, so this may remove a real saved preset too -
# which is the case that matters: a removal must not take the others with it.
echo "-- save then remove leaves everything else alone"
ensure_slot || fail "could not make room for a saved preset"
python3 - "$CFG" <<'PY' > "$WORK/before-delete.json"
import json, sys
conf = json.load(open(sys.argv[1]))
print(json.dumps({"presets": conf.get("presets") or [], "keys": sorted(conf.keys())}))
PY
pid=$(probe_ipc savePreset "verify_live_presets")
[ -n "$pid" ] || fail "savePreset returned no id"
probe_ipc presets | python3 -c '
import json, sys
rows = json.load(sys.stdin)
assert any(r["id"] == sys.argv[1] and not r.get("builtin") for r in rows), "the saved preset is not listed"
' "$pid" || fail "presets() does not list the preset just saved"
[ "$(probe_ipc deletePreset "$pid")" = "ok" ] || fail "deletePreset"
[ "$(probe_ipc deletePreset "$pid")" = "not found" ] || fail "deletePreset twice must answer not found"
# The removal reaches the file a moment after the call returns.
probe_wait_presets out "$pid"
bid=$(python3 -c 'import json,sys; print([r["id"] for r in json.load(open(sys.argv[1])) if r.get("builtin")][0])' "$BEFORE")
[ "$(probe_ipc deletePreset "$bid")" = "not found" ] || fail "a shipped look must not be removable"
python3 - "$CFG" "$WORK/before-delete.json" <<'PY' || fail "save-then-remove disturbed the config"
import json, sys
conf = json.load(open(sys.argv[1]))
before = json.load(open(sys.argv[2]))
assert conf.get("presets") == before["presets"], "save-then-remove changed the saved presets"
assert sorted(conf.keys()) == before["keys"], "save-then-remove changed the config keys"
print("   saved, listed, removed: %d saved presets and %d config keys unchanged"
      % (len(before["presets"]), len(before["keys"])))
PY

echo "-- removing a saved preset keeps the others"
saved_ids=$(python3 -c 'import json,sys; print(" ".join(p["id"] for p in json.load(open(sys.argv[1]))["presets"]))' "$WORK/before-delete.json")
if [ -z "$saved_ids" ]; then
  echo "   (no saved preset in this config to remove - the save/remove path above covers it)"
else
  victim=$(echo "$saved_ids" | awk '{print $1}')
  rows_before=$(probe_ipc presets | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
  [ "$(probe_ipc deletePreset "$victim")" = "ok" ] || fail "deletePreset \"$victim\""
  probe_wait_presets out "$victim"
  probe_ipc presets > "$WORK/presets-after.json"
  assert_unique_preset_names "$WORK/presets-after.json"
  python3 - "$WORK/presets-after.json" "$WORK/before-delete.json" "$victim" <<'PY' || fail "removal lost other presets"
import json, sys
after = json.load(open(sys.argv[1]))
before = json.load(open(sys.argv[2]))
victim = sys.argv[3]
ids = [r["id"] for r in after]
assert victim not in ids, "the removed preset is still listed"
expected = [p["id"] for p in before["presets"] if p["id"] != victim]
missing = [i for i in expected if i not in ids]
assert not missing, "removal took other presets with it: %s" % missing
print("   removed %s; still listed: %s" % (victim, expected))
PY
  python3 - "$CFG" "$WORK/before-delete.json" "$victim" <<'PY' || fail "the config rewrite is wrong"
import json, sys
conf = json.load(open(sys.argv[1]))
before = json.load(open(sys.argv[2]))
victim = sys.argv[3]
ids = [p["id"] for p in conf.get("presets") or []]
assert victim not in ids, "the removed preset is still in the config"
expected = [p["id"] for p in before["presets"] if p["id"] != victim]
assert ids == expected, "the config holds %s, expected %s" % (ids, expected)
assert sorted(conf.keys()) == before["keys"], "the rewrite changed the config keys"
assert not any(p.get("builtin") for p in conf["presets"]), "a shipped look was written into the config"
print("   config holds %s, %d keys, no shipped look" % (ids, len(conf.keys())))
PY
  # The mark must land somewhere real: after removing the active preset the dock
  # either matches no preset or matches one that is listed.
  active=$(probe_ipc state | python3 -c 'import json,sys; print(json.load(sys.stdin)["activePreset"])')
  python3 - "$WORK/presets-after.json" "$active" <<'PY' || fail "activePreset points at a row that is not listed"
import json, sys
rows = json.load(open(sys.argv[1]))
active = sys.argv[2]
ids = {r["id"] for r in rows}
assert active == "" or active in ids, "activePreset %r is not in %s" % (active, sorted(ids))
print("   activePreset after the removal: %r" % active)
PY
  [ "$(probe_ipc presets | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" = "$((rows_before - 1))" ] \
    || fail "the list did not shrink by exactly one row"
  echo "   the list shrank $rows_before -> $((rows_before - 1))"
fi

# ---------------------------------------------------------------------------
# A hostile name is persisted data too: DockModel bounds it (MAX_PRESET_NAME,
# read from the module above) and strips control and bidi characters. If that
# bound were ever dropped, a 10k name would land in omadock.json - this is the
# live guard for it.
echo "-- a hostile preset name is stored bounded and clean"
ensure_slot 2 || fail "could not make room for two saved presets"
probe_ipc presets > "$WORK/rows-before-names.json"
hid=$(probe_ipc savePreset "$(python3 -c 'print("x" * 10000)')")
[ -n "$hid" ] || fail "savePreset with a 10k name"
did=$(probe_ipc savePreset "$(printf 'evil\xe2\x80\xaename\x01here')")
[ -n "$did" ] || fail "savePreset with a control/bidi name"
probe_wait_presets in "$hid" "$did"
python3 - "$CFG" "$hid" "$did" "$MAX_PRESET_NAME" <<'PY' || fail "a saved name is unbounded or unclean"
import json, re, sys
cfg = json.load(open(sys.argv[1]))
bound = int(sys.argv[4])
byid = {p["id"]: p for p in cfg.get("presets") or []}
bad = re.compile("[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069]")
for pid, keep in ((sys.argv[2], "x"), (sys.argv[3], "evil")):
    p = byid.get(pid)
    assert p, "the preset was not stored under its id %s" % pid
    name = p["name"]
    assert len(name) <= bound, "name of %d characters was stored unbounded (bound %d)" % (len(name), bound)
    assert name == name.strip() and name, "name %r is not trimmed and non-empty" % name
    assert not bad.search(name), "name %r kept control or bidi characters" % name
    assert keep in name, "name %r lost its visible text" % name
print("   names stored: %r, %r" % (byid[sys.argv[2]]["name"], byid[sys.argv[3]]["name"]))
PY
for id in "$hid" "$did"; do
  [ "$(probe_ipc deletePreset "$id")" = "ok" ] || fail "deletePreset $id after the name check"
done
probe_wait_presets out "$hid" "$did"
assert_unique_preset_names "$CFG"
python3 - "$CFG" "$WORK/rows-before-names.json" "$MAX_PRESET_NAME" <<'PY' || fail "the name check did not clean up after itself"
import json, sys
cfg = json.load(open(sys.argv[1]))
rows_before = json.load(open(sys.argv[2]))
bound = int(sys.argv[3])
saved = [p["name"] for p in cfg.get("presets") or []]
want = len([r for r in rows_before if not r.get("builtin")])
assert len(saved) == want, "%d saved preset(s) left, expected %d" % (len(saved), want)
assert not any("x" * (bound + 1) in n for n in saved), "an unbounded name survived: %s" % saved
print("   cleaned up: %d saved preset(s) left, %d config keys" % (len(saved), len(cfg)))
PY

# ---------------------------------------------------------------------------
# An edit made outside the dock must still be applied. The dock holds back a
# read older than its own last write, and that hold-off is bounded on purpose:
# this is the case that would break if it were not (the live layout test and a
# hand edit of omadock.json both rely on an outside change landing).
echo "-- an outside edit still reaches the dock"
want=$(python3 - "$CFG" <<'PY'
import json, sys
path = sys.argv[1]
conf = json.load(open(path))
conf["alignment"] = "right" if conf.get("alignment") != "right" else "left"
json.dump(conf, open(path, "w"), indent=2)
print(conf["alignment"])
PY
)
for _ in $(seq 20); do
  [ "$(probe_ipc state | python3 -c 'import json,sys; print(json.load(sys.stdin)["align"])')" = "$want" ] && break
  sleep 0.3
done
[ "$(probe_ipc state | python3 -c 'import json,sys; print(json.load(sys.stdin)["align"])')" = "$want" ] \
  || fail "an edit to omadock.json made outside the dock never reached it (wanted $want)"
echo "   alignment set to $want outside the dock and picked up"

# ---------------------------------------------------------------------------
# The dock reads its config through a gate; a read that catches the file
# mid-write used to come back as a truncated prefix, and the dock's answer to
# that parse failure is defaults - which emptied the preset list right after a
# preset was saved. A torn read leaves this line in the log.
echo "-- omadock.json was never read mid-write"
if grep -q "Failed parsing omadock.json" "$PROBE_DIR/probe.log"; then
  grep -m 3 "Failed parsing omadock.json" "$PROBE_DIR/probe.log" | sed 's/^/   /' >&2
  fail "the dock parsed a torn omadock.json during the suite"
fi
echo "   no parse failure in the dock's log"

# The other half of what the running-dock suite used to assert: the dock's own
# log stays clean while all of the above runs through it. A QML exception the
# dock survives is still a defect.
echo "-- the dock's log is clean"
if grep -inE "(TypeError|ReferenceError|is not a function|is not defined|Unable to assign)" "$PROBE_DIR/probe.log" | head -5 > "$WORK/log-errors.txt" && [ -s "$WORK/log-errors.txt" ]; then
  sed 's/^/   /' "$WORK/log-errors.txt" >&2
  fail "runtime errors in the dock's log"
fi
echo "   no runtime error in the dock's log"

echo "-- the probe's own copy is still a valid config"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$CFG" || fail "the config copy is not valid JSON"

echo
probe_cleanup || exit 1
headless_stop || fail "the monitor list did not come back"
echo "PRESETS PASSED"
