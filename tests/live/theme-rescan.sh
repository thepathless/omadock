#!/usr/bin/env bash
# NON-INTRUSIVE. A failed apply that lands while the theme list is still being
# read must queue one more read, not be lost behind the stale snapshot.
#
# The dock under test is a copy of this tree with one change: scripts/icon-theme.sh
# captures its `list` output, sleeps, then prints it. That makes the read that
# started before ProbeTheme was removed finish with the stale id, exactly the
# race a slow disk or a busy machine produces. The apply then fails while that
# read is still in flight. Without the queue the picker would keep advertising
# ProbeTheme forever; with it, a second read lands after the removal.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OWNER_CFG="${PROBE_CFG_SRC:-$HOME/.config/omarchy/omadock.json}"
OWNER_MD5=$(md5sum "$OWNER_CFG" | cut -d' ' -f1)
WORK=$(mktemp -d "$PWD/tests/live/theme-rescan-XXXXXX") || exit 1
. tests/live/probe.sh
cleanup() {
  if declare -F probe_cleanup >/dev/null; then probe_cleanup; fi
  rm -rf "$WORK"
}
trap cleanup EXIT
fail() { echo "THEME RESCAN FAILED: $*" >&2; if declare -F probe_log_tail >/dev/null; then probe_log_tail >&2; fi; exit 1; }

# The probe must never write the owner's dconf, even by accident.
REAL_GSETTINGS=$(command -v gsettings)
mkdir -p "$WORK/bin"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = "set" ]; then printf "%%s\\n" "$*" >> "%s"; exit 0; fi\nexec %s "$@"\n' \
  "$WORK/gsettings.log" "$REAL_GSETTINGS" > "$WORK/bin/gsettings"
chmod +x "$WORK/bin/gsettings"
PATH="$WORK/bin:$PATH"
export PATH

# A copy of the plugin, with the helper wrapped. The wrapper's `list` snapshots
# the disk first and only then pauses, so the read is genuinely stale.
mkdir -p "$WORK/plugin"
cp -a DockHost.qml Dock.qml ./*.js components scripts i18n shaders assets fonts manifest.json "$WORK/plugin/" \
  || fail "plugin copy"
cp "$WORK/plugin/scripts/icon-theme.sh" "$WORK/real-icon-theme.sh" || fail "helper copy"
cat > "$WORK/plugin/scripts/icon-theme.sh" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = list ]; then
  out=$(bash "$OMADOCK_THEME_REAL" list)
  touch "$HOME/.theme-rescan-captured"
  sleep 2
  printf '%s\n' "$out"
  exit 0
fi
exec bash "$OMADOCK_THEME_REAL" "$@"
SH
OMADOCK_THEME_REAL="$WORK/real-icon-theme.sh"
export OMADOCK_THEME_REAL

# probe.sh imports PROBE_ROOT into the generated shell.qml; point it at the
# copy so LocalAppLibrary resolves the wrapped helper.
PROBE_ROOT="$WORK/plugin"
PROBE_BODY="$PWD/tests/live/theme-rescan-shell.qml"
export PROBE_BODY
probe_start || fail "dock load"
PROBE_OWNER_CFG="$OWNER_CFG"
PROBE_OWNER_MD5="$OWNER_MD5"
call() { qs -p "$PROBE_DIR" ipc call theme-rescan-test "$@"; }

# The disposable theme is created after the probe's own first read.
mkdir -p "$PROBE_DIR/home/.local/share/icons/ProbeTheme/apps"
printf '[Icon Theme]\nName=ProbeTheme\n' > "$PROBE_DIR/home/.local/share/icons/ProbeTheme/index.theme"
printf '<svg/>' > "$PROBE_DIR/home/.local/share/icons/ProbeTheme/apps/app.svg"

wait_state() {
  local i
  for i in $(seq 50); do
    call state > "$WORK/state.json"
    python3 - "$WORK/state.json" "$@" <<'PY' 2>/dev/null && return 0
import json, sys
r = json.load(open(sys.argv[1]))
assert not r.get("error"), r
if sys.argv[2] == "has":
    assert sys.argv[3] in r["ids"], r
elif sys.argv[2] == "absent":
    assert "not installed" in r["themeError"], r
    assert sys.argv[3] not in r["ids"], r
    assert r["pending"] is False, r
PY
    sleep 0.2
  done
  cat "$WORK/state.json" >&2
  return 1
}

# Let the first (slow) read see ProbeTheme, then take it away and start a read
# whose snapshot still contains it.
call refresh >/dev/null
wait_state has ProbeTheme || fail "the initial read never saw ProbeTheme"
# Let any scan queued behind that read finish before starting the stale one,
# so the marker below belongs to this read and not an earlier one.
sleep 2.5
before_current=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["current"])' "$WORK/state.json")
rm -f "$PROBE_DIR/home/.theme-rescan-captured"
call refresh >/dev/null
for _ in $(seq 50); do
  [ -f "$PROBE_DIR/home/.theme-rescan-captured" ] && break
  sleep 0.05
done
[ -f "$PROBE_DIR/home/.theme-rescan-captured" ] || fail "the stale read never started"
rm -rf "$PROBE_DIR/home/.local/share/icons/ProbeTheme"
call applyTheme ProbeTheme >/dev/null

# The apply fails during the stale read. Poll for the queued read's result: the
# row reports the honest failure and the stale id is gone from the list.
wait_state absent ProbeTheme || fail "the queued read did not replace the stale list"
python3 - "$WORK/state.json" "$before_current" <<'PY' || fail "stale state after the queued read"
import json, sys
r = json.load(open(sys.argv[1]))
assert r["current"] == sys.argv[2], r
assert r["themeError"].startswith("icon-theme: theme is not installed"), r
PY
if [ -s "$WORK/gsettings.log" ]; then
  cat "$WORK/gsettings.log" >&2
  fail "a removed theme reached gsettings"
fi
echo "   stale theme-list read: failed apply, queued read, no stale id, no gsettings write"
probe_cleanup || fail "probe cleanup"
rm -rf "$WORK"
trap - EXIT
echo "THEME RESCAN PASSED: a failed apply behind a running read refreshes the list; owner untouched"
