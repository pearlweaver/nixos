#!/usr/bin/env bash
# Apply the wallpaper's matugen palette to ChillPill and to GTK/Qt/KDE apps.
# @system_theme@ is SekaiPop's pinned script; it writes the shared GTK/Qt/KDE
# files while the second matugen run renders ChillPill's own JSON preset.
set -eu

cache="$HOME/.cache/chillpill-shell"
wallpaper="${1:-}"

if [ -z "$wallpaper" ] && [ -s "$cache/last_wallpaper" ]; then
  wallpaper="$(cat "$cache/last_wallpaper")"
fi

# On a fresh profile last_wallpaper may not exist yet; ask awww what it is
# showing so the first startup still gets a palette.
if [ -z "$wallpaper" ]; then
  wallpaper="$("@awww@" query 2>/dev/null | awk -F 'currently displaying: image: ' '/currently displaying: image: / { print $2; exit }')"
fi

if [ -z "$wallpaper" ] || [ ! -f "$wallpaper" ]; then
  echo "chillpill-matugen: no wallpaper to theme from" >&2
  exit 0
fi

# Keep the script's own cache separate from the SekaiPop profile's; it uses
# XDG_CACHE_HOME for stamps and intermediate files.
export XDG_CACHE_HOME="$HOME/.cache/chillpill-matugen"
export PATH="@path_value@:$PATH"
mkdir -p "$XDG_CACHE_HOME" "$cache/themes"

"@system_theme@" apply source=image value="$wallpaper" mode=dark \
  targets=gtk,qt,kde gtktheme=off scheme=off reload=qt,kde force=1

"@matugen@" image "$wallpaper" --config "@matugen_config@" \
  --mode dark --type scheme-tonal-spot --source-color-index 0 --quiet
