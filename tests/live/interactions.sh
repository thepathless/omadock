#!/usr/bin/env bash
# Live (NON-INTRUSIVE): the dock's interactive paths, driven on a headless
# output, with the log watched and the pixels checked.
#
# The other live suites drive the dock's IPC and its config. None of them ever
# touched the paths a *pointer* opens - the context menu, the rename field
# inside a folder's menu, the app group popup, the settings panel - which are
# exactly the surfaces the Qt 6.12 `Color` shadowing broke (undefined colours
# are read when those components instantiate, not when the dock loads). This
# suite closes that gap without a pointer on the owner's screen:
#
#   * `hyprctl output create headless` gives Hyprland a real output with no
#     glass attached. The probe's dock is pinned to it by the suite's own
#     config copy (`screen` + multiMonitor false), so every surface this suite
#     opens - menus, popups, the full-screen settings overlay - renders there
#     and only there. The owner's monitor keeps focus; its dock is untouched.
#   * tests/live/interactions-shell.qml (the probe's PROBE_BODY) drives the
#     paths through the very functions the tiles' click handlers call, and
#     reports each surface's own resolved colours. Every step refuses to open
#     anything unless the dock is on the headless output (PROBE_SCREEN).
#   * each surface is checked twice: the values it draws with (the menus and
#     the settings panel against the shell's own palette read through a
#     qualified import; the group popup against the dock's material it now
#     borrows); and the rendered pixels, cropped from `grim -o <output>`
#     before and after - the colours have to be on the output, not just in
#     the properties.
#
# The dock's log must stay clean through all of it (no TypeError /
# ReferenceError / is not a function / is not defined / Cannot read property /
# Unable to assign), the probe's config copy must be byte-identical afterwards
# (the rename is cancelled, nothing is committed), and the owner's side is
# re-checked at exit: config md5, monitor list and focus, its own dock's state,
# shell PID, no surviving process or scratch directory and no headless output.
#
# Fails closed: a compositor without headless outputs, a missing grim, a
# probe that lands anywhere but the headless output - each is a failure, never
# a silent pass.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

SCREEN="omadock-probe"
OWNER_CFG="${HOME}/.config/omarchy/omadock.json"
SRC_CFG=$(mktemp "${TMPDIR:-/tmp}/omadock-interactions-cfg-XXXXXX") || exit 1
# The folder step's precondition, owned by the suite: a directory a pinned
# folder can point at. A pin is the only thing that puts a folder tile on the
# dock (DockConfigLogic's ~/Downloads fallback runs only when the key is absent
# entirely, not when it holds an empty list), so on a config that pins none the
# step could never reach its target whatever the code did. The config copy
# below pins this directory unless the source config already pins one of its
# own, and the source file itself is never written.
FOLDER_DIR=$(mktemp -d "${TMPDIR:-/tmp}/omadock-interactions-folder-XXXXXX") || exit 1
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
# The owner's own dock: its visibility and how many docks its shell runs. The
# item count is deliberately not compared - the owner is using the desktop
# while this suite runs and their window list moves on its own.
owner_dock_state() {
  qs -p /usr/share/omarchy/shell ipc call omadock state 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("visible"), d.get("docks"))'
}

# Nothing of this suite may outlive it: the probe, the headless output, the
# two scratch files. probe_cleanup also re-checks the owner's side.
cleanup() {
  if declare -F probe_cleanup >/dev/null; then probe_cleanup >/dev/null 2>&1; fi
  [ -n "$HAVE_OUTPUT" ] && hyprctl output remove "$SCREEN" >/dev/null 2>&1
  rm -f "$SRC_CFG"
  [ -n "$FOLDER_DIR" ] && rm -rf "$FOLDER_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------- pre-flight
echo "-- pre-flight: a headless output to run on, the owner watching"
if hyprctl monitors 2>/dev/null | grep -qE "^(Monitor|  )?${SCREEN}\b"; then
  echo "   REFUSING: an output named $SCREEN already exists" >&2
  exit 1
fi
command -v grim >/dev/null || { echo "   cannot verify pixels: grim is not installed" >&2; exit 1; }
command -v hyprctl >/dev/null || { echo "   cannot run: no hyprctl on PATH" >&2; exit 1; }
OWNER_MD5=$(owner_md5)
OWNER_MONITORS=$(monitor_state)
OWNER_DOCK=$(owner_dock_state)

# The probe's config source: the owner's config, pinned to the headless output
# and to a single dock. probe.sh copies this file and never reads the owner's
# again, so the suite re-checks the real one itself at the end.
python3 - "$OWNER_CFG" "$SRC_CFG" "$SCREEN" "$FOLDER_DIR" <<'PY' || exit 1
import json, sys
conf = json.load(open(sys.argv[1]))
conf["screen"] = sys.argv[3]
conf["multiMonitor"] = False
# The copy must carry a pinned folder for the folder-menu step, and it may not
# borrow one from a desktop that has none. The source config stays the source
# of everything else - its look, its groups, its app list - so the probe still
# renders like the owner's dock; only a missing precondition is supplied.
pins = conf.get("pinnedFolders")
if isinstance(pins, list) and pins:
    print("   config copy keeps the %d pinned folder(s) it inherited" % len(pins))
else:
    conf["pinnedFolders"] = [{"path": sys.argv[4], "name": "Probe Folder", "icon": "folder"}]
    print("   config copy pinned %s for the folder-menu step" % sys.argv[4])
# A group tile needs a group, and the desk's own are used when it has any. The
# probe group starts empty; the fixture adds an app to it (through the dock's
# own addAppToGroup) only while it is still empty, so the group popup has tiles
# to draw on a desk that has no groups of its own.
groups = conf.get("appGroups")
if isinstance(groups, list) and groups:
    print("   config copy keeps the %d app group(s) it inherited" % len(groups))
else:
    conf["appGroups"] = [{"id": "omadock_probe_group", "name": "Probe Group",
                          "icon": "folder", "apps": [], "cols": 2, "before": ""}]
    print("   config copy added a probe group for the group steps")
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
PROBE_BODY="$PWD/interactions-shell.qml"
PROBE_SCREEN="$SCREEN"
export PROBE_CFG_SRC PROBE_BODY PROBE_SCREEN
# shellcheck source=tests/live/probe.sh
. ./probe.sh

WORK=""   # set below, inside the probe dir (removed with it)
probe_test() { qs -p "$PROBE_DIR" ipc call omadock-test "$@"; }
step() {
  local out
  out=$(probe_test run "$1" "${2:-}" 2>/dev/null) || return 1
  printf '%s' "$out"
}
jval() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get(sys.argv[1])))' "$2"; }
# A JSON value as plain text, for a colour or a note (no quotes).
jstr() { printf '%s' "$1" | python3 -c 'import json,sys
v = json.load(sys.stdin).get(sys.argv[1])
print(v if isinstance(v, str) else json.dumps(v))' "$2"; }
expect_true() { [ "$(jval "$2" "$3")" = "true" ] || fail "$1"; }
expect_eq() { [ "$(jval "$2" "$3")" = "$4" ] || fail "$1 ($3=$(jval "$2" "$3"), wanted $4)"; }
expect_at_least() { python3 -c 'import json,sys
sys.exit(0 if json.loads(sys.argv[1]).get(sys.argv[2], 0) >= int(sys.argv[3]) else 1)' \
  "$2" "$3" "$4" || fail "$1 ($3=$(jval "$2" "$3"))"; }
expect_empty() { [ "$(jval "$2" "$3")" = "[]" ] || fail "$1 ($3=$(jval "$2" "$3"))"; }

# The runtime errors the dock must not log, and a guard that fires per surface
# rather than only once at the end: every section records the count before it
# drives anything and demands the same count after, so a fault names the
# surface it came from.
ERR_RE="(TypeError|ReferenceError|is not a function|is not defined|Cannot read property|Unable to assign)"
errs_now() { grep -icE "$ERR_RE" "$PROBE_DIR/probe.log" 2>/dev/null || true; }
log_since() {   # log_since <count-before> <what>
  local now; now=$(errs_now)
  [ "$now" = "$1" ] || fail "$2: the dock's log gained $((now - ${1:-0})) error line(s)"
}

# A surface's rendered pixels: the frame taken before it opened against the
# frame taken while it is up. The changed pixels are the surface; enough of
# them must carry the colour it says it draws with. That is what separates a
# resolved colour from a transparent (unresolved) panel, which changes almost
# nothing on the output.
capture() { timeout 10 grim -o "$SCREEN" -t ppm "$WORK/$1" || fail "grim could not capture the headless output"; }
pixels() {   # pixels <before> <after> <want> <min-changed> <min-want> <what>
  python3 - "$WORK/$1" "$WORK/$2" "$3" "$4" "$5" <<'PY' || fail "$6: not on the output"
import sys
def read(path):
    head, dims, _, px = open(path, "rb").read().split(b"\n", 3)
    assert head == b"P6", head
    w, h = map(int, dims.split())
    return w, h, px
def rgb(s):
    s = s.lstrip("#")
    translucent = len(s) == 8   # QColor.toString puts alpha first when it is not 255
    if translucent:
        s = s[2:]
    return bytes(int(s[i:i+2], 16) for i in (0, 2, 4)), translucent
before, after, want, min_changed, min_want = sys.argv[1:6]
w, h, a = read(before)
w2, h2, b = read(after)
assert (w, h) == (w2, h2), "the output size changed mid-run"
want, translucent = rgb(want)
changed = hits = 0
for i in range(0, len(a), 3):
    if a[i:i+3] != b[i:i+3]:
        changed += 1
        if b[i:i+3] == want:
            hits += 1
if translucent:
    # A theme whose surface colour has alpha is composited over what is
    # behind it, so only the amount of ink is a fair question.
    print("   %d pixels changed; the theme's colour is translucent" % changed)
    sys.exit(0 if changed >= int(min_changed) else 1)
print("   %d pixels changed, %d of them the expected colour" % (changed, hits))
sys.exit(0 if changed >= int(min_changed) and hits >= int(min_want) else 1)
PY
}

echo
echo "-- the probe, its dock pinned to the headless output"
probe_start || { echo "   FAIL: the probe never started" >&2; exit 1; }
WORK="$PROBE_DIR/work"
mkdir -p "$WORK"
CFG=$(probe_cfg)
# probe.sh checked its *source* (the suite's synthetic file); from here on it
# must re-check the owner's own config, which is the one that must not move.
PROBE_OWNER_CFG="$OWNER_CFG"
PROBE_OWNER_MD5=$(owner_md5)
probe=$(step probe) || fail "the probe's own ipc surface did not answer"
expect_eq "the dock is not on the headless output" "$probe" "screen" "\"$SCREEN\""
note "dock screen $(jstr "$probe" screen), still hidden ($(jval "$probe" visible))"

palette=$(step palette) || fail "the palette step did not answer"
MENU_BG=$(jstr "$palette" menuBg)
note "shell menu background $MENU_BG, text $(jstr "$palette" menuText)"

revealed=$(step reveal) || fail "the reveal step did not answer"
expect_true "the dock did not become visible on the headless output" "$revealed" visible
probe=$(step probe) || fail "the probe's own ipc surface did not answer after reveal"
expect_at_least "the revealed dock reports no items to click" "$probe" items 1
note "revealed with $(jval "$probe" items) items, visible $(jval "$probe" visible)"

# The preconditions this suite owns, supplied only where the desk cannot give
# them: an app tile needs a running window (the compositor's, not the probe's)
# or a pin, and a probe HOME carries neither. Nothing is added when the desk
# already shows the real thing. The config baseline is taken *after* this: a pin
# chosen here can legitimately re-anchor a group in the copy, and the assertions
# below are about what the surfaces do, not about the fixture's preparation.
prepare=$(step prepare) || fail "the prepare step did not answer"
for _ in $(seq 20); do
  [ "$(jval "$prepare" hadApp)" = "true" ] && break
  sleep 0.25
  prepare=$(step prepare) || fail "the prepare step did not answer"
done
if [ "$(jval "$prepare" pinned)" = "true" ]; then
  note "no app tile on the headless dock: the fixture pinned $(jstr "$prepare" app)"
else
  note "the dock already shows an app tile; the fixture pinned nothing"
fi
[ "$(jval "$prepare" filled)" = "true" ] \
  && note "the fixture's probe group was empty: $(jstr "$prepare" app) was put in it"
[ "$(jval "$prepare" hadApp)" = "true" ] \
  || note "still no app tile after the wait ($(jstr "$prepare" why))"
CFG_MD5=$(md5sum "$CFG" | cut -d' ' -f1)

# ------------------------------------------------------------ context menu
echo
echo "-- an app's context menu"
MARK=$(errs_now)
step close >/dev/null
sleep 0.3
capture before-context.ppm
menu=$(step context-app) || fail "the app context menu step did not answer"
if [ "$(jval "$menu" ok)" != "true" ]; then
  fail "the app context menu did not open ($(jval "$menu" why))"
else
  expect_eq "the menu is not the one that was asked for" "$menu" appId "$(jval "$menu" id)"
  expect_true "the menu's panel colour is not the shell's menu background" "$menu" panelMatch
  expect_at_least "the menu laid out no rows" "$menu" rows 3
  expect_at_least "the menu has almost no text in it" "$menu" texts 5
  expect_empty "the menu drew text with a colour that is not the theme's" "$menu" foreign
  note "menu panel $(jstr "$menu" panel), rows $(jval "$menu" rows), texts $(jval "$menu" texts)"
fi
sleep 0.5
capture after-context.ppm
pixels before-context.ppm after-context.ppm "$MENU_BG" 8000 3000 "the app context menu"
log_since "$MARK" "the app context menu"
step close >/dev/null

# ------------------------------------------------------------ the other menu
echo
echo "-- a group tile's menu (Remove from Group), same menu surface"
MARK=$(errs_now)
groupmenu=$(step context-group) || fail "the group context menu step did not answer"
if [ "$(jval "$groupmenu" ok)" != "true" ]; then
  fail "the group context menu did not open ($(jval "$groupmenu" why))"
else
  expect_eq "the group menu is not the one that was asked for" "$groupmenu" appId '"__app_group_context__"'
  expect_eq "the group menu did not take the group that was clicked" "$groupmenu" groupData "$(jval "$groupmenu" id)"
  expect_true "the group menu's panel colour is not the shell's menu background" "$groupmenu" panelMatch
  expect_at_least "the group menu has almost no text in it" "$groupmenu" texts 5
  expect_empty "the group menu drew text with a colour that is not the theme's" "$groupmenu" foreign
  note "group menu on $(jval "$groupmenu" groupData), texts $(jval "$groupmenu" texts)"
fi
log_since "$MARK" "the group menu"
step close >/dev/null

# ------------------------------------------------- folder menu + rename field
echo
echo "-- a pinned folder's menu, its Rename field, Escape"
MARK=$(errs_now)
rename=$(step folder-rename) || fail "the rename step did not answer"
if [ "$(jval "$rename" ok)" != "true" ]; then
  fail "the folder menu never reached its name field ($(jval "$rename" why))"
else
  expect_true "the folder menu's panel colour is not the shell's menu background" "$rename" panelMatch
  expect_true "the name field never entered editing" "$rename" editing
  expect_true "the dock did not take the keyboard for the field" "$rename" holdsKeyboard
  expect_true "the name field's text colour is not the shell's menu text" "$rename" inputMatch
  expect_true "the name field's border is not the theme accent" "$rename" borderMatch
  expect_true "Escape did not end the edit" "$rename" cancelled
  expect_true "the keyboard stayed with a field that is gone" "$rename" releasedKeyboard
  expect_empty "the folder menu drew text with a colour that is not the theme's" "$rename" foreign
  note "field text $(jstr "$rename" input), border $(jstr "$rename" border), cancelled"
fi
log_since "$MARK" "the Rename field"
step close >/dev/null
[ "$(md5sum "$CFG" | cut -d' ' -f1)" = "$CFG_MD5" ] \
  || fail "a cancelled rename still wrote the config copy"

# ------------------------------------------------------------- group popup
echo
echo "-- an app group's popup (its tiles, its name row)"
MARK=$(errs_now)
capture before-group.ppm
popup=$(step group-popup) || fail "the group popup step did not answer"
GROUP_PANEL="$MENU_BG"
if [ "$(jval "$popup" ok)" != "true" ]; then
  fail "the group popup did not open ($(jval "$popup" why))"
else
  expect_eq "the popup on screen is not the group that was clicked" "$popup" active "$(jval "$popup" id)"
  expect_at_least "the group has no apps in its popup" "$popup" apps 1
  GROUP_PANEL=$(jstr "$popup" panel)
  [ -n "$GROUP_PANEL" ] || fail "the group popup step named no panel colour"
  note "group $(jval "$popup" active), apps $(jval "$popup" apps), panel $GROUP_PANEL (the dock's material)"
fi
sleep 0.5
capture after-group.ppm
pixels before-group.ppm after-group.ppm "$GROUP_PANEL" 8000 3000 "the group popup"
log_since "$MARK" "the group popup"
step close >/dev/null
sleep 0.4

# ---------------------------------------------------------- settings panel
echo
echo "-- the settings panel, its pages, its overlay"
MARK=$(errs_now)
capture before-settings.ppm
settings=$(step settings-open) || fail "the settings step did not answer"
expect_true "the settings panel did not open" "$settings" open
for page in appearance labels icons motion behavior placement folders groups presets about; do
  page_rep=$(step settings-page "$page") || fail "switching to $page did not answer"
  expect_eq "the panel did not switch to $page" "$page_rep" page "\"$page\""
done
note "open on $(jval "$settings" open), all 10 pages switched"
sleep 0.7
capture after-settings.ppm
pixels before-settings.ppm after-settings.ppm "$MENU_BG" 300000 60000 "the settings panel"
closed=$(step close) || fail "the close step did not answer"
expect_eq "the context menu stayed open" "$closed" context '""'
expect_eq "the group popup stayed open" "$closed" group '""'
expect_eq "the settings panel stayed open" "$closed" settings "false"
log_since "$MARK" "the settings panel"
[ "$(md5sum "$CFG" | cut -d' ' -f1)" = "$CFG_MD5" ] \
  || fail "opening and closing the surfaces wrote the config copy"

# ----------------------------------------------------------------- the log
echo
echo "-- the dock's log across every surface"
if grep -inE "$ERR_RE" "$PROBE_DIR/probe.log" | head -5 > "$WORK/log-errors.txt" && [ -s "$WORK/log-errors.txt" ]; then
  sed 's/^/   /' "$WORK/log-errors.txt" >&2
  fail "a runtime error in the dock's log while the surfaces were driven"
else
  note "no runtime error in the dock's log"
fi

# ------------------------------------------------------------- owner's side
echo
echo "-- the owner's side, as it was"
hyprctl output remove "$SCREEN" >/dev/null 2>&1
OUTPUTS=""
for _ in $(seq 10); do
  [ "$(monitor_state)" = "$OWNER_MONITORS" ] && break
  sleep 0.3
done
[ "$(monitor_state)" = "$OWNER_MONITORS" ] \
  || fail "the monitor list did not come back (now: $(monitor_state), was: $OWNER_MONITORS)"
[ "$(owner_md5)" = "$OWNER_MD5" ] || fail "the owner's omadock.json changed ($OWNER_MD5 -> $(owner_md5))"
note "owner's omadock.json unchanged (md5 $OWNER_MD5), monitors $OWNER_MONITORS"
for _ in $(seq 10); do
  [ "$(owner_dock_state)" = "$OWNER_DOCK" ] && break
  sleep 0.3
done
[ "$(owner_dock_state)" = "$OWNER_DOCK" ] \
  || fail "the owner's own dock changed state (now: $(owner_dock_state), was: $OWNER_DOCK)"
note "owner's own dock back to: $(owner_dock_state)"

echo
probe_cleanup || exit 1
if [ "$fail" = "0" ]; then
  echo "INTERACTIONS PASSED: menus, the rename field, the group popup and the settings panel render with the theme's colours"
else
  echo "INTERACTIONS FAILED" >&2
fi
exit $fail
