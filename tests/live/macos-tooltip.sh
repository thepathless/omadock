#!/usr/bin/env bash
# Live (NON-INTRUSIVE): the macOS look's hover callout, over a magnified icon.
#
# The macOS preset's name chip is the Dock's callout, not this dock's chip
# (DockLabels.LABEL_CHIPS). The values below are the design, recorded once so
# they are not re-derived:
#
#   - a dark translucent chip: #2b2b2b at 82%, no border, 5 px corners,
#     8 x 3 px of padding (HoverNamePlate variant "macos");
#   - its ink a fixed near-white #f5f5f5, so it reads over any wallpaper;
#   - the system sans at 13 px (Style.font.subtitle), regular weight
#     (DockLabelLogic, the macOS branch);
#   - a 6 px gap above the *drawn* icon top, so the chip clears the enlarged
#     artwork instead of sitting at resting-row height (DockLabel.macGap,
#     from DockLabel.artRise so every tile kind uses one rule);
#   - it waits the dock's tooltip delay (450 ms by default, user-settable)
#     instead of the dock chip's 150 ms name dwell (DockLabel.baseDelay);
#   - no pointer arrow: the chip is a plain surface.
#
# Every one of those is measured on a real dock over a live magnified icon -
# and the screenshot is the proof: the chip must be on the output, above the
# enlarged icon, centred on it, and legible against what it covers. A second
# capture with the pointer off the row shows the resting tile is unchanged.
# The same is done for an app tile, an app-group tile and a pinned folder: a
# group's or a folder's artwork is not the same box as an app's, so "6 px
# above the drawn icon" must hold for each, from one rule rather than a
# per-widget special case. A second preset then proves the callout is a
# property of the macOS look, not a restyle of every tooltip.
#
# Runs on a headless output (`hyprctl output create headless`) against the
# probe's own HOME; the owner's config is only read, the pointer is put back
# where it was, and probe_cleanup re-checks the owner's file md5, shell PID
# and monitor list, and fails on any survivor. Fails closed without grim,
# hyprctl or a headless output.

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

OWNER_CFG="${HOME}/.config/omarchy/omadock.json"
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
# The headless output's geometry, as the globals a pointer warp uses: the
# monitor the probe is on is the one that was not there before.
MON_FILE=$(mktemp "${TMPDIR:-/tmp}/omadock-macos-monitors-XXXXXX") || exit 1
screen_geometry() {
  hyprctl -j monitors > "$MON_FILE" 2>/dev/null || return 1
  python3 - "$MON_FILE" "$HEADLESS_OWNER_MONITORS" <<'PY'
import json, sys
owner = set(sys.argv[2].replace("*", "").split())
m = next((m for m in json.load(open(sys.argv[1])) if m["name"] not in owner), None)
if m is None:
    sys.exit(1)
print(m["name"], m["x"], m["y"], m["width"], m["height"], m["scale"])
PY
}

command -v grim >/dev/null || { echo "   cannot verify pixels: grim is not installed" >&2; exit 1; }
command -v hyprctl >/dev/null || { echo "   cannot run: no hyprctl on PATH" >&2; exit 1; }
OWNER_MD5=$(owner_md5)
OWNER_MONITORS=$(monitor_state)
CURSOR=$(hyprctl -j cursorpos | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["x"], d["y"])')

# shellcheck source=tests/live/headless.sh
. tests/live/headless.sh
warp() { hyprctl dispatch "hl.dsp.cursor.move({ x = $1, y = $2 })" >/dev/null 2>&1; }
cleanup() {
  if declare -F probe_cleanup >/dev/null; then probe_cleanup >/dev/null 2>&1; fi
  headless_stop >/dev/null 2>&1
  # The pointer goes back where the owner left it, whatever happened above.
  if [ -n "${CURSOR:-}" ]; then
    read -r ox oy <<<"$CURSOR"
    warp "$ox" "$oy"
  fi
  [ -n "${MON_FILE:-}" ] && rm -f "$MON_FILE"
}
trap cleanup EXIT

echo "-- pre-flight: a headless output, the owner's config and cursor recorded"
headless_start "$OWNER_CFG" || { echo "   FAIL: no headless output" >&2; exit 1; }
PROBE_BODY="$PWD/tests/live/macos-tooltip-shell.qml"
export PROBE_BODY
# shellcheck source=tests/live/probe.sh
. tests/live/probe.sh

probe_start || { echo "   FAIL: the probe never started" >&2; exit 1; }
# probe.sh checked its *source* (the suite's synthetic copy); from here on it
# must re-check the owner's own file, which is the one that must not move.
PROBE_OWNER_CFG="$OWNER_CFG"
PROBE_OWNER_MD5=$(owner_md5)
WORK="$PROBE_DIR/work"
mkdir -p "$WORK"
body() { qs -p "$PROBE_DIR" ipc call omadock-test "$@"; }
state() { body read "${1:-app}" 2>/dev/null; }

geo=$(screen_geometry) || { fail "the headless output vanished"; exit 1; }
read -r SCREEN MX MY MW MH MS <<<"$geo"
note "screen $SCREEN at $MX,$MY ${MW}x${MH}, scale $MS"
[ "$MS" = "1" ] || fail "the probe output is scaled ($MS); the pixel reads assume 1"

# The look is applied by name, the way the settings panel does it.
probe_ipc applyPreset macOS >/dev/null 2>&1 || fail "applyPreset macOS did not answer"
for _ in $(seq 20); do
  REST=$(state app)
  [ "$(printf '%s' "$REST" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("preset",""))' 2>/dev/null)" = "builtin_macos" ] && break
  sleep 0.25
done
[ -n "${REST:-}" ] || fail "the macOS preset never reached the dock"

# A probe HOME has no pinned apps, so the fixture pins one through the dock's
# own togglePin - a real DockItem, built by the delegate like any other.
prepare=$(body prepare) || fail "the prepare step did not answer"
PINNED_NOW=$(printf '%s' "$prepare" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("pinned", False))')
PROBE_APP=$(printf '%s' "$prepare" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("app", ""))')
for _ in $(seq 20); do
  [ "$(printf '%s' "$prepare" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("had",False))' 2>/dev/null)" = "True" ] && break
  sleep 0.25
  prepare=$(body prepare)
done
if [ "$PINNED_NOW" = "True" ]; then
  note "fixture: pinned $PROBE_APP (a real DockItem, chosen from the dock's own list)"
else
  note "fixture: an app tile was already on the row ($PROBE_APP)"
fi
probe_ipc reveal >/dev/null 2>&1 || fail "reveal did not answer"
sleep 1.5

# The tiles this desk actually has. A desk with no group has no group tile to
# hover, so that kind is skipped with a note; the app tile is required (the
# fixture supplies it).
KINDS=$(body kinds)
present() { printf '%s' "$KINDS" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1],False))' "$1"; }
[ "$(present app)" = "True" ] || fail "no app tile on the probe dock after the fixture pinned one"
note "tiles: app=$(present app), group=$(present group), folder=$(present folder)"

# ---------------------------------------------------------------- one tile
# Hover one tile kind, measure the callout's geometry, design and pixels, then
# put the pointer back and check the resting tile is what it was.
measure() {
  local kind=$1 rest hover rest2 tile point hx hy gx gy win_h art
  rest=$(state "$kind")
  echo "$rest" > "$WORK/$kind-rest.json"
  python3 - "$WORK/$kind-rest.json" "$kind" <<'PY' || { fail "$kind: no tile to measure"; return; }
import json, sys
d = json.load(open(sys.argv[1]))
t = d.get("tile")
if not t or not t.get("icon"):
    sys.exit(1)
i = t["icon"]
print("   %s: %r, resting art %.0f..%.0f at x %.0f..%.0f, scale %.3f" % (
    sys.argv[2], t.get("name", t.get("id", "")), i["y"], i["y"] + i["h"], i["x"], i["x"] + i["w"], t["scale"]))
PY
  timeout 10 grim -o "$SCREEN" -t ppm "$WORK/$kind-rest.ppm" || fail "$kind: grim could not capture the resting dock"

  point=$(python3 - "$WORK/$kind-rest.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
t = d["tile"]
i = t["icon"]
print(round(i["x"] + i["w"] / 2), round(i["y"] + i["h"] / 2), d["window"]["h"])
PY
)
  read -r hx hy win_h <<<"$point"
  gx=$((MX + hx))
  gy=$((MY + MH - win_h + hy))
  note "   pointer -> $gx,$gy (the icon's centre $hx,$hy in the dock window)"
  warp "$gx" "$gy"
  # A warp can land while the card's input region is still settling (the dock
  # rebuilds its mask on the card's geometry). The pointer is already inside,
  # so no new motion would come: nudge it once and wait again. The check is
  # the dock's own hover state, not a sleep.
  for i in $(seq 12); do
    hover=$(state "$kind")
    [ "$(printf '%s' "$hover" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("hover",{}).get("card"))' 2>/dev/null)" = "True" ] && break
    [ "$i" = "6" ] && warp "$((gx + 3))" "$((gy + 3))"
    sleep 0.35
  done
  sleep 2.2
  hover=$(state "$kind")
  echo "$hover" > "$WORK/$kind-hover.json"
  timeout 10 grim -o "$SCREEN" -t ppm "$WORK/$kind-hover.ppm" || fail "$kind: grim could not capture the hovered dock"
  timeout 10 grim -o "$SCREEN" "$WORK/$kind-hover.png" 2>/dev/null || true
  # MACOS_TOOLTIP_SHOTS names a directory to keep the proof frames in (the
  # probe's scratch directory is removed at the end, so by default they are
  # only read). Never required for the checks.
  if [ -n "${MACOS_TOOLTIP_SHOTS:-}" ]; then
    mkdir -p "$MACOS_TOOLTIP_SHOTS"
    cp "$WORK/$kind-hover.png" "$MACOS_TOOLTIP_SHOTS/$kind-hover.png" 2>/dev/null || true
  fi

  python3 - "$WORK/$kind-rest.json" "$WORK/$kind-hover.json" "$WORK/$kind-rest.ppm" "$WORK/$kind-hover.ppm" "$MX" "$MY" "$MW" "$MH" "$kind" <<'PY' || fail "$kind: the macOS callout"
import json, sys
rest = json.load(open(sys.argv[1]))
hover = json.load(open(sys.argv[2]))
mx, my, mw, mh = map(int, sys.argv[5:9])
kind = sys.argv[9]
ok = True

def bad(msg):
    global ok
    print("   FAIL: " + msg, file=sys.stderr)
    ok = False

t = hover.get("tile") or {}
c = t.get("chip") or {}
rt = rest.get("tile") or {}
label = t.get("label") or {}

if hover.get("chipKey") != "macos":
    bad("the dock is not on the macOS chip (%r)" % hover.get("chipKey"))
if not t:
    bad("no %s tile on the dock" % kind)
if not c:
    bad("the callout never opened over the %s tile" % kind)
if t.get("scale", 1) <= 1.2:
    bad("the %s icon did not magnify (scale %.3f)" % (kind, t.get("scale", 1)))
if label.get("chip") != "macos":
    bad("the %s label did not take the macOS chip (%r)" % (kind, label.get("chip")))

if c and t:
    icon = t["icon"]
    chip = c["screen"]
    chip_bottom = chip["y"] + chip["h"]
    gap = icon["y"] - chip_bottom
    dx = (chip["x"] + chip["w"] / 2) - (icon["x"] + icon["w"] / 2)
    resting_top = rt["icon"]["y"]
    print("   %s: hovered scale %.3f, drawn art %.0f..%.0f, chip %.0f..%.0f" % (
        kind, t["scale"], icon["y"], icon["y"] + icon["h"], chip["y"], chip_bottom))
    print("   %s: gap above the drawn icon %.1f px (wanted 6), centre dx %.1f px (wanted 0)" % (
        kind, gap, dx))
    if not (4.5 <= gap <= 8.5):
        bad("%s: the chip is %.1f px above the drawn icon's top, not ~6" % (kind, gap))
    if abs(dx) > 1.5:
        bad("%s: the chip is %.1f px off the icon's centre" % (kind, dx))
    if chip_bottom >= resting_top:
        bad("%s: the chip sits at resting-row height (bottom %.0f, resting art top %.0f)" % (
            kind, chip_bottom, resting_top))
    rise = icon["h"] - (icon["h"] / t["scale"])
    if rise < 5:
        bad("%s: the artwork did not rise out of the row (%.1f px)" % (kind, rise))

d = c.get("design") or {}
if c:
    print("   %s: chip variant %s, fill %s, ink %s, radius %.0f, %.0fx%.0f, font %.0fpx weight %s" % (
        kind, d.get("variant"), d.get("fill"), d.get("ink"), d.get("radius", -1),
        d.get("width", -1), d.get("height", -1), d.get("fontPx", -1), d.get("weight")))
    if d.get("variant") != "macos":
        bad("%s: the chip is not the macOS callout" % kind)
    if d.get("ink", "").lower() != "#f5f5f5":
        bad("%s: the callout ink is %r, not the fixed #f5f5f5" % (kind, d.get("ink")))
    fill = d.get("fill", "").lower().lstrip("#")
    alpha, rgb = (fill[:2], fill[2:]) if len(fill) == 8 else ("ff", fill)
    if rgb != "2b2b2b":
        bad("%s: the callout fill is #%s, not #2b2b2b" % (kind, rgb))
    try:
        a = int(alpha, 16) / 255.0
    except ValueError:
        a = -1
    if not (0.78 <= a <= 0.86):
        bad("%s: the callout alpha is %.2f, not 0.82" % (kind, a))
    if abs(d.get("radius", 0) - 5) > 0.6:
        bad("%s: the callout corners are %.1f px, not 5" % (kind, d.get("radius", 0)))

delay = hover.get("tooltipDelay")
if label.get("baseDelay") != delay:
    bad("%s: the callout waits %r ms, not the dock's tooltip delay %r" % (
        kind, label.get("baseDelay"), delay))
# Once the callout is up the next icon hands over at once (the dock's warmth);
# that 1 ms is the hand-over, not the callout's own delay.
if label.get("hoverDelay") != 1:
    bad("%s: an open callout hands over in %r ms, not at once" % (kind, label.get("hoverDelay")))

# ---- the pixels: the chip must be on the output, over the wallpaper
def read_ppm(path):
    head, dims, _, px = open(path, "rb").read().split(b"\n", 3)
    assert head == b"P6", head
    w, h = map(int, dims.split())
    return w, h, px

if c:
    chip = c["screen"]
    # The dock window is anchored to the output's bottom, so its content
    # coords start at (0, height - window.height) in screen space.
    win_top = my + mh - int(hover["window"]["h"])
    x0 = max(0, int(round(mx + chip["x"])))
    y0 = max(0, int(round(win_top + chip["y"])))
    x1 = min(mx + mw, int(round(mx + chip["x"] + chip["w"])))
    y1 = min(my + mh, int(round(win_top + chip["y"] + chip["h"])))
    if x1 - x0 < 20 or y1 - y0 < 10:
        bad("%s: the chip's box is off the output (%d..%d, %d..%d)" % (kind, x0, x1, y0, y1))
    else:
        bw, bh, before = read_ppm(sys.argv[3])
        aw, ah, after = read_ppm(sys.argv[4])
        changed = 0
        total = 0
        lumas = []
        for y in range(y0, y1):
            row = (y * aw + x0) * 3
            for i in range(x1 - x0):
                p = row + i * 3
                a = after[p:p+3]
                b = before[p:p+3]
                total += 1
                if a != b:
                    changed += 1
                lumas.append(0.2126 * a[0] + 0.7152 * a[1] + 0.0722 * a[2])
        lumas.sort()
        bg = lumas[len(lumas) // 2]
        ink = lumas[int(len(lumas) * 0.995)]
        # WCAG contrast is computed on linearised sRGB, not on the luma of the
        # gamma-encoded pixels (doing that reported 3.2:1 for a legible chip).
        def linear(v):
            v = v / 255.0
            return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
        def ratio(a, b):
            a, b = max(linear(a), linear(b)), min(linear(a), linear(b))
            return (a + 0.05) / (b + 0.05)
        print("   %s: pixels %d of %d in the chip's box drawn; fill luma %.0f, ink luma %.0f, contrast %.1f:1" % (
            kind, changed, total, bg, ink, ratio(ink, bg)))
        if changed < total * 0.85:
            bad("%s: only %d of %d pixels in the chip's box were drawn" % (kind, changed, total))
        if ink < 150:
            bad("%s: no light text in the chip (99.5th percentile luma %.0f)" % (kind, ink))
        if ratio(ink, bg) < 4.5:
            bad("%s: the chip's text does not read over its own fill (%.1f:1)" % (
                kind, ratio(ink, bg)))

sys.exit(0 if ok else 1)
PY

  warp "$((MX + 40))" "$((MY + 40))"
  sleep 1.8
  rest2=$(state "$kind")
  echo "$rest2" > "$WORK/$kind-rest2.json"
  timeout 10 grim -o "$SCREEN" -t ppm "$WORK/$kind-rest2.ppm" || fail "$kind: grim could not capture the resting dock again"
  if [ -n "${MACOS_TOOLTIP_SHOTS:-}" ]; then
    timeout 10 grim -o "$SCREEN" "$MACOS_TOOLTIP_SHOTS/$kind-rest.png" 2>/dev/null || true
  fi
  python3 - "$WORK/$kind-rest.json" "$WORK/$kind-rest2.json" "$WORK/$kind-rest.ppm" "$WORK/$kind-rest2.ppm" "$kind" <<'PY' || fail "$kind: the resting tile changed"
import json, sys
a = json.load(open(sys.argv[1]))
b = json.load(open(sys.argv[2]))
kind = sys.argv[5]
ok = True
if (b.get("tile") or {}).get("chip"):
    print("   FAIL: %s: the callout is still open with the pointer off the row" % kind, file=sys.stderr); ok = False
if abs(b["tile"]["scale"] - 1) > 0.01:
    print("   FAIL: %s: the icon is still magnified (%.3f)" % (kind, b["tile"]["scale"]), file=sys.stderr); ok = False
if a["tile"]["rect"] != b["tile"]["rect"]:
    print("   FAIL: %s: the tile moved while idle (%r -> %r)" % (kind, a["tile"]["rect"], b["tile"]["rect"]), file=sys.stderr); ok = False

# The artwork itself, pixel for pixel: the resting tile is exactly what it
# was. The card is translucent over an animated wallpaper on the headless
# output, so its surroundings are not a fair comparison; the icon art is
# opaque and is. An inset keeps transparent icon corners (wallpaper behind
# them) out of it.
def read_ppm(path):
    head, dims, _, px = open(path, "rb").read().split(b"\n", 3)
    w, h = map(int, dims.split())
    return w, h, px
w, h, p1 = read_ppm(sys.argv[3])
w2, h2, p2 = read_ppm(sys.argv[4])
top = h - int(a["window"]["h"])
i = a["tile"]["icon"]
ix, iy = i["w"] * 0.15, i["h"] * 0.15
x0 = max(0, int(round(i["x"] + ix)))
y0 = max(0, top + int(round(i["y"] + iy)))
x1 = min(w, int(round(i["x"] + i["w"] - ix)))
y1 = min(h, top + int(round(i["y"] + i["h"] - iy)))
diff = 0
for y in range(y0, y1):
    row = y * w * 3
    for x in range(x0, x1):
        j = row + x * 3
        if p1[j:j+3] != p2[j:j+3]:
            diff += 1
print("   %s: resting scale %.3f, tile %r, chip absent, %d of the art's %d inset pixels differ" % (
    kind, b["tile"]["scale"], b["tile"]["rect"], diff, max(0, (x1 - x0) * (y1 - y0))))
if diff:
    print("   FAIL: %s: the resting tile's artwork changed (%d pixels)" % (kind, diff), file=sys.stderr); ok = False
sys.exit(0 if ok else 1)
PY
}

for kind in app group folder; do
  [ "$(present "$kind")" = "True" ] || { echo; echo "-- $kind: no such tile on this desk, skipped"; continue; }
  echo
  echo "-- $kind: the callout over its magnified icon"
  measure "$kind"
done

# ------------------------------------------------------------ another look
echo
echo "-- another look keeps its own chip"
probe_ipc applyPreset WhiteSur >/dev/null 2>&1 || fail "applyPreset WhiteSur did not answer"
for _ in $(seq 20); do
  OTHER=$(state app)
  [ "$(printf '%s' "$OTHER" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("chipKey",""))' 2>/dev/null)" = "dock" ] && break
  sleep 0.25
done
OTHER=$(state app)
printf '%s' "$OTHER" > "$WORK/other.json"
python3 - "$WORK/other.json" <<'PY' || fail "the WhiteSur look took the macOS chip"
import json, sys
d = json.load(open(sys.argv[1]))
ok = True
if d.get("chipKey") != "dock":
    print("   FAIL: WhiteSur's chip key is %r, not dock" % d.get("chipKey"), file=sys.stderr); ok = False
label = (d.get("tile") or {}).get("label") or {}
if label.get("baseDelay") not in (None, 150):
    print("   FAIL: WhiteSur's name dwell is %r ms, not 150" % label.get("baseDelay"), file=sys.stderr); ok = False
if label.get("chip") not in (None, "dock"):
    print("   FAIL: WhiteSur's label took the %r chip" % label.get("chip"), file=sys.stderr); ok = False
print("   WhiteSur: chip %r, name dwell %r ms" % (d.get("chipKey"), label.get("baseDelay")))
sys.exit(0 if ok else 1)
PY

# ---------------------------------------------------------------- the log
echo
echo "-- the dock's log and the owner's side"
ERR_RE="(TypeError|ReferenceError|is not a function|is not defined|Cannot read property|Unable to assign)"
if grep -inE "$ERR_RE" "$PROBE_DIR/probe.log" | head -5 > "$WORK/log-errors.txt" && [ -s "$WORK/log-errors.txt" ]; then
  sed 's/^/   /' "$WORK/log-errors.txt" >&2
  fail "a runtime error in the dock's log while the callout was up"
else
  note "no runtime error in the dock's log"
fi
[ "$(owner_md5)" = "$OWNER_MD5" ] || fail "the owner's omadock.json changed"
note "owner's omadock.json unchanged (md5 $OWNER_MD5)"
if [ -n "${CURSOR:-}" ]; then
  read -r ox oy <<<"$CURSOR"
  warp "$ox" "$oy"
fi
probe_cleanup || exit 1
headless_stop || fail "the owner's monitor list did not come back"
[ "$(monitor_state)" = "$OWNER_MONITORS" ] || fail "the owner's monitor list is not back"

echo
if [ "$fail" = "0" ]; then
  echo "MACOS-TOOLTIP PASSED: the callout rides each magnified tile (app, group, folder) 6 px above its drawn icon, and the rest of the dock is untouched"
else
  echo "MACOS-TOOLTIP FAILED" >&2
fi
exit $fail
