#!/usr/bin/env bash
# A real Hyprland output with no glass attached, for a suite whose probe dock
# must open or stay visible without anything reaching the owner's screen. The
# probe's config source is pinned to that output (screen + one dock); call this
# BEFORE sourcing probe.sh, because probe.sh reads PROBE_CFG_SRC when it loads.
#
#   OWNER_CFG="${PROBE_CFG_SRC:-$HOME/.config/omarchy/omadock.json}"
#   . tests/live/headless.sh
#   headless_start "$OWNER_CFG" || exit 1
#   . tests/live/probe.sh
#   probe_start ...
#   headless_stop || fail "the monitor list did not come back"
#
# probe_start records the synthetic copy as the "owner" it re-checks; point
# PROBE_OWNER_CFG/MD5 back at OWNER_CFG after it returns. headless_stop is safe
# to call twice and from a cleanup trap: it removes the output, the copy and
# waits for the owner's monitor list to come back.

HEADLESS_SCREEN=""
HEADLESS_SRC=""
HEADLESS_HAVE=""
HEADLESS_OWNER_MONITORS=""
HEADLESS_OWNER_FOCUSED=""

headless_monitors() {
  hyprctl -j monitors | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(" ".join(m["name"] + ("*" if m["focused"] else "") for m in d))'
}

headless_start() {
  local owner=${1:-}
  [ -f "$owner" ] || { echo "headless: no config at $owner" >&2; return 1; }
  command -v hyprctl >/dev/null || { echo "headless: no hyprctl on PATH" >&2; return 1; }
  HEADLESS_SCREEN="OMADOCK-HEADLESS-$$"
  HEADLESS_SRC="$PWD/tests/live/.headless-cfg-$$"
  if hyprctl monitors 2>/dev/null | grep -qE "^(Monitor|  )?${HEADLESS_SCREEN}\b"; then
    echo "headless: REFUSING, an output named $HEADLESS_SCREEN already exists" >&2
    return 1
  fi
  HEADLESS_OWNER_MONITORS=$(headless_monitors)
  HEADLESS_OWNER_FOCUSED=$(headless_monitors | tr ' ' '\n' | grep '\*$' | tr -d '*')
  python3 - "$owner" "$HEADLESS_SRC" "$HEADLESS_SCREEN" <<'PY' || return 1
import json, sys
conf = json.load(open(sys.argv[1]))
conf["screen"] = sys.argv[3]
conf["multiMonitor"] = False
conf["autohide"] = True
conf["intelligentAutohide"] = True
json.dump(conf, open(sys.argv[2], "w"), indent=2)
PY
  hyprctl output create headless "$HEADLESS_SCREEN" >/dev/null 2>&1 || {
    echo "headless: this compositor would not create a headless output" >&2
    return 1
  }
  HEADLESS_HAVE="$HEADLESS_SCREEN"
  sleep 1
  if [ "$(headless_monitors)" = "$HEADLESS_OWNER_MONITORS" ]; then
    echo "headless: the output did not appear in the monitor list" >&2
    headless_stop >/dev/null 2>&1
    return 1
  fi
  # A headless output that took focus would route the owner's typing to a
  # screen they cannot see: hand focus back, then stop.
  case "$(headless_monitors)" in
    *"${HEADLESS_SCREEN}*"*)
      echo "headless: REGRESSION, the output took the owner's focus" >&2
      [ -n "$HEADLESS_OWNER_FOCUSED" ] && hyprctl dispatch focusmonitor "$HEADLESS_OWNER_FOCUSED" >/dev/null 2>&1
      headless_stop >/dev/null 2>&1
      return 1 ;;
  esac
  PROBE_CFG_SRC="$HEADLESS_SRC"
  PROBE_SCREEN="$HEADLESS_SCREEN"
  export PROBE_CFG_SRC PROBE_SCREEN
}

headless_stop() {
  local rc=0
  [ -n "$HEADLESS_HAVE" ] && hyprctl output remove "$HEADLESS_SCREEN" >/dev/null 2>&1
  HEADLESS_HAVE=""
  [ -n "$HEADLESS_SRC" ] && rm -f "$HEADLESS_SRC"
  [ -n "$HEADLESS_OWNER_MONITORS" ] || return 0
  for _ in $(seq 10); do
    [ "$(headless_monitors)" = "$HEADLESS_OWNER_MONITORS" ] && return 0
    sleep 0.3
  done
  echo "headless: the monitor list did not come back" >&2
  return 1
}
