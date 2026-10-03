#!/usr/bin/env bash
# Live: malformed omadock.json contents must not break the dock, and a
# settings save (setAlignment) must leave a file that is not a readable JSON
# object untouched; readable objects are saved with their values bounded.
# Backs up the config and restores it on exit.
set -u
cd "$(dirname "$0")/../.."
. tests/live/common.sh
wait_ready || exit 1
CFG=$HOME/.config/omarchy/omadock.json
bak=$(mktemp); cp "$CFG" "$bak"
work=$(mktemp -d)
restore() { cp "$bak" "$CFG"; rm -rf "$bak" "$work"; }
trap restore EXIT
since=$(date '+%Y-%m-%d %H:%M:%S')
rc=0

python3 - "$work" <<'EOF'
import json, pathlib, sys
w = pathlib.Path(sys.argv[1])
cases = {
    "empty": "", "garbage": "garbage{", "null": "null", "array": "[]", "string": '"str"',
    "infinity": '{"iconSize": 1e999, "systemBlurSize": 1e999}',
    "wrong-types": '{"iconSize": "big", "pinned": 5, "appGroups": "x", "autohide": "yes"}',
    "array-like": '{"appGroups": {"length": 1000000}, "pinnedFolders": {"length": 1000000}}',
    "bad-sound": '{"urgentSoundName": "../../../etc/passwd", "urgentSound": true}',
    "relative-folder": '{"pinnedFolders": [{"path": "-x"}, {"path": "rel"}]}',
    "oversize": json.dumps({"pad": "x" * (2 * 1024 * 1024)}),
}
for name, text in cases.items():
    (w / name).write_text(text)
EOF

# Files that must survive a save byte for byte: rewriting them from {}
# would drop every key the dock does not own. "infinity" belongs here: QML's
# JSON.parse rejects 1e999, so to the dock that file is unreadable too.
keep=" garbage null array string oversize infinity "
for f in "$work"/*; do
  name=$(basename "$f")
  cp "$f" "$CFG"
  sleep 1.5
  hyprctl layers | grep -q "namespace: omadock" || { echo "FAIL $name: dock layer gone"; rc=1; }
  omarchy-shell omadock setAlignment center >/dev/null
  sleep 1
  if [ "${keep#* $name }" != "$keep" ]; then
    cmp -s "$f" "$CFG" || { echo "FAIL $name: a save rewrote a file it cannot read"; rc=1; }
  else
    python3 - "$CFG" "$name" <<'PY' || rc=1
import json, sys
path, name = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(path))
except ValueError as e:
    sys.exit(f"FAIL {name}: saved file is not JSON ({e})")
if not isinstance(d, dict):
    sys.exit(f"FAIL {name}: saved file is not an object")
if not 0 <= d.get("systemBlurSize", 0) <= 100:
    sys.exit(f"FAIL {name}: systemBlurSize {d['systemBlurSize']} saved unbounded")
if d.get("urgentSoundName", "bell") != "bell" and name == "bad-sound":
    sys.exit(f"FAIL {name}: urgentSoundName {d['urgentSoundName']!r} saved")
if any(not str(f.get("path", "")).startswith(("/", "~")) for f in d.get("pinnedFolders", [])):
    sys.exit(f"FAIL {name}: relative pinned folder saved")
PY
  fi
done

cp "$bak" "$CFG"; sleep 1.5
bash tests/smoke-test.sh >/dev/null || { echo "FAIL: smoke test after fuzz"; rc=1; }
if journalctl --user --since "$since" | grep -iE "omadock/.*(TypeError|ReferenceError|is not a)"; then
  echo "FAIL: runtime errors in the log"; rc=1
fi
[ $rc = 0 ] && echo "CONFIG FUZZ PASSED"
exit $rc
