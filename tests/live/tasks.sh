#!/usr/bin/env bash
# Live: the developer task HUD works end to end through the IPC surface a CLI
# wrapper uses, and the dock stays clean while it does.
#
# What it proves, in order:
#   1. reportTask lands: taskStatus() reads the task back with the status, exit
#      code, title and duration the caller sent.
#   2. The tile that owns the task resolves it: the dock item's own `taskInfo`
#      and `badgeView` are read out of the running dock (tasks-shell.qml), so a
#      broken binding cannot pass on the IPC answer alone. Only the reported app
#      resolves a task; every other tile resolves null.
#   3. The badge the user sees is drawable: the glyph, the status colour, the
#      resolved QColor and the text it actually set are all read from the live
#      BadgeMark. A colour that never resolved is the silent failure class this
#      repo pins its QtQuick imports against, and it is invisible over IPC.
#   4. Each status maps to the documented look (running ●, success ✓, error !).
#   5. An empty app id is refused ("invalid"), and clearTask empties both the
#      state and the tile.
#   6. The dock's log gains no error line across all of it.
#
# `visible` is not asserted: it says the tile is on screen, not that the badge
# drew. The badge's OWN rule is asserted instead (`expr`, level > 0.01 with an
# anchor), and the chip section checks the pixels on the output.
#
# Non-intrusive: a second Quickshell instance on a byte-copy of the config under
# a redirected HOME (tests/live/probe.sh), its dock pinned to a headless output
# and made visible there - the item tree behind `read items` only exists for a
# mapped dock. Nothing appears on the owner's screen and the owner's own config
# is only read.

set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
# shellcheck source=tests/live/probe.sh
. ./probe.sh

PROBE_BODY="$PWD/tasks-shell.qml"
export PROBE_BODY

ROOT="$(cd ../.. && pwd)"
WRAPPER="$ROOT/scripts/omadock-task.sh"
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/omadock-tasks-XXXXXX") || exit 1
MAIN_SCREEN="omadock-tasks"
# A suite that exits mid-way must not leave an output behind, whichever section
# was running.
cleanup() {
  hyprctl output remove "$MAIN_SCREEN" >/dev/null 2>&1
  hyprctl output remove "omadock-chip" >/dev/null 2>&1
  rm -rf "$TMPD"
}
trap cleanup EXIT

fail=0
note() { echo "   $*"; }
red() { echo "   FAIL: $*" >&2; fail=1; }

# Error lines the dock logged: the class a broken binding or an unresolved
# colour produces. Counted before and after, so a pre-existing line cannot pass
# the check for us.
errlines() {
  grep -ciE "TypeError|ReferenceError|Unable to assign|is not a|Cannot read property" \
    "$(probe_log)" 2>/dev/null || true
}
monitor_list() {
  hyprctl -j monitors 2>/dev/null | python3 -c '
import json, sys
print(" ".join(m["name"] + ("*" if m["focused"] else "") for m in json.load(sys.stdin)))'
}
focused_monitor() { monitor_list | tr ' ' '\n' | grep '\*$' | tr -d '*'; }

# The dock's tiles and badges as they are right now, or "" if the call failed.
read_items() { qs -p "$PROBE_DIR" ipc call omadock-test read items "" 2>/dev/null; }
# A desk can have every running app inside a group and no pin, which leaves the
# probe with no app tile to file a task against. The fixture supplies one.
pin_fixture() { qs -p "$PROBE_DIR" ipc call omadock-test read pin "" 2>/dev/null; }

# A call that only settles after the dock has processed the change (its model
# updates on a debounce, and a shared-state change reaches the tiles through
# pullSharedState). Retry the whole predicate rather than sleeping a fixed time.
wait_for() {
  local i
  for i in $(seq 25); do
    "$@" && return 0
    sleep 0.2
  done
  return 1
}

# Predicates used with wait_for: they must run in THIS shell, because the
# probe helpers are shell functions and $PROBE_DIR is not exported.
answered() { [ -n "$(read_items)" ]; }
state_empty() { [ "$(probe_ipc taskStatus 2>/dev/null)" = "{}" ]; }
no_tile_task() {
  read_items | python3 -c '
import json,sys
busy = [i["appId"] for i in json.load(sys.stdin).get("items") or [] if i.get("hasTask")]
sys.exit(0 if not busy else 1)' 2>/dev/null
}

# The app tile to file tasks against: one that is present in two consecutive
# reads, so a tile that is still settling cannot pick itself and then vanish.
pick_target() {
  local a b
  a=$(read_items | python3 -c 'import json,sys;print(" ".join(i["appId"] for i in json.load(sys.stdin).get("items") or [] if i.get("appId")))' 2>/dev/null)
  sleep 0.4
  b=$(read_items | python3 -c 'import json,sys;print(" ".join(i["appId"] for i in json.load(sys.stdin).get("items") or [] if i.get("appId")))' 2>/dev/null)
  for id in $a; do
    case " $b " in *" $id "*) echo "$id"; return 0 ;; esac
  done
  return 1
}

# ------------------------------------------------ the wrapper's exit status
echo "-- omadock-task.sh: its exit status means what it says"
DEAD=/nonexistent-dir-xyz
if [ ! -f "$WRAPPER" ]; then
  red "no scripts/omadock-task.sh in the tree"
else
  # No dock reachable: every IPC subcommand must fail, loudly and non-zero.
  # Before the fix `status` printed quickshell's "Function not found." to stdout
  # and still exited 0, so a caller could not tell success from nothing at all.
  out=$(OMADOCK_SHELL_PATH=$DEAD sh "$WRAPPER" status 2>&1); rc=$?
  if [ "$rc" = 0 ]; then
    red "status answered exit 0 with no dock reachable (said: $out)"
  else
    case "$out" in
      *"not available"*) note "status with no dock: exit $rc, and it says why" ;;
      *) red "status failed without saying why (said: $out)" ;;
    esac
  fi
  OMADOCK_SHELL_PATH=$DEAD sh "$WRAPPER" report x running 0 t 0 >/dev/null 2>&1
  [ "$?" != 0 ] || red "report answered exit 0 with no dock reachable"
  # A wrapped command reports the COMMAND's status, and shouts when the report
  # could not be delivered - it must not turn a passing build into a failure,
  # nor hide that nothing was reported.
  OMADOCK_SHELL_PATH=$DEAD sh "$WRAPPER" /bin/true >/dev/null 2>"$TMPD/wrap-warn.txt"
  [ "$?" = 0 ] || red "wrapping a successful command answered non-zero"
  grep -q "not reported" "$TMPD/wrap-warn.txt" || red "a report that could not be delivered was silent"
  OMADOCK_SHELL_PATH=$DEAD sh "$WRAPPER" /bin/false >/dev/null 2>&1
  [ "$?" = 1 ] || red "wrapping a failing command did not report its exit code"
  # The callerless `hook` mode is gone rather than advertised.
  if sh "$WRAPPER" 2>&1 | grep -q "hook"; then
    red "the usage line still advertises the hook mode"
  else
    note "no hook mode advertised"
  fi
fi

echo
echo "-- task HUD: reportTask -> tile binding -> badge -> clearTask"
# The suite owns its premise: a headless output, a config copy that pins the dock
# to it with no autohide and no per-monitor filtering. `read items` walks the
# item tree, which only exists for a mapped dock, so the dock is made visible
# on an output with no glass, never on the owner's screen. None of this depends
# on the owner's config.
MAIN_SRC="$TMPD/main-cfg.json"
OWNER_MD5=$(md5sum "$HOME/.config/omarchy/omadock.json" | cut -d' ' -f1)
OWNER_MONITORS=$(monitor_list)
OWNER_FOCUSED=$(focused_monitor)
if hyprctl monitors 2>/dev/null | grep -qE "^(Monitor|  )?${MAIN_SCREEN}\b"; then
  echo "   REFUSING: an output named $MAIN_SCREEN already exists" >&2
  exit 1
fi
python3 - "$HOME/.config/omarchy/omadock.json" "$MAIN_SRC" "$MAIN_SCREEN" <<'PY' || exit 1
import json, sys
conf = json.load(open(sys.argv[1]))
conf["screen"] = sys.argv[3]
conf["multiMonitor"] = False
conf["perMonitorApps"] = False
conf["autohide"] = False
conf["intelligentAutohide"] = False
json.dump(conf, open(sys.argv[2], "w"), indent=2)
PY
hyprctl output create headless "$MAIN_SCREEN" >/dev/null 2>&1 \
  || { echo "   FAIL: this compositor would not create a headless output" >&2; exit 1; }
sleep 1
if [ "$(focused_monitor)" != "$OWNER_FOCUSED" ]; then
  echo "   FAIL: the headless output took the owner's focus" >&2
  [ -n "$OWNER_FOCUSED" ] && hyprctl dispatch "hl.dsp.focus({ monitor = \"$OWNER_FOCUSED\" })" >/dev/null 2>&1
  fail=1
fi
# probe.sh copies PROBE_OWNER_CFG; point it at the suite's own copy for the
# start, then back at the real owner's config for its exit re-check.
PROBE_OWNER_CFG="$MAIN_SRC"
if ! probe_start; then
  echo "   FAIL: the probe never started" >&2
  probe_cleanup >/dev/null 2>&1
  exit 1
fi
PROBE_OWNER_CFG="$HOME/.config/omarchy/omadock.json"
PROBE_OWNER_MD5="$OWNER_MD5"
probe_ipc reveal >/dev/null 2>&1
if qs -p "$PROBE_DIR" ipc call omadock-test read screen "" 2>/dev/null \
     | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("screen") == sys.argv[1] else 1)' "$MAIN_SCREEN"; then
  note "the probe's dock is visible on $MAIN_SCREEN"
else
  red "the probe's dock is not on $MAIN_SCREEN"
fi

target=$(pick_target)
if [ -z "$target" ]; then
  pin_fixture >/dev/null
  for _ in $(seq 10); do
    target=$(pick_target)
    [ -n "$target" ] && break
    sleep 0.2
  done
fi
if [ -z "$target" ]; then
  red "the dock exposed no stable app tile to report a task against"
  probe_cleanup >/dev/null 2>&1
  exit 1
fi
note "reporting tasks against the real tile \"$target\""
before=$(errlines)

# The feature is inert by default: no tile resolves a task before one is sent.
wait_for answered || red "the fixture never answered"
read_items | python3 -c '
import json,sys
d = json.load(sys.stdin)
busy = [i["appId"] for i in d.get("items") or [] if i.get("hasTask")]
if busy: raise SystemExit("tiles already carry a task: %s" % ", ".join(busy))
if not (d.get("badges") or []): raise SystemExit("the fixture found no badge at all")
' 2>&1 | sed 's/^/   /' >&2
[ "${PIPESTATUS[0]}" = "0" ] || fail=1

# One status -> its documented glyph and colour, read back from the IPC state,
# the tile's binding and the drawn badge.
expect_task() {
  local st=$1 code=$2 title=$3 dur=$4 glyph=$5 colour=$6 rep tid ok
  rep=$(probe_ipc reportTask "$target" "$st" "$code" "$title" "$dur" 2>/dev/null)
  [ "$rep" = "ok" ] || { red "reportTask $st answered \"$rep\""; return 0; }

  tid=$(probe_ipc taskStatus 2>/dev/null | python3 -c '
import json,sys
want = sys.argv[1]
hit = [v for k, v in json.load(sys.stdin).items() if v.get("appId") == want]
if not hit: raise SystemExit("no task stored for %s" % want)
t = hit[0]
print("%s|%s|%s|%s" % (t["status"], t["exitCode"], t["title"], t["duration"]))
' "$target" 2>/dev/null)
  case "$tid" in
    "") red "taskStatus() held no task for $target" ;;
    "$st|$code|$title|$dur") note "taskStatus: $st, exit $code, \"$title\", ${dur}s" ;;
    *) red "taskStatus() read back \"$tid\", wanted \"$st|$code|$title|$dur\"" ;;
  esac

  ok=1
  for _ in $(seq 25); do
    read_items | python3 -c '
import json,sys
d = json.load(sys.stdin)
want, st, glyph, colour = sys.argv[1:5]
items = d.get("items") or []
mine = [i for i in items if i.get("appId") == want]
if not mine: raise SystemExit("the tile for %s vanished" % want)
it = mine[0]
if not it.get("hasTask"): raise SystemExit("tile %s resolved no task" % want)
if it.get("taskStatus") != st: raise SystemExit("tile resolved status %r, wanted %r" % (it.get("taskStatus"), st))
if it.get("badgeMode") != "status": raise SystemExit("tile badge mode %r, wanted status" % it.get("badgeMode"))
if it.get("badgeGlyph") != glyph: raise SystemExit("tile badge glyph %r, wanted %r" % (it.get("badgeGlyph"), glyph))
if it.get("badgeColor") != colour: raise SystemExit("tile badge colour %r, wanted %r" % (it.get("badgeColor"), colour))
others = [i["appId"] for i in items if i.get("appId") != want and i.get("hasTask")]
if others: raise SystemExit("another tile resolved the task: %s" % ", ".join(others))
# The drawn mark: the badge that took this glyph, its resolved colour, the text
# it set, and its own visibility rule (visible itself cascades from the hidden
# probe dock - see the header).
drawn = [b for b in (d.get("badges") or []) if b.get("shownGlyph") == glyph]
if not drawn: raise SystemExit("no BadgeMark took glyph %r" % glyph)
b = drawn[0]
if b.get("ink") != glyph: raise SystemExit("the badge drew %r, wanted %r" % (b.get("ink"), glyph))
if b.get("badgeColor") != colour: raise SystemExit("the badge took colour %r, wanted %r" % (b.get("badgeColor"), colour))
r = str(b.get("resolved") or "")
if not r.startswith("#") or r == "#00000000":
    raise SystemExit("the badge colour never resolved (%r)" % b.get("resolved"))
if b.get("expr") != "true": raise SystemExit("the badge is not drawable (level %r, anchor %r)" % (b.get("level"), b.get("hasAnchor")))
if float(b.get("level") or 0) <= 0.01: raise SystemExit("the badge level never rose (%r)" % b.get("level"))
' "$target" "$st" "$glyph" "$colour" 2>"/tmp/omadock-task-check.$$" && ok=0 && break
    sleep 0.2
  done
  if [ "$ok" != "0" ]; then
    red "the $st task did not reach the tile and its badge:"
    sed 's/^/     /' "/tmp/omadock-task-check.$$" >&2
  else
    note "the tile bound the task and a BadgeMark drew \"$glyph\" in $colour"
  fi
  rm -f "/tmp/omadock-task-check.$$"
}

expect_task running 0 "Sleep 40" 0 "●" "#89b4fa"
expect_task success 0 "cargo build --release" 14 "✓" "#a6e3a1"
expect_task error 2 "cargo test" 11 "!" "#f38ba8"

# An empty app id is not a task.
rep=$(probe_ipc reportTask "" done 0 "orphan" 0 2>/dev/null)
[ "$rep" = "invalid" ] || red "reportTask with an empty app id answered \"$rep\", wanted invalid"
note "an empty app id is refused (invalid)"

# clearTask empties the state and the tile together.
probe_ipc clearTask "$target" >/dev/null 2>&1
if wait_for state_empty; then
  note "clearTask emptied the task state"
else
  red "clearTask left the task in the state: $(probe_ipc taskStatus 2>/dev/null)"
fi
if wait_for no_tile_task; then
  note "clearTask emptied the tile"
else
  red "clearTask left the task on a tile"
fi

# Focusing (or clicking) the app clears its task - the release note promises
# "the badge clears as soon as you focus the app". That clear lives in
# Dock.qml's root.clearUrgentApp, which the focus handler (onActiveIdChanged)
# calls with the newly active app id; this drives the same function with the
# same shape of arguments. The Hyprland focus event that feeds activeId is the
# dock's pre-existing machinery and is not what this step proves.
probe_ipc reportTask "$target" running 0 "FOCUSCLEAR sleep 99" 0 >/dev/null 2>&1
wait_for answered || red "the fixture stopped answering before the focus clear"
out=$(qs -p "$PROBE_DIR" ipc call omadock-test read focus-clear "$target" 2>/dev/null)
if printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("ok") else 1)'; then
  if wait_for state_empty && wait_for no_tile_task; then
    note "the app being focused cleared its task (clearUrgentApp)"
  else
    red "the task survived the app being focused: $(probe_ipc taskStatus 2>/dev/null)"
  fi
else
  red "the focus-clear path could not be driven ($out)"
fi

# The existing IPC surface still answers after all of it.
probe_ipc state 2>/dev/null | grep -q '"docks"' || red "state no longer answers after the task calls"

# ------------------------------- the wrapper, end to end, against a real dock
# The probe dock runs this tree's DockHost.qml, so it HAS reportTask - which is
# the only way to exercise the wrapper past its syntax and usage paths.
echo
echo "-- omadock-task.sh against a dock that really has reportTask"
if [ -f "$WRAPPER" ]; then
  out=$(OMADOCK_SHELL_PATH="$PROBE_DIR" sh "$WRAPPER" report "$target" running 0 "WRAPPER end to end" 0 2>&1); rc=$?
  if [ "$rc" = 0 ] && [ "$out" = "ok" ]; then
    note "report -> ok"
  else
    red "report against a live dock answered exit $rc: $out"
  fi
  if OMADOCK_SHELL_PATH="$PROBE_DIR" sh "$WRAPPER" status 2>/dev/null | python3 -c '
import json,sys
want = sys.argv[1]
d = json.load(sys.stdin)
hit = [v for v in d.values() if v.get("appId") == want]
if not hit: raise SystemExit("status did not read the reported task back (have %s)" % list(d))
if hit[0]["title"] != "WRAPPER end to end": raise SystemExit("read back %r" % hit[0]["title"])
' "$target"; then
    note "status read the wrapper's report back"
  else
    red "status did not reflect the wrapper's own report"
  fi
  # The wrapped-command form: the command's status is reported, and its own exit
  # code is what the wrapper exits with.
  OMADOCK_APP="$target" OMADOCK_SHELL_PATH="$PROBE_DIR" sh "$WRAPPER" /bin/true >/dev/null 2>&1
  [ "$?" = 0 ] || red "wrapping /bin/true answered non-zero"
  OMADOCK_APP="$target" OMADOCK_SHELL_PATH="$PROBE_DIR" sh "$WRAPPER" /bin/false >/dev/null 2>&1
  [ "$?" = 1 ] || red "wrapping /bin/false did not exit 1"
  if OMADOCK_SHELL_PATH="$PROBE_DIR" sh "$WRAPPER" status 2>/dev/null | python3 -c '
import json,sys
want = sys.argv[1]
d = json.load(sys.stdin)
hit = [v for v in d.values() if v.get("appId") == want]
if not hit: raise SystemExit("the wrapped command reported nothing for %s" % want)
t = hit[0]
if t["status"] != "error" or t["exitCode"] != 1:
    raise SystemExit("wrapped status %s/exit %s, wanted error/1" % (t["status"], t["exitCode"]))
' "$target"; then
    note "wrapping /bin/false reported error/exit 1 and exited 1"
  else
    red "the wrapped command's outcome did not reach the dock"
  fi
  OMADOCK_SHELL_PATH="$PROBE_DIR" sh "$WRAPPER" clear "$target" >/dev/null 2>&1 \
    || red "clear against a live dock answered non-zero"
fi

after=$(errlines)
if [ "$after" -le "$before" ]; then
  note "the dock's log gained no error line ($before -> $after)"
else
  red "the dock's log gained $((after - before)) error line(s):"
  grep -iE "TypeError|ReferenceError|Unable to assign|is not a|Cannot read property" "$(probe_log)" | tail -5 | sed 's/^/     /' >&2
fi

probe_cleanup || fail=1
hyprctl output remove "$MAIN_SCREEN" >/dev/null 2>&1
for _ in $(seq 10); do
  [ "$(monitor_list)" = "$OWNER_MONITORS" ] && break
  sleep 0.3
done
[ "$(monitor_list)" = "$OWNER_MONITORS" ] \
  || red "the monitor list did not come back (now: $(monitor_list), was: $OWNER_MONITORS)"
[ "$(md5sum "$HOME/.config/omarchy/omadock.json" | cut -d' ' -f1)" = "$OWNER_MD5" ] \
  || red "the owner's omadock.json changed"
note "owner's monitors and config unchanged, no headless output left"

# -------------------------------------------------- the hover chip, for real
# The chip sits behind the tooltip's LazyLoader; a real hover cannot be produced
# on this host without warping the pointer onto another monitor, which with
# `input:follow_mouse` set to full would take the owner's focus mid-typing. So
# the dock is run on a headless output and made visible there, and the tooltip's
# own life flag is raised so the LazyLoader builds the surface the chip lives
# in. What is then read back is the real component with its real bindings and
# theme colours. The hover -> dwell -> tipShown chain is the dock's pre-existing
# tooltip machinery and is deliberately not what this verifies.

chip_section() {
  local screen=omadock-chip owner_md5="" owner_monitors="" owner_focused="" src out rc
  command -v grim >/dev/null 2>&1 || { red "cannot check the chip's pixels: grim is not installed"; return; }
  if hyprctl monitors 2>/dev/null | grep -qE "^(Monitor|  )?${screen}\b"; then
    red "an output named $screen already exists"; return
  fi
  owner_md5=$(md5sum "$HOME/.config/omarchy/omadock.json" | cut -d' ' -f1)
  owner_monitors=$(monitor_list)
  owner_focused=$(focused_monitor)
  src="$TMPD/chip-cfg.json"
  python3 - "$HOME/.config/omarchy/omadock.json" "$src" "$screen" <<'PY' || { red "could not build the chip probe's config"; return; }
import json, sys
conf = json.load(open(sys.argv[1]))
conf["screen"] = sys.argv[3]
conf["multiMonitor"] = False
# Same premise as the HUD section: a visible dock on an empty output, with no
# per-monitor filtering and no autohide to race the tile read.
conf["perMonitorApps"] = False
conf["autohide"] = False
conf["intelligentAutohide"] = False
json.dump(conf, open(sys.argv[2], "w"), indent=2)
PY
  hyprctl output create headless "$screen" >/dev/null 2>&1 \
    || { red "this compositor would not create a headless output"; return; }
  sleep 1
  if [ "$(focused_monitor)" != "$owner_focused" ]; then
    red "the headless output took the owner's focus"
    [ -n "$owner_focused" ] && hyprctl dispatch "hl.dsp.focus({ monitor = \"$owner_focused\" })" >/dev/null 2>&1
  fi
  # The probe copies this file and never writes it; from here on the owner's
  # own config is the one probe_cleanup must re-check.
  PROBE_OWNER_CFG="$src"
  PROBE_SCREEN="$screen"
  if ! probe_start; then
    red "the chip probe never started"
    probe_cleanup >/dev/null 2>&1
    hyprctl output remove "$screen" >/dev/null 2>&1
    return
  fi
  PROBE_OWNER_CFG="$HOME/.config/omarchy/omadock.json"
  PROBE_OWNER_MD5="$owner_md5"

  pt() { qs -p "$PROBE_DIR" ipc call omadock-test read "$1" "${2:-}" 2>/dev/null; }

  out=$(pt screen)
  if printf '%s' "$out" | python3 -c '
import json,sys
d = json.load(sys.stdin)
if not d.get("ok"): raise SystemExit(d.get("why") or "no answer")
if d.get("screen") != sys.argv[1]: raise SystemExit("the dock is on %r, not %s" % (d.get("screen"), sys.argv[1]))
' "$screen"; then
    note "the chip probe's dock is pinned to the headless output"
  else
    red "the chip probe's dock is not on the headless output"
  fi
  pt reveal >/dev/null
  # The model builds from the app library a moment after the dock maps; retry
  # the tile read rather than measuring the first empty turn.
  target=""
  for _ in $(seq 20); do
    target=$(pick_target)
    [ -n "$target" ] && break
    sleep 0.3
  done
  if [ -z "$target" ]; then
    pin_fixture >/dev/null
    for _ in $(seq 10); do
      target=$(pick_target)
      [ -n "$target" ] && break
      sleep 0.2
    done
  fi
  [ -n "$target" ] && note "chip target tile \"$target\"" || red "no tile to raise the chip over"
  sleep 0.6
  timeout 10 grim -o "$screen" -t ppm "$TMPD/chip-off.ppm" 2>/dev/null \
    || red "grim could not capture the headless output"

  chipbefore=$(errlines)
  CHIP_TITLE="AUDITCHIP cargo test"
  probe_ipc reportTask "$target" error 3 "$CHIP_TITLE" 7 >/dev/null 2>&1
  out=$(pt chip-open "$target")
  if printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("ok") else 1)'; then
    note "the tooltip's own life flag was raised on \"$target\""
  else
    red "the tile's tooltip would not come alive ($out)"
  fi
  sleep 0.8
  timeout 10 grim -o "$screen" -t ppm "$TMPD/chip-on.ppm" 2>/dev/null \
    || red "grim could not capture the headless output"

  # What the instantiated chip drew, against literal expectations - the text and
  # the mark colour are the two things the collapse to one source touched. The
  # text is bound to DockTasks.chipLabel and the mark's colour to
  # DockTasks.statusColor, the same pair the tile's badge reads, so a chip that
  # disagrees with the badge cannot pass here or in the `items` step above.
  chipok=1
  for _ in $(seq 15); do
    out=$(pt chip-read "AUDITCHIP")
    printf '%s' "$out" | python3 -c '
import json,sys
d = json.load(sys.stdin)
want_text = "AUDITCHIP cargo test (7s) [Exit 3]"
want_dot = "#f38ba8"
if int(d.get("surfaces") or 0) < 1:
    raise SystemExit("no tile built a tooltip surface to read the chip out of")
hits = d.get("hits") or []
if not hits: raise SystemExit("the chip drew no text with the task title in it")
if hits[0]["text"] != want_text:
    raise SystemExit("the chip drew %r, wanted %r" % (hits[0]["text"], want_text))
c = str(hits[0].get("color") or "")
if not c.startswith("#") or c in ("#000000", "#000000ff", "#00000000", "#ff000000"):
    raise SystemExit("the chip text colour never resolved (%r)" % c)
if float(hits[0].get("iw") or 0) <= 0: raise SystemExit("the chip text has no width")
if not any(str(m.get("color")) == want_dot for m in (d.get("marks") or [])):
    raise SystemExit("no mark beside the chip drew the status colour %s (marks: %s)"
                     % (want_dot, [m.get("color") for m in (d.get("marks") or [])][:8]))
' 2>"$TMPD/chip-read.txt" && { chipok=0; break; }
    sleep 0.2
  done
  if [ "$chipok" = "0" ]; then
    note "the chip drew \"$CHIP_TITLE (7s) [Exit 3]\" over a #f38ba8 mark"
  else
    red "the hover chip did not resolve as it must:"
    sed 's/^/     /' "$TMPD/chip-read.txt" >&2
  fi
  # The chip probe's log must be clean too: the chip is a tooltip surface of its
  # own, so a broken colour or a bad property read lands there, not in the
  # hidden probe's log the earlier check read.
  chipafter=$(errlines)
  if [ "$chipafter" -le "$chipbefore" ]; then
    note "the chip probe's dock logged no error line ($chipbefore -> $chipafter)"
  else
    red "the chip probe's dock logged $((chipafter - chipbefore)) error line(s):"
    grep -iE "TypeError|ReferenceError|Unable to assign|is not a|Cannot read property" "$(probe_log)" | tail -5 | sed 's/^/     /' >&2
  fi

  # ...and it reached the output, not just the properties.
  if [ -f "$TMPD/chip-off.ppm" ] && [ -f "$TMPD/chip-on.ppm" ]; then
    if out=$(python3 - "$TMPD/chip-off.ppm" "$TMPD/chip-on.ppm" <<'PY'
import sys
def read(p):
    head, dims, _, px = open(p, "rb").read().split(b"\n", 3)
    w, h = map(int, dims.split())
    return w, h, px
a, b = sys.argv[1], sys.argv[2]
_, _, pa = read(a)
_, _, pb = read(b)
print(sum(1 for i in range(0, len(pa), 3) if pa[i:i+3] != pb[i:i+3]))
PY
    ); then
      if [ "${out:-0}" -gt 100 ]; then
        note "$out pixels changed on the output when the chip came up"
      else
        red "the chip did not draw on the output ($out pixels changed)"
      fi
    else
      red "the two frames could not be compared"
    fi
  fi

  pt chip-close >/dev/null
  probe_cleanup || fail=1
  hyprctl output remove "$screen" >/dev/null 2>&1
  for _ in $(seq 10); do
    [ "$(monitor_list)" = "$owner_monitors" ] && break
    sleep 0.3
  done
  [ "$(monitor_list)" = "$owner_monitors" ] \
    || red "the monitor list did not come back (now: $(monitor_list), was: $owner_monitors)"
  [ "$(md5sum "$HOME/.config/omarchy/omadock.json" | cut -d' ' -f1)" = "$owner_md5" ] \
    || red "the owner's omadock.json changed"
  note "owner's monitors and config unchanged, no headless output left"
}

chip_section

if [ "$fail" = "0" ]; then
  echo "TASKS PASSED: the task HUD lands, binds on the tile, draws and clears"
else
  echo "TASKS FAILED" >&2
fi
exit $fail
