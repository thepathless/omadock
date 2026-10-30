#!/usr/bin/env bash
# Icon themes for the whole desktop.
#
#   icon-theme.sh list            one "id|Name|Inherits" line per complete theme
#   icon-theme.sh apply <id>      make an installed <id> the desktop's icon theme
#   icon-theme.sh install         fetch, verify and apply the WhiteSur (macOS) icons
#
# `list` reads the index.theme of every icon directory the freedesktop spec
# names, but only advertises a directory that actually has icon artwork: an
# index.theme left behind by an interrupted copy is not a theme. `apply` refuses
# an id that is not installed and complete before it writes anything. `apply`
# writes the same places the desktop reads: gsettings (GTK and, with
# QT_QPA_PLATFORMTHEME=gtk3, Qt), both GTK settings files, ~/.icons/default,
# the staged Omarchy theme, and KDE/Qt config files when they exist. Existing
# keys in those files are preserved; nothing outside $HOME is written and no
# privilege is requested.
#
# `install` clones into a staging directory outside the icon roots, runs
# upstream's installer there, verifies the resulting theme, and only then moves
# complete theme directories into ~/.local/share/icons. A failed or interrupted
# download/install therefore leaves no half-populated theme for `list` to
# advertise, and a retry starts from a clean stage. An already-installed
# WhiteSur is applied without downloading again.
#
# Usage from a QML panel: the theme id is passed as an argument, never spliced
# into a command line.

set -uo pipefail

theme_dirs() {
  printf '%s\n' "$HOME/.icons" "$HOME/.local/share/icons" /usr/share/icons
}

# The same rule as DockIconTheme.safeId: an id is a directory name, passed as
# one argv element to gsettings, never parsed by a shell.
valid_id() {
  local id=${1:-}
  # Exact byte set, not a locale-sensitive range: `[A-Za-z]` under a UTF-8
  # locale can accept non-ASCII letters, which is why this is a case pattern.
  case "$id" in
    ''|[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789]*) return 1 ;;
  esac
  case "$id" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-]*) return 1 ;;
  esac
  return 0
}

# An index.theme without any artwork is what an interrupted install leaves
# behind. Find one real icon file (Yaru and friends put it under 16x16/apps,
# not a top-level apps) so that prefix is never advertised or applied.
theme_complete() {
  local dir=$1 found
  [ -f "$dir/index.theme" ] || return 1
  found=$(find "$dir" -type f \( -path '*/apps/*' -o -path '*/places/*' \
    -o -path '*/devices/*' -o -path '*/mimetypes/*' \) -print -quit 2>/dev/null)
  [ -n "$found" ]
}

# The first installed, complete copy of an id, in the freedesktop lookup order.
theme_path() {
  local id=$1 base
  while IFS= read -r base; do
    if [ -f "$base/$id/index.theme" ] && theme_complete "$base/$id"; then
      printf '%s\n' "$base/$id"
      return 0
    fi
  done < <(theme_dirs)
  return 1
}

# Split an index.theme into "Name" and "Inherits", from its [Icon Theme]
# section only: later sections (ScaledDirectories etc.) carry no theme name.
index_field() {
  awk -v want="$1" '
    /^\[/ { main = ($0 == "[Icon Theme]") ; next }
    main && index($0, want "=") == 1 { print substr($0, length(want) + 2); exit }
  ' "$2"
}

list_themes() {
  local base dir id name inherits
  while IFS= read -r base; do
    [ -d "$base" ] || continue
    for dir in "$base"/*; do
      [ -f "$dir/index.theme" ] || continue
      id=$(basename "$dir")
      # hicolor/default/locolor are lookup fallbacks, not choosable themes.
      case "$id" in
        .*) continue ;;
        hicolor|locolor|default|default-dark) continue ;;
      esac
      valid_id "$id" || continue
      theme_complete "$dir" || continue
      name=$(index_field Name "$dir/index.theme")
      [ -n "$name" ] || continue
      inherits=$(index_field Inherits "$dir/index.theme")
      printf '%s|%s|%s\n' "$id" "$name" "$inherits"
    done
  done < <(theme_dirs)
}

# Replace or add gtk-icon-theme-name in a GTK settings file, keeping every
# other key. A file without a [Settings] section gets one.
write_gtk_settings() {
  local file=$1 theme=$2 tmp
  mkdir -p "$(dirname "$file")" || return 1
  if [ ! -f "$file" ]; then
    printf '[Settings]\ngtk-icon-theme-name=%s\n' "$theme" > "$file"
    return 0
  fi
  tmp=$(mktemp "${file}.XXXXXX") || return 1
  if grep -q '^\[Settings\]' "$file"; then
    awk -v t="$theme" '
      /^\[Settings\]/ { print; if (!done) { print "gtk-icon-theme-name=" t; done = 1 } ; next }
      /^gtk-icon-theme-name=/ { if (!done) { print "gtk-icon-theme-name=" t; done = 1 } ; next }
      { print }
      END { if (!done) print "gtk-icon-theme-name=" t }
    ' "$file" > "$tmp"
  else
    { printf '[Settings]\ngtk-icon-theme-name=%s\n' "$theme"; cat "$file"; } > "$tmp"
  fi
  mv "$tmp" "$file"
}

# [Icons] Theme= in kdeglobals, when KDE applications are configured here.
write_kde() {
  local file=$HOME/.config/kdeglobals theme=$1 tmp
  [ -f "$file" ] || return 0
  tmp=$(mktemp "${file}.XXXXXX") || return 1
  awk -v t="$theme" '
    /^\[Icons\]/ { print; if (!done) { print "Theme=" t; done = 1 } ; next }
    /^Theme=/ { next }
    { print }
    END { if (!done) print "[Icons]\nTheme=" t }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# icon_theme= in a qt5ct/qt6ct config, when one is in use.
write_qtct() {
  local file=$1 theme=$2 tmp
  [ -f "$file" ] || return 0
  tmp=$(mktemp "${file}.XXXXXX") || return 1
  if grep -q '^icon_theme=' "$file"; then
    sed "s|^icon_theme=.*|icon_theme=$theme|" "$file" > "$tmp" && mv "$tmp" "$file"
  else
    { cat "$file"; printf 'icon_theme=%s\n' "$theme"; } > "$tmp" && mv "$tmp" "$file"
  fi
}

apply_theme() {
  local theme=$1 staged="$HOME/.local/state/omarchy/current/theme/icons.theme"

  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface icon-theme "$theme" >/dev/null 2>&1 || true
  fi
  write_gtk_settings "$HOME/.config/gtk-3.0/settings.ini" "$theme"
  write_gtk_settings "$HOME/.config/gtk-4.0/settings.ini" "$theme"
  mkdir -p "$HOME/.icons/default" && printf '[Icon Theme]\nInherits=%s\n' "$theme" > "$HOME/.icons/default/index.theme"
  [ -d "$(dirname "$staged")" ] && printf '%s\n' "$theme" > "$staged"
  write_kde "$theme"
  write_qtct "$HOME/.config/qt5ct/qt5ct.conf" "$theme"
  write_qtct "$HOME/.config/qt6ct/qt6ct.conf" "$theme"
  printf '%s\n' "$theme"
}

# The one theme the dock offers to fetch for you: WhiteSur, a macOS Big Sur
# look. Pinned to the release verified in 2026-10 so the download is
# reproducible; bump the tag when a newer release has been checked. The
# installer runs against a staging directory under ~/.local/share, outside the
# icon roots, so `list` never sees a partial theme.
WHITESUR_REPO=https://github.com/vinceliuice/WhiteSur-icon-theme.git
WHITESUR_TAG=2026-09-10
WHITESUR_STAGE=""
WHITESUR_BACKUP=""

cleanup_whitesur() {
  [ -n "$WHITESUR_STAGE" ] && rm -rf "$WHITESUR_STAGE"
  [ -n "$WHITESUR_BACKUP" ] && rm -rf "$WHITESUR_BACKUP"
  WHITESUR_STAGE=""
  WHITESUR_BACKUP=""
}

# Put any displaced incomplete theme directories back after a failed move.
restore_whitesur_backup() {
  local dest=$1 old name
  [ -n "$WHITESUR_BACKUP" ] || return 0
  for old in "$WHITESUR_BACKUP"/*; do
    [ -e "$old" ] || continue
    name=$(basename "$old")
    rm -rf "$dest/$name"
    mv "$old" "$dest/$name" 2>/dev/null || true
  done
}

install_whitesur() {
  command -v git >/dev/null 2>&1 || { echo "icon-theme: git is not installed" >&2; return 3; }

  local dest="$HOME/.local/share/icons" stage backup name dir rc
  # A complete WhiteSur already on disk is still installed; apply it without
  # touching the network or duplicating directories. This makes a second click
  # idempotent even if the UI entry reappears.
  if [ -n "$(theme_path WhiteSur)" ]; then
    apply_theme WhiteSur
    return $?
  fi

  mkdir -p "$HOME/.local/share" "$dest" || return 1
  stage=$(mktemp -d "$HOME/.local/share/.omadock-whitesur.XXXXXX") || return 1
  WHITESUR_STAGE=$stage
  WHITESUR_BACKUP=""
  trap cleanup_whitesur EXIT INT TERM HUP

  # GIT_TERMINAL_PROMPT=0 stops a private/redirected URL from waiting for
  # credentials; `timeout` bounds a hotel-wifi connection that never answers.
  # Git's own stderr (a proxy URL, a resolved host, a certificate subject) is
  # noise for the settings row, so it goes to the stage's log and only one
  # honest sentence reaches stderr. The stage, log and all go with the trap.
  if command -v timeout >/dev/null 2>&1; then
    # --foreground keeps the clone in this script's process group, so a
    # terminal's Ctrl-C (or a shell shutdown killing the group) reaches git too;
    # without it timeout starts a new group, the signal misses the clone and the
    # trap waits for a download nobody is watching.
    GIT_TERMINAL_PROMPT=0 timeout --foreground "${OMADOCK_ICON_TIMEOUT:-120}" git clone --quiet --depth 1 --branch "$WHITESUR_TAG" "$WHITESUR_REPO" "$stage/src" >"$stage/clone.log" 2>&1
  else
    GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 --branch "$WHITESUR_TAG" "$WHITESUR_REPO" "$stage/src" >"$stage/clone.log" 2>&1
  fi
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "icon-theme: could not download WhiteSur; check your connection and try again" >&2
    return 4
  fi

  # No -t flag: upstream's default variant is the blue macOS set, and its
  # --theme list accepts only colour names, not "blue". Everything it writes
  # goes to the stage, not to the icon roots.
  mkdir -p "$stage/icons" || return 1
  ( cd "$stage/src" && bash ./install.sh -d "$stage/icons" >"$stage/install.log" 2>&1 )
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "icon-theme: the WhiteSur installer failed; nothing was changed" >&2
    return 5
  fi
  if ! theme_complete "$stage/icons/WhiteSur"; then
    echo "icon-theme: the WhiteSur installer finished without a complete theme; nothing was changed" >&2
    return 5
  fi

  backup=$(mktemp -d "$HOME/.local/share/.omadock-backup.XXXXXX") || return 1
  WHITESUR_BACKUP=$backup
  # Move only complete staged directories. Existing complete variants win;
  # an incomplete copy (from an older interrupted run) is displaced and
  # restored if the move fails. Each moved directory is complete on its own,
  # so even a kill between moves cannot expose a half-populated theme.
  for dir in "$stage/icons"/*; do
    [ -d "$dir" ] || continue
    [ -f "$dir/index.theme" ] || continue
    name=$(basename "$dir")
    valid_id "$name" || continue
    theme_complete "$dir" || continue
    if [ -e "$dest/$name" ]; then
      theme_complete "$dest/$name" && continue
      if ! mv "$dest/$name" "$backup/$name"; then
        echo "icon-theme: could not replace $name" >&2
        restore_whitesur_backup "$dest"
        return 1
      fi
    fi
    if ! mv "$dir" "$dest/$name"; then
      echo "icon-theme: could not install $name" >&2
      restore_whitesur_backup "$dest"
      return 1
    fi
  done

  apply_theme WhiteSur
}

case "${1:-}" in
  list) list_themes ;;
  install) install_whitesur ;;
  apply)
    theme=${2:-}
    # A theme id is a directory name: anything else is refused before it can
    # reach a file path or a gsettings value.
    if ! valid_id "$theme"; then
      echo "icon-theme: invalid theme id" >&2
      exit 2
    fi
    if [ -z "$(theme_path "$theme")" ]; then
      echo "icon-theme: theme is not installed: $theme" >&2
      exit 6
    fi
    apply_theme "$theme"
    ;;
  *)
    echo "usage: icon-theme.sh list | icon-theme.sh install | icon-theme.sh apply <theme-id>" >&2
    exit 2
    ;;
esac
