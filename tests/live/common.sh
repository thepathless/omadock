# Shared by the live tests (sourced).

# Quickshell reloads the plugin whenever any file in its directory changes
# (a commit, __pycache__, an editor's swap file), and the IPC target is gone
# for about half a second. Wait until the dock answers twice in a row.
wait_ready() {
  local i
  for i in $(seq 60); do
    if omarchy-shell omadock state 2>/dev/null | grep -q '"docks"'; then
      sleep 1
      omarchy-shell omadock state 2>/dev/null | grep -q '"docks"' && return 0
    fi
    sleep 0.3
  done
  echo "the dock did not answer over IPC" >&2
  return 1
}
