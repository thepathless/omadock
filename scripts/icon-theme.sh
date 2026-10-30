#!/usr/bin/env bash
# Icon themes for the whole desktop.
#
#   icon-theme.sh list            one "id|Name|Inherits" line per installed theme
#   icon-theme.sh apply <id>      make <id> the desktop's icon theme
#   icon-theme.sh install         fetch and apply the WhiteSur (macOS) icons
#
# `list` reads the index.theme of every icon directory the freedesktop spec
# names. `apply` writes the same places the desktop reads: gsettings (GTK and,
# with QT_QPA_PLATFORMTHEME=gtk3, Qt), both GTK settings files, ~/.icons/default,
# the staged Omarchy theme, and KDE/Qt config files when they exist. Existing
# keys in those files are preserved; nothing outside $HOME is written and no
# privilege is requested.
#
# Usage from a QML panel: the theme id is passed as an argument, never spliced
# into a command line.

set -uo pipefail

theme_dirs() {
  printf '%s\n' "$HOME/.icons" "$HOME/.local/share/icons" /usr/share/icons
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
      case "$id" in hicolor|locolor|default|default-dark) continue ;; esac
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
# reproducible; bump the tag when a newer release has been checked. It
# installs into $HOME/.local/share/icons with upstream's own installer, so
# nothing outside $HOME is written and no privilege is asked for.
WHITESUR_REPO=https://github.com/vinceliuice/WhiteSur-icon-theme.git
WHITESUR_TAG=2026-09-10

install_whitesur() {
  command -v git >/dev/null 2>&1 || { echo "icon-theme: git is not installed" >&2; return 3; }
  local tmp rc
  tmp=$(mktemp -d) || return 1
  # Global on purpose: the EXIT trap runs after this function's locals are
  # gone, and quoting the path at trap time keeps a spacey TMPDIR safe.
  WHITESUR_TMP=$tmp
  trap 'rm -rf "$WHITESUR_TMP"' EXIT INT TERM HUP
  git clone --quiet --depth 1 --branch "$WHITESUR_TAG" "$WHITESUR_REPO" "$tmp" >&2 || {
    echo "icon-theme: could not download WhiteSur $WHITESUR_TAG" >&2
    return 4
  }
  # No -t flag: upstream's default variant is the blue macOS set, and its
  # --theme list accepts only colour names, not "blue".
  ( cd "$tmp" && bash ./install.sh -d "$HOME/.local/share/icons" >&2 )
  rc=$?
  [ "$rc" -eq 0 ] || { echo "icon-theme: WhiteSur installer failed ($rc)" >&2; return 5; }
  apply_theme WhiteSur
}

case "${1:-}" in
  list) list_themes ;;
  install) install_whitesur ;;
  apply)
    theme=${2:-}
    # A theme id is a directory name: anything else is refused before it can
    # reach a file path or a gsettings value.
    if ! [[ $theme =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
      echo "icon-theme: invalid theme id" >&2
      exit 2
    fi
    apply_theme "$theme"
    ;;
  *)
    echo "usage: icon-theme.sh list | icon-theme.sh apply <theme-id>" >&2
    exit 2
    ;;
esac
