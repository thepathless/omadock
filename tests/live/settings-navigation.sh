#!/usr/bin/env bash
# NON-INTRUSIVE. Actual SettingsPanel + Qt key events, no compositor input.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OWNER_CFG="${PROBE_CFG_SRC:-$HOME/.config/omarchy/omadock.json}"
OWNER_MD5=$(md5sum "$OWNER_CFG" | cut -d' ' -f1)
WORK=$(mktemp -d "$PWD/tests/live/.settings-test-XXXXXX") || exit 1
. tests/live/headless.sh
cleanup() {
  if declare -F probe_cleanup >/dev/null; then probe_cleanup; fi
  headless_stop
  rm -rf "$WORK"
}
trap cleanup EXIT
fail() { echo "SETTINGS FAILED: $*" >&2; if declare -F probe_log_tail >/dev/null; then probe_log_tail >&2; fi; exit 1; }
mkdir -p "$WORK/TestInput"
/usr/lib/qt6/moc $(pkg-config --cflags Qt6Core Qt6Qml Qt6Quick Qt6Test) tests/live/settings-input.cpp -o "$WORK/settings-input.moc" || fail moc
c++ -std=c++17 -shared -fPIC tests/live/settings-input.cpp -I"$WORK" \
  $(pkg-config --cflags --libs Qt6Core Qt6Gui Qt6Qml Qt6Quick Qt6Test) \
  -o "$WORK/TestInput/libsettingsinput.so" || fail "input helper build"
printf 'module TestInput\nplugin settingsinput\n' > "$WORK/TestInput/qmldir"
printf 'import TestInput 1.0\nSettingsInput {}\n' > "$WORK/Input.qml"
# Inherit every production binding; disable only the keyboard grab before map.
printf 'import QtQuick\nimport Quickshell.Wayland\nimport "file:%s/components" as DockUi\nDockUi.SettingsPanel { WlrLayershell.keyboardFocus: WlrKeyboardFocus.None }\n' "$PWD" > "$WORK/Panel.qml"
SETTINGS_INPUT_QML="$WORK/Input.qml"
SETTINGS_PANEL_QML="$WORK/Panel.qml"
QML_IMPORT_PATH="$WORK${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
export SETTINGS_INPUT_QML SETTINGS_PANEL_QML QML_IMPORT_PATH
headless_start "$OWNER_CFG" || fail "headless bootstrap safety guard"
. tests/live/probe.sh
PROBE_BODY="$PWD/tests/live/settings-navigation-shell.qml"
export PROBE_BODY
probe_start || fail "dock load"
PROBE_OWNER_CFG="$OWNER_CFG"
PROBE_OWNER_MD5="$OWNER_MD5"
call() { qs -p "$PROBE_DIR" ipc call omadock-settings-test run "$@"; }
# Seed dependency cases only in the disposable config before opening the panel.
python3 - "$(probe_cfg)" <<'PY'
import json, sys
p=sys.argv[1]; c=json.load(open(p))
c.update(showBackground=False, blur="system", labelMode="off", iconStyle="original", showNotificationBadges=False,
         layout="dock", alignment="center", showTooltips=False)
# A group row for the keyboard check, on any host: the owner's copy may pin none.
if not any(g.get("id") == "omadock_probe_group" for g in c.get("appGroups") or []):
    c["appGroups"] = (c.get("appGroups") or []) + [{"id": "omadock_probe_group", "name": "Probe Group",
                                                     "icon": "folder", "apps": [], "cols": 2, "before": ""}]
json.dump(c,open(p,"w"),indent=2)
PY
sleep 1
call open '' > "$WORK/open.json"
python3 - "$WORK/open.json" <<'PY' || fail "panel creation"
import json,sys
assert json.load(open(sys.argv[1])).get("opened")
PY
sleep 1
check() {
  call read "$1" > "$WORK/read.json"
  python3 - "$WORK/read.json" "$2" "$3" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); mode,arg=sys.argv[2:]
assert not r.get("error"),r
if mode=="page": assert r["page"]==arg,r
elif mode=="target":
    assert r["row"] and r["row"]["visible"] and r["target"]==arg,r
    assert r["scroll"] <= r["row"]["y"] + r["row"]["height"],r
    assert r["row"]["y"] < r["scroll"] + r["viewport"],r
elif mode=="dependency":
    assert r["row"]["dependency"]["key"]==arg,r
    assert len(r["row"]["hint"])>15,r
elif mode=="config":
    key,val=arg.split("=",1)
    assert str(r["config"][key]).lower()==val,r
elif mode=="focus": assert r["focus"]==arg,r
elif mode=="editing-preset": assert r["editing"]["preset"]==arg,r
elif mode=="editing-group": assert r["editing"]["group"]==arg,r
elif mode=="collapsed": assert all(not a["expanded"] for a in r["advanced"]),r
elif mode=="expanded": assert any(a["expanded"] and a["title"]==arg for a in r["advanced"]),r
elif mode=="section-collapsed": assert any(not a["expanded"] and a["title"]==arg for a in r["advanced"]),r
elif mode=="categories": assert r["categories"]==["presets","appearance","placement","behavior","folders","about"],r
PY
}
wait_check() {
  local i
  for i in $(seq 25); do check "$@" >/dev/null 2>&1 && return 0; sleep 0.2; done
  check "$@"; fail "$*"
}
send() {
  call key "$1" | python3 -c 'import json,sys; assert json.load(sys.stdin).get("keySent")' || fail "key $1"
}
wait_check '' categories ''
wait_check '' collapsed ''
cp "$(probe_cfg)" "$WORK/before-navigation.json"
for category in presets appearance placement behavior folders about; do
  call category "$category" >/dev/null
  wait_check '' page "$category"
  echo "   Enter on category: $category"
done
for spec in labels:appearance icons:appearance motion:appearance groups:folders supporters:about; do
  IFS=: read -r old category <<< "$spec"
  call legacy "$old" >/dev/null
  wait_check '' page "$category"
done
# Search, Enter activation and dependency links never change persisted values.
call search 'blur strength' > "$WORK/search.json"
python3 - "$WORK/search.json" <<'PY' || fail "blur search ranking"
import json,sys
assert json.load(open(sys.argv[1]))["hits"][0]["key"]=="blurSize"
PY
call enter-search '' >/dev/null
wait_check blurSize target blurSize
wait_check blurSize dependency showBackground
call read blurSize
send settings-prerequisite-blurSize:Return
wait_check showBackground target showBackground
call goto blurSystem >/dev/null
wait_check blurSystem target blurSystem
for key in labelPlateHeight iconTint badgePosition perMonitorApps appsButtonAction; do
  call goto "$key" >/dev/null
  wait_check "$key" target "$key"
done
# Exercise every indexed target against the actual, laid-out QML tree.
call targets '' > "$WORK/targets.json"
mapfile -t targets < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))))' "$WORK/targets.json")
[ "${#targets[@]}" -eq 88 ] || fail "expected 88 search targets, found ${#targets[@]}"
for key in "${targets[@]}"; do
  call goto "$key" >/dev/null
  wait_check "$key" target "$key"
done
echo "   all ${#targets[@]} search targets reached a visible row in the viewport"

# The icon-theme picker: the host's installed themes are listed and the current
# one is read from the desktop, without applying anything.
call read iconTheme > "$WORK/themes.json"
python3 - "$WORK/themes.json" <<'PY' || fail "icon theme picker"
import glob, json, os, sys
r=json.load(open(sys.argv[1]))
t=r["themes"]
assert t["installed"] >= 5, t
assert t["current"], t
assert "iconTheme" in r["visibleKeys"], r["visibleKeys"]
# The folder artwork is a real file, and the index is theme-first: when a theme
# the desktop inherits from ships the icon, that theme's copy must win. A theme
# that ships none (Yaru-yellow has no plain `folder`) leaves the fallback to
# whatever does; asserting a particular fallback theme would be wrong here.
folder=t["folder"]
assert os.path.isfile(folder), folder
assert "/icons/" in folder, folder
def ships(theme):
  home=os.path.expanduser("~")
  return any(glob.glob(base + "/**/folder." + ext, recursive=True)
             for base in (f"/usr/share/icons/{theme}", f"{home}/.icons/{theme}",
                          f"{home}/.local/share/icons/{theme}") for ext in ("svg", "png"))
providers=[c for c in t["chain"] if ships(c)]
if providers:
  assert f"/icons/{providers[0]}/" in folder or f"/.icons/{providers[0]}/" in folder, (providers, folder)
# The macOS set is offered as a click, not silently downloaded: the row is
# there while WhiteSur is absent and gone once its chips carry the theme.
w=t["whiteSur"]
if not t["whiteSurInstalled"]:
  assert w["found"] and w["visible"] and "WhiteSur" in w["text"], w
else:
  assert not w["found"], w
PY
call search 'whitesur' > "$WORK/theme-search.json"
python3 - "$WORK/theme-search.json" <<'PY' || fail "icon theme search"
import json,sys
hits=json.load(open(sys.argv[1]))["hits"]
assert hits and any(h["key"] == "iconTheme" for h in hits), hits
PY
echo "   icon theme picker lists the desktop's themes and search finds it"
python3 - "$WORK/before-navigation.json" "$(probe_cfg)" <<'PY' || fail "navigation changed config"
import json,sys
assert json.load(open(sys.argv[1]))==json.load(open(sys.argv[2])),"navigation/search wrote settings"
PY
echo '   dependency targets are visible, explained and scrolled into view; navigation writes nothing'

# Native themed ButtonGroup: arrows move the candidate, Enter commits it.
call goto minimizeMode >/dev/null
wait_check minimizeMode target minimizeMode
send settings-choice-minimizeMode:Left
send settings-choice-minimizeMode:Return
wait_check minimizeMode config minimizeMode=off
send settings-choice-minimizeMode:Right
send settings-choice-minimizeMode:Return
wait_check minimizeMode config minimizeMode=active
send settings-choice-minimizeMode:Tab
wait_check '' focus 'settings-disclosure-Advanced window behavior'
send 'settings-disclosure-Advanced window behavior:Backtab'
wait_check '' focus settings-choice-minimizeMode
# Switch, slider and disclosure all receive genuine Qt key events too.
call goto showBackground >/dev/null
wait_check showBackground target showBackground
send settings-switch-showBackground:Space
wait_check showBackground config showBackground=true
call goto iconSize >/dev/null
wait_check iconSize target iconSize
call read iconSize > "$WORK/icon-before.json"
send settings-slider-iconSize:Right
call read iconSize > "$WORK/icon-after.json"
python3 - "$WORK/icon-before.json" "$WORK/icon-after.json" <<'PY' || fail "slider keyboard change"
import json,sys
before,after=(json.load(open(p))["config"]["iconSize"] for p in sys.argv[1:])
assert after==before+2,(before,after)
PY
call category appearance >/dev/null
# Search above opened this section. Enter must close it, then reopen it.
wait_check '' expanded 'Advanced icon effects'
send 'settings-disclosure-Advanced icon effects:Return'
wait_check '' section-collapsed 'Advanced icon effects'
send 'settings-disclosure-Advanced icon effects:Return'
wait_check '' expanded 'Advanced icon effects'
send settings-category-appearance:Down
wait_check '' page placement

# Rows that used to be mouse-only take the keyboard as well.
call category presets >/dev/null
wait_check '' page presets
call read presets > "$WORK/presets.json"
preset_id=$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1]))["config"]["presets"]; print(p[0]["id"] if p else "")' "$WORK/presets.json")
[ -n "$preset_id" ] || fail "no saved preset to rename"
send "settings-preset-name-$preset_id:Return"
wait_check '' editing-preset "$preset_id"
send "settings-preset-name-$preset_id:Escape"
wait_check '' editing-preset ''
call category folders >/dev/null
wait_check '' page folders
send settings-group-name-omadock_probe_group:Return
wait_check '' editing-group omadock_probe_group
send settings-group-name-omadock_probe_group:Escape
wait_check '' editing-group ''
echo '   choice arrows/Enter, Tab, toggle Space, slider Right, disclosure Enter, category Down and rename rows passed'

call close '' >/dev/null
call open '' >/dev/null
sleep 0.3
wait_check '' collapsed ''
call close '' >/dev/null
if grep -inE 'TypeError|ReferenceError|Unable to assign|Cannot assign|is not a function|is not defined|Binding loop|Error:' "$(probe_log)"; then fail 'runtime log'; fi
probe_cleanup || fail 'probe cleanup'
headless_stop || fail 'monitor restoration'
rm -rf "$WORK"
trap - EXIT
echo 'SETTINGS PASSED: actual QML surface, synthetic Qt keys; owner configuration, PID and monitors unchanged'
