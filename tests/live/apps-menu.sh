#!/usr/bin/env bash
# Live (NON-INTRUSIVE): the Windows preset's apps button, end to end.
#
# The punch list for this row has three parts, and this is the proof of each:
#
#  * pressing Start opens a surface anchored to that button - above it, with
#    the same 6px gap the dock's other popups leave - instead of the centred
#    Omarchy menu. The suite applies the Windows preset by name, presses the
#    button through the very function its click handler calls
#    (sharedState.appGrid.openLauncher), and reads the window and the panel out
#    of the running dock: the surface's centre over the button's centre, the
#    panel's box inside it, the gap to the card, and the app rows it lists.
#    A before/after `grim` capture of the headless output proves the panel is
#    on the output and the gap strip between it and the card is still
#    wallpaper.
#  * the preset pins its own `appsButtonAction`. A stale "grid" is written into
#    the probe's config copy and observed to reach the dock (mode == "grid"),
#    then the Windows preset is applied again and the dock is seen to come back
#    as "start" both in memory and in the file it saves. Applying macOS is then
#    seen to pin "menu" again - the other looks behave as they did.
#  * the close paths leave no stuck window: Esc (a real key, sent with wtype
#    only while the popup holds the keyboard grab, so it can never reach the
#    owner's focused window), a press on the button again, and another surface
#    taking the focus - which is exactly the compositor event a click
#    elsewhere produces, and what the popup's own focus grab reports.
#
# Everything runs on a disposable headless output (tests/live/headless.sh) with
# a second Quickshell instance running this tree's DockHost.qml against a copy
# of the config (tests/live/probe.sh). The owner's config is only read; its md5,
# monitor list and shell PID are re-checked at exit, and no probe process,
# headless output or scratch directory may survive.
#
# Fails closed: no headless output, no grim, no wtype, a probe that lands on a
# real output, or a popup whose grab never engages are failures, never passes.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

OWNER_CFG="${HOME}/.config/omarchy/omadock.json"
WORK=""
SCREEN=""
STALE_CFG=""

# The probe's source is the owner's config with a value saved on another
# machine - "grid" - so the first read proves the dock honors what it finds
# and the preset below proves it overrides it. The owner's file is only read.
STALE_CFG=$(mktemp "${TMPDIR:-/tmp}/omadock-apps-stale-XXXXXX") || exit 1
python3 - "$OWNER_CFG" "$STALE_CFG" <<'PY' || exit 1
import json, sys
c = json.load(open(sys.argv[1]))
c["appsButtonAction"] = "grid"
json.dump(c, open(sys.argv[2], "w"), indent=2)
PY
PROBE_CFG_SRC="$STALE_CFG"
export PROBE_CFG_SRC

# shellcheck source=tests/live/headless.sh
. tests/live/headless.sh
headless_start "$STALE_CFG" || exit 1
# shellcheck source=tests/live/probe.sh
. tests/live/probe.sh

cleanup() {
  if declare -F probe_cleanup >/dev/null; then probe_cleanup >/dev/null 2>&1; fi
  headless_stop >/dev/null 2>&1
  [ -n "$STALE_CFG" ] && rm -f "$STALE_CFG"
}
trap cleanup EXIT

fail() {
  echo "APPS-MENU FAILED: $*" >&2
  [ -n "$WORK" ] && probe_log_tail >&2
  probe_cleanup >/dev/null 2>&1
  headless_stop >/dev/null 2>&1
  exit 1
}
note() { echo "   $*"; }

command -v grim >/dev/null || fail "cannot verify the panel's pixels: grim is not installed"
command -v wtype >/dev/null || fail "cannot verify the Esc close path: wtype is not installed"

# The name Hyprland actually gave the disposable output (it may truncate the
# requested one); grim and the report use the real name.
SCREEN=$(hyprctl -j monitors | python3 -c '
import json, sys
owner = set(sys.argv[1].replace("*", "").split())
print(next(m["name"] for m in json.load(sys.stdin) if m["name"] not in owner))' "$HEADLESS_OWNER_MONITORS") \
  || fail "could not name the headless output"

PROBE_BODY="$PWD/tests/live/apps-menu-shell.qml"
export PROBE_BODY
probe_start || { probe_cleanup >/dev/null 2>&1; exit 1; }
# probe_start recorded the synthetic copy as the "owner" it re-checks; point
# that back at the real file so the exit check guards the user's config.
PROBE_OWNER_CFG="$OWNER_CFG"
PROBE_OWNER_MD5=$(md5sum "$OWNER_CFG" | cut -d' ' -f1)

WORK="$PROBE_DIR/work"
mkdir -p "$WORK"
CFG=$(probe_cfg)

ipc_test() { qs -p "$PROBE_DIR" ipc call omadock-test "$@"; }
read_state() { ipc_test read > "$WORK/state.json"; }
press() { ipc_test press >/dev/null; }

# The panel is fully in (the rise animation done: the body's gap to the card
# is only its own once the level has reached 1).
wait_open() {
  local i
  for i in $(seq 30); do
    read_state
    python3 - "$WORK/state.json" <<'PY' && return 0
import json, sys
s = json.load(open(sys.argv[1]))
sys.exit(0 if s.get("open") and s.get("hasBody") and (s.get("win") or {}).get("level") == 1 else 1)
PY
    sleep 0.1
  done
  return 1
}
# And fully gone: no window and no open flag. The fade holds the window for a
# moment, which is not a stuck window.
wait_closed() {
  local i
  for i in $(seq 30); do
    read_state
    python3 - "$WORK/state.json" <<'PY' && return 0
import json, sys
s = json.load(open(sys.argv[1]))
sys.exit(0 if s.get("open") is False and s.get("hasWindow") is False else 1)
PY
    sleep 0.1
  done
  return 1
}

# The config copy holds the value under test, written by the dock itself.
cfg_value() {
  python3 - "$CFG" "$1" <<'PY'
import json, sys
print(json.load(open(sys.argv[1])).get(sys.argv[2]))
PY
}
# The preset the Presets list marks active, by name. The apps action is part
# of a preset's setup, so this is what proves the pinned key also takes part in
# active detection (a preset that changes it must be able to report itself).
preset_active() {
  probe_ipc presets | python3 -c '
import json, sys
name = sys.argv[1]
rows = json.load(sys.stdin)
match = [r for r in rows if r.get("name") == name]
sys.exit(0 if match and match[0].get("active") else 1)' "$1"
}

# Wait until the dock has saved a key in its config copy (~8 s).
wait_cfg() {
  probe_wait_cfg 'import json,sys
c = json.load(open(sys.argv[1]))
sys.exit(0 if str(c.get(sys.argv[2])) == sys.argv[3] else 1)' "$1" "$2" \
    || fail "the dock never saved $1 = $2 (file holds $(cfg_value "$1"))"
}

# ---------------------------------------------------------------- predicates
assert_state() {
  python3 - "$WORK/state.json" "$@" <<'PY' || fail "state: $*"
import json, sys
s = json.load(open(sys.argv[1]))
conds = sys.argv[2:]
for c in conds:
    key, want = c.split("=", 1)
    got = s.get(key)
    assert str(got) == want, "%s: expected %r, got %r" % (key, want, got)
PY
}

# The measured placement: the panel's centre over the button's centre, and the
# panel's bottom exactly the surface's gap above the card's top.
assert_anchored() {
  python3 - "$WORK/state.json" <<'PY' || fail "the panel is not anchored over the apps button"
import json, sys
s = json.load(open(sys.argv[1]))
assert s.get("open") and s.get("hasWindow") and s.get("hasBody"), "no open window/panel"
assert s.get("panelVisible"), "the panel is not visible"
assert s.get("buttonVisible"), "the apps button is not visible to anchor to"
dx = s.get("dx")
assert abs(dx) <= 1, "the panel's centre is %.1fpx off the button's centre" % dx
gap, want = s.get("gap"), s["win"]["gap"]
assert gap == want, "the gap above the card is %s px, the popup rule is %s" % (gap, want)
assert s["apps"] > 0, "the panel lists no apps"
assert s["body"]["w"] > 0 and s["body"]["h"] > 0, "the panel has no box"
assert s["bodyScreen"]["y"] + s["bodyScreen"]["h"] <= s["cardTop"], "the panel overlaps the dock card"
print("   panel %dx%d at %d,%d (screen %dx%d): centre dx %dpx over the button, gap %dpx above the card, %d apps"
      % (s["body"]["w"], s["body"]["h"], s["bodyScreen"]["x"], s["bodyScreen"]["y"],
         s["win"]["w"], s["screenHeight"], round(dx), gap, s["apps"]))
PY
}

# The app rows are alphabetical and each desktop entry once (the app list is
# the floor; a repeated id would mean the panel, not the model, is wrong).
# Display names may repeat: two entries can legitimately share one.
assert_names() {
  ipc_test names > "$WORK/names.json"
  python3 - "$WORK/names.json" <<'PY' || fail "the panel's app rows are not a clean alphabetical list"
import json, sys
rows = json.load(open(sys.argv[1]))
assert len(rows) > 0, "no rows"
ids = [r["id"] for r in rows]
assert len(set(ids)) == len(ids), "an entry is listed twice"
names = [r["name"] for r in rows]
low = [n.lower() for n in names]
assert low == sorted(low), "the rows are not alphabetical"
print("   %d entries, alphabetical, each id once (first %r, last %r)"
      % (len(rows), names[0], names[-1]))
PY
}

# ---------------------------------------------------------------- pixels
# Capture the whole headless output; the panel's screen box and the strip
# between it and the card are compared before and after opening.
capture() { timeout 10 grim -o "$SCREEN" -t ppm "$WORK/$1" || fail "grim could not capture $SCREEN"; }

# The dock window spans the output, so the panel's dock-window-space box maps
# to screen pixels by shifting it down past the window's top and scaling.
assert_pixels() {
  python3 - "$WORK/before.ppm" "$WORK/after.ppm" "$WORK/state.json" <<'PY' || fail "the panel is not on the output where the dock says it is"
import json, sys

def read_ppm(path):
    with open(path, "rb") as f:
        assert f.readline().strip() == b"P6", "not a P6 ppm"
        line = f.readline()
        while line.startswith(b"#"):
            line = f.readline()
        w, h = map(int, line.split())
        assert int(f.readline()) == 255, "unexpected ppm range"
        return w, h, f.read()

w, h, a = read_ppm(sys.argv[1])
w2, h2, b = read_ppm(sys.argv[2])
assert (w, h) == (w2, h2), "the captures differ in size"
s = json.load(open(sys.argv[3]))
scale = w / float(s["windowWidth"])
top = h - round(s["windowHeight"] * scale)
bx = round(s["bodyScreen"]["x"] * scale)
by = top + round(s["bodyScreen"]["y"] * scale)
bw = round(s["bodyScreen"]["w"] * scale)
bh = round(s["bodyScreen"]["h"] * scale)
assert bx >= 0 and by >= 0 and bx + bw <= w and by + bh <= h, "the panel's box leaves the output"

def changed(x, y):
    i = (y * w + x) * 3
    return abs(a[i] - b[i]) + abs(a[i + 1] - b[i + 1]) + abs(a[i + 2] - b[i + 2]) > 12

inside = sum(1 for y in range(by, by + bh, 8) for x in range(bx, bx + bw, 8))
inside_changed = sum(1 for y in range(by, by + bh, 8) for x in range(bx, bx + bw, 8) if changed(x, y))
assert inside > 0, "the panel's box is empty"
ratio = inside_changed / float(inside)
assert ratio >= 0.90, "only %.0f%% of the panel's box was drawn over the wallpaper" % (ratio * 100)

# The gap strip: the rows just above the card between the panel's bottom and
# the card's top must be untouched wallpaper - the surface is not flush with
# the dock.
gap_px = round(s["win"]["gap"] * scale)
gx0, gx1 = bx + bw // 4, bx + bw * 3 // 4
gy0, gy1 = by + bh + 1, by + bh + gap_px
gap_total = gap_changed = 0
for y in range(gy0, gy1):
    for x in range(gx0, gx1, 2):
        gap_total += 1
        gap_changed += 1 if changed(x, y) else 0
assert gap_total == 0 or gap_changed == 0, "the %dpx gap strip was covered by the surface" % gap_px
print("   %.0f%% of the panel's %dx%d box drawn over the wallpaper; the %dpx gap strip is untouched"
      % (ratio * 100, bw, bh, gap_px))
PY
}

# ---------------------------------------------------------------- steps
echo "-- the Windows preset pins its action, over a stale saved value"
read_state
assert_state mode=grid open=False
note "the config said grid (saved on another machine) and the dock took it: mode = grid"

probe_ipc applyPreset Windows >/dev/null || fail "applyPreset Windows was refused"
wait_cfg appsButtonAction start
note "applied: appsButtonAction = start, alignment = $(cfg_value alignment), autohide = $(cfg_value autohide)"

read_state
assert_state mode=start
preset_active Windows || fail "the Windows look is not marked active after applying it"
note "the preset won: mode = start, saved back as start, and the look is marked active"

echo "-- pressing the apps button opens the anchored panel"
# The taskbar's card and dock may still be settling from the preset switch;
# the before-frame is the resting desktop, not that motion.
sleep 0.8
capture before.ppm
press
wait_open || fail "the panel never finished opening"
assert_state open=True hasWindow=True hasBody=True mode=start
assert_anchored
assert_names
capture after.ppm
assert_pixels
note "screenshot: $WORK/after.ppm (the panel over the Start button, gap and all)"

echo "-- the second press closes it, with no stuck window"
press
wait_closed || fail "the second press left the panel open"
assert_state open=False hasWindow=False
note "closed by the button's own path; the window went with it"

echo "-- Esc closes it (sent only while the popup holds the keyboard grab)"
press
wait_open || fail "the panel did not open for the Esc step"
assert_state open=True
python3 - "$WORK/state.json" <<'PY' || fail "the popup never took the keyboard grab, so Esc was not sent"
import json, sys
s = json.load(open(sys.argv[1]))
sys.exit(0 if s["win"]["grab"] else 1)
PY
wtype -k Escape || fail "wtype could not send Escape"
wait_closed || fail "Escape did not close the panel"
assert_state open=False hasWindow=False
note "Escape closed it; no window left behind"

echo "-- another surface taking the focus closes it (the click-elsewhere path)"
press
wait_open || fail "the panel did not open for the click-elsewhere step"
assert_state open=True
probe_ipc openSettings >/dev/null || fail "could not open the settings panel on the probe"
wait_closed || fail "the focused settings surface did not dismiss the panel"
assert_state open=False hasWindow=False
probe_ipc closeSettings >/dev/null || fail "could not close the probe's settings panel"
note "the focus grab was cleared by the focused surface (a click elsewhere does the same); the panel went"

echo "-- the macOS look still opens the Omarchy menu"
probe_ipc applyPreset macOS >/dev/null || fail "applyPreset macOS was refused"
wait_cfg appsButtonAction menu
read_state
assert_state mode=menu open=False hasWindow=False
preset_active macOS || fail "the macOS look is not marked active after applying it"
note "applied: appsButtonAction = menu (the Omarchy menu branch, untouched), macOS active; no anchored window"

echo "-- back to Windows: the action follows the preset both ways"
probe_ipc applyPreset Windows >/dev/null || fail "applyPreset Windows (return) was refused"
wait_cfg appsButtonAction start
read_state
assert_state mode=start open=False
note "Windows again: mode = start"

echo "-- the log stayed clean"
if grep -nE "TypeError|ReferenceError|is not a function|is not defined|Cannot read|Unable to assign" "$(probe_log)" > "$WORK/log-errors"; then
  cat "$WORK/log-errors" >&2
  fail "runtime errors in the dock's log"
fi
note "no runtime errors"

echo "-- teardown"
probe_cleanup || fail "teardown left something behind or the owner's side changed"
headless_stop || fail "the headless output did not go away"
note "monitors back to: $(hyprctl monitors | grep -c '^Monitor')"
rm -f "$STALE_CFG"; trap - EXIT
echo "APPS-MENU PASSED"
