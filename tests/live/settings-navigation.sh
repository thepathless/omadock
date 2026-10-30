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
# The picker's apply writes gsettings. This suite must never change the owner's
# desktop theme, so a stub shadows `gsettings set` for the probe process only:
# it logs the call and lets every read (the dock's own probe included) through.
REAL_GSETTINGS=$(command -v gsettings)
mkdir -p "$WORK/bin"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = "set" ]; then printf "%%s\\n" "$*" >> "%s"; exit 0; fi\nexec %s "$@"\n' \
  "$WORK/gsettings.log" "$REAL_GSETTINGS" > "$WORK/bin/gsettings"
chmod +x "$WORK/bin/gsettings"
export OMADOCK_TEST_GSETTINGS_LOG="$WORK/gsettings.log"
PATH="$WORK/bin:$PATH"
export PATH
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
# A disposable installed theme, present before the panel reads the list and
# removed later to exercise a stale selection without touching the owner.
mkdir -p "$PROBE_DIR/home/.local/share/icons/ProbeTheme/apps"
printf '[Icon Theme]\nName=ProbeTheme\n' > "$PROBE_DIR/home/.local/share/icons/ProbeTheme/index.theme"
printf '<svg/>' > "$PROBE_DIR/home/.local/share/icons/ProbeTheme/apps/app.svg"
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

# The icon-theme picker is one searchable dropdown: the desktop's installed
# themes plus the WhiteSur set, opened from the theme in use. Opening or
# filtering it applies nothing.
call category appearance >/dev/null
wait_check '' page appearance
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
# The macOS set is an entry in the list while it is absent - never a silent
# download - and simply another installed theme once it is on disk.
w=t["whiteSur"]
if not t["whiteSurInstalled"]:
  assert w["found"] and w["visible"] and w["installEntry"], w
  assert "whitesur" in w["text"].lower() and "install" in w["text"].lower(), w
else:
  assert w["found"] and not w["installEntry"], w
PY
call read-dropdown settings-icon-theme-dropdown > "$WORK/theme-dropdown.json"
python3 - "$WORK/theme-dropdown.json" "$WORK/themes.json" <<'PY' || fail "icon theme dropdown"
import json,sys
d=json.load(open(sys.argv[1])); t=json.load(open(sys.argv[2]))["themes"]
assert d["found"] and d["visible"] and not d["open"], d
# It opens from the current selection, listing every installed theme beside
# the WhiteSur entry.
assert d["value"] == t["current"] and d["current"] == t["current"], (d["value"], d["current"], t["current"])
installed=[o["value"] for o in d["options"] if not o["value"].startswith("__install")]
assert len(installed) == t["installed"], (len(installed), t["installed"])
PY
call search 'whitesur' > "$WORK/theme-search.json"
python3 - "$WORK/theme-search.json" <<'PY' || fail "icon theme search"
import json,sys
hits=json.load(open(sys.argv[1]))["hits"]
assert hits and any(h["key"] == "iconTheme" for h in hits), hits
PY

# Synthetic Qt keys only: Enter opens the list, letters filter it in place,
# Down/Up walk it, Enter applies through the existing system-wide path.
REAL_BEFORE=$("$REAL_GSETTINGS" get org.gnome.desktop.interface icon-theme)
before_theme=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["themes"]["current"])' "$WORK/themes.json")
call key-trigger settings-icon-theme-dropdown:Return >/dev/null || fail "dropdown Enter"
open_ok=0
for _ in $(seq 25); do
  call read-dropdown settings-icon-theme-dropdown > "$WORK/dd-open.json"
  python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["open"] else 1)' "$WORK/dd-open.json" && { open_ok=1; break; }
  sleep 0.2
done
[ "$open_ok" -eq 1 ] || fail "the dropdown did not open on Enter"
# The search field takes focus one event-loop turn after the popup maps.
sleep 0.3
call read iconTheme > "$WORK/themes-open.json"
python3 - "$WORK/themes-open.json" <<'PY' || fail "the panel stands down while the list is open"
import json,sys
r=json.load(open(sys.argv[1]))
assert r["iconThemeDropdownOpen"], r
assert r["themes"]["current"] == r["themes"]["whiteSur"]["value"], r
PY
for k in Y A R; do call key-focused settings-icon-theme-dropdown:$k >/dev/null || fail "typing $k"; done
sleep 0.2
call read-dropdown settings-icon-theme-dropdown > "$WORK/dd-yar.json"
python3 - "$WORK/dd-yar.json" <<'PY' || fail "the dropdown filters as you type"
import json,sys
d=json.load(open(sys.argv[1]))
assert d["open"] and d["filtered"], d
assert "Yaru" in d["filtered"], d
by={o["value"]: o for o in d["options"]}
for v in d["filtered"]:
  o=by[v]
  assert "yar" in (v + " " + o["label"] + " " + o["description"]).lower(), o
assert len(d["filtered"]) < len(d["options"]), d
PY
call key-focused settings-icon-theme-dropdown:Down >/dev/null
call key-focused settings-icon-theme-dropdown:Down >/dev/null
call key-focused settings-icon-theme-dropdown:Up >/dev/null
call key-focused settings-icon-theme-dropdown:Return >/dev/null
applied=0
for _ in $(seq 40); do
  call read iconTheme > "$WORK/themes-applied.json"
  python3 -c 'import json,sys; t=json.load(open(sys.argv[1]))["themes"]; sys.exit(0 if t["current"] != sys.argv[2] else 1)' "$WORK/themes-applied.json" "$before_theme" && { applied=1; break; }
  sleep 0.2
done
[ "$applied" -eq 1 ] || fail "Enter on the filtered list did not apply a theme"
python3 - "$WORK/themes-applied.json" "$before_theme" <<'PY' || fail "dropdown Enter applied the wrong theme"
import json,sys
t=json.load(open(sys.argv[1]))["themes"]
assert t["current"] == "Yaru" and t["current"] != sys.argv[2], (t["current"], sys.argv[2])
assert t["whiteSur"]["value"] == "Yaru", t["whiteSur"]
PY
grep -qxF 'set org.gnome.desktop.interface icon-theme Yaru' "$OMADOCK_TEST_GSETTINGS_LOG" \
  || fail "the selection did not go through the existing apply path"
[ "$("$REAL_GSETTINGS" get org.gnome.desktop.interface icon-theme)" = "$REAL_BEFORE" ] \
  || fail "the probe changed the owner's icon theme"
# Escape closes the list without applying: state, panel and gsettings untouched.
count_before=$(wc -l < "$OMADOCK_TEST_GSETTINGS_LOG")
call key-trigger settings-icon-theme-dropdown:Return >/dev/null
for _ in $(seq 25); do
  call read-dropdown settings-icon-theme-dropdown > "$WORK/dd-reopen.json"
  python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["open"] else 1)' "$WORK/dd-reopen.json" && break
  sleep 0.2
done
sleep 0.3
for k in B R E E; do call key-focused settings-icon-theme-dropdown:$k >/dev/null; done
sleep 0.2
call read-dropdown settings-icon-theme-dropdown > "$WORK/dd-bree.json"
python3 - "$WORK/dd-bree.json" <<'PY' || fail "the second filter"
import json,sys
d=json.load(open(sys.argv[1]))
by={o["value"]: o for o in d["options"]}
assert d["open"] and d["filtered"] and "breeze-dark" in d["filtered"], d
assert len(d["filtered"]) < len(d["options"]), d
for v in d["filtered"]:
  o=by[v]
  assert "bree" in (v + " " + o["label"] + " " + o["description"]).lower(), o
PY
call key-focused settings-icon-theme-dropdown:Escape >/dev/null
sleep 0.3
call read-dropdown settings-icon-theme-dropdown > "$WORK/dd-escape.json"
call read iconTheme > "$WORK/themes-escape.json"
python3 - "$WORK/dd-escape.json" "$WORK/themes-escape.json" <<'PY' || fail "Escape must close the list without applying"
import json,sys
d=json.load(open(sys.argv[1])); r=json.load(open(sys.argv[2]))
assert not d["open"], d
assert d["value"] == "Yaru" and r["themes"]["current"] == "Yaru", (d["value"], r["themes"]["current"])
assert not r["iconThemeDropdownOpen"], r
assert r["page"] == "appearance" and r["themes"]["current"] == "Yaru", r
PY
[ "$(wc -l < "$OMADOCK_TEST_GSETTINGS_LOG")" -eq "$count_before" ] || fail "Escape applied an icon theme"
echo "   icon theme dropdown: opens from the selection, filters, Enter applies, Escape cancels"

# A theme that disappears after the list was read must fail through the row,
# not apply a stale id, log a gsettings write, or crash. ProbeTheme was made
# before the panel opened; remove it and choose it from the loaded list.
rm -rf "$PROBE_DIR/home/.local/share/icons/ProbeTheme"
count_before=$(wc -l < "$OMADOCK_TEST_GSETTINGS_LOG")
call key-trigger settings-icon-theme-dropdown:Return >/dev/null || fail "removed-theme dropdown"
for _ in $(seq 25); do
  call read-dropdown settings-icon-theme-dropdown > "$WORK/dd-removed-open.json"
  python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["open"] else 1)' "$WORK/dd-removed-open.json" && break
  sleep 0.2
done
sleep 0.3
for k in P R O B E; do call key-focused settings-icon-theme-dropdown:$k >/dev/null || fail "typing missing theme"; done
sleep 0.2
call read-dropdown settings-icon-theme-dropdown > "$WORK/dd-removed.json"
python3 - "$WORK/dd-removed.json" <<'PY' || fail "removed theme was not offered from the stale list"
import json,sys
d=json.load(open(sys.argv[1]))
assert d["open"] and "ProbeTheme" in d["filtered"], d
PY
call key-focused settings-icon-theme-dropdown:Down >/dev/null
call key-focused settings-icon-theme-dropdown:Return >/dev/null
removed_failed=0
for _ in $(seq 40); do
  call read iconTheme > "$WORK/themes-removed.json"
  python3 - "$WORK/themes-removed.json" <<'PY' 2>/dev/null && { removed_failed=1; break; }
import json,sys
r=json.load(open(sys.argv[1]))
t=r["themes"]
assert "not installed" in t["error"], r
assert "ProbeTheme" not in t["installedIds"], r
PY
  sleep 0.2
done
[ "$removed_failed" -eq 1 ] || fail "the removed theme did not surface an error and refresh the list"
python3 - "$WORK/themes-removed.json" <<'PY' || fail "removed theme left stale state"
import json,sys
r=json.load(open(sys.argv[1]))
assert r["themes"]["current"] == "Yaru", r
assert "ProbeTheme" not in r["themes"]["installedIds"], r
PY
[ "$(wc -l < "$OMADOCK_TEST_GSETTINGS_LOG")" -eq "$count_before" ] \
  || fail "a removed theme reached gsettings"
call key-focused settings-icon-theme-dropdown:Escape >/dev/null
sleep 0.2
echo "   removed theme: row reports not installed, list refreshes, gsettings untouched"

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
