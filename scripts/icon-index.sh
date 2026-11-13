#!/usr/bin/env bash
# The icon index the dock resolves names through: one "name -> absolute path"
# line per artwork name, theme-first and size-first.
#
#   icon-index.sh <theme-id> [<inherited-theme> ...]
#
# The first argument is the desktop's active icon theme and the rest are the
# themes it inherits from, in lookup order (DockIconTheme.chain). Every theme in
# that chain is searched before any other theme, so an active theme's artwork
# is never replaced by a stranger's; inside a theme the largest artwork wins
# (scalable, then 256x256, 128, 96 ... 16), because `find` lists a theme's
# 16x16 folder first and that is how WhiteSur's dark 16px outline was drawn
# instead of its blue folder. Everything else on disk is the last resort
# (group 99), which keeps a theme that names an icon it does not ship
# resolvable.
#
# `mimetypes` and `mimes` are both indexed: WhiteSur keeps its file-type art
# under mimes/, while most themes use mimetypes/.
#
# Prints one path per line, in no particular order: the caller's parser keeps
# the first occurrence of each name.

set -uo pipefail

groups=()
g=0
for theme in "$@"; do
  groups+=("$g:$HOME/.icons/$theme" "$g:$HOME/.local/share/icons/$theme" \
           "$g:/usr/share/icons/$theme" "$g:/usr/local/share/icons/$theme")
  g=$((g + 1))
done
groups+=("99:$HOME/.icons" "99:$HOME/.local/share/icons")
IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
  groups+=("99:$d/icons")
done; unset IFS

{
  for entry in "${groups[@]}"; do
    group=${entry%%:*}
    base=${entry#*:}
    [ -d "$base" ] || continue
    for ext in svg png; do
      # -L: a theme can share another theme's artwork through a symlinked
      # size directory (WhiteSur-dark/apps/scalable -> ../../WhiteSur/apps/
      # scalable). find(1) does not follow it, so the active dark theme had no
      # scalable app icons, and every name it does not ship at 22/16px resolved
      # from the inherited hicolor/breeze art instead of the artwork it shares
      # (measured: foot and firefox fell to hicolor's generic files).
      find -L "$base" \( -path "*/apps/*" -o -path "*/devices/*" -o -path "*/places/*" \
        -o -path "*/mimetypes/*" -o -path "*/mimes/*" \) -name "*.$ext" 2>/dev/null \
        | while IFS= read -r file; do printf "%s\t%s\n" "$group" "$file"; done
    done
  done
  for ext in svg png; do
    find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null \
      | while IFS= read -r file; do printf "99\t%s\n" "$file"; done
  done
} | awk -F"\t" '
  {
    g = $1 + 0; p = $2
    n = p; sub(/.*\//, "", n); sub(/\.[^.]*$/, "", n)
    if (n == "") next
    rank = 0
    m = split(p, parts, "/")
    for (i = 1; i <= m; i++) {
      tok = parts[i]
      if (tok == "scalable") rank = 100000
      else if (tok == "symbolic") { if (rank < 1) rank = 1 }
      else if (tok ~ /^[0-9]+x[0-9]+/) {
        s = tok; sub(/x.*/, "", s); s = s + 0
        if (tok ~ /@[0-9]+x/) s = s * 2
        if (s > rank) rank = s
      } else if (tok ~ /^[0-9]+$/) {
        s = tok + 0
        if (s > rank) rank = s
      }
    }
    if (p ~ /\.svg$/) rank = rank + 0.5
    if (!(n in bestGroup) || g < bestGroup[n] || (g == bestGroup[n] && rank > bestRank[n])) {
      bestGroup[n] = g; bestRank[n] = rank; path[n] = p
    }
  }
  END { for (n in path) print path[n] }'
