#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE_DIR=${1:-"$ROOT_DIR/../NsCDE"}

if [ ! -d "$SOURCE_DIR" ]; then
   echo "Missing source NsCDE tree: $SOURCE_DIR" >&2
   exit 1
fi

clean_dir() {
   dir=$1
   rm -rf "$ROOT_DIR/$dir"
   mkdir -p "$ROOT_DIR/$dir"
}

sync_dir() {
   src=$1
   dest=$2
   clean_dir "$dest"
   cp -a "$SOURCE_DIR/$src/." "$ROOT_DIR/$dest/"
}

sync_file() {
   src=$1
   dest=$2
   mkdir -p "$(dirname "$ROOT_DIR/$dest")"
   cp -a "$SOURCE_DIR/$src" "$ROOT_DIR/$dest"
}

sync_sources_by_find() {
   src=$1
   dest=$2
   shift 2
   clean_dir "$dest"
   (
      cd "$SOURCE_DIR/$src"
      find . "$@" -type f -print
   ) | while IFS= read -r rel; do
      rel=${rel#./}
      mkdir -p "$ROOT_DIR/$dest/$(dirname "$rel")"
      cp -a "$SOURCE_DIR/$src/$rel" "$ROOT_DIR/$dest/$rel"
   done
}

sync_sources_by_find "haskell" "haskell" \( -name '*.hs' -o -name 'README.md' -o -name '*.cabal' \)
sync_sources_by_find "nix" "nix" \( -name '*.nix' -o -name 'README.md' \)
sync_sources_by_find "lib/python" "lib/python" \( -name '*.py' -o -name '*.py.in' -o -name 'README.md' \)

sync_sources_by_find "src/nscde_wayland_common" "src/nscde_wayland_common" \( -name '*.[ch]' -o -name 'README.md' -o -name 'Makefile.am' \)
sync_sources_by_find "src/nscde_common" "src/nscde_common" \( -name 'nscde-pixel-icon.[ch]' \)
sync_sources_by_find "src/nscde_paneld" "src/nscde_paneld" \( -name '*.[ch]' -o -name 'Makefile.am' \)
sync_sources_by_find "src/nscde_pagerd" "src/nscde_pagerd" \( -name '*.[ch]' -o -name 'Makefile.am' \)
sync_sources_by_find "src/nscde_toplevel" "src/nscde_toplevel" \( -name '*.[ch]' -o -name 'Makefile.am' \)

clean_dir "bin"
sync_file "bin/nscde_labwc.in" "bin/nscde_labwc.in"

clean_dir "legacy-shims"
for rel in \
   "nscde_tools/ised.in" \
   "nscde_tools/nscde_backend.shlib.in" \
   "nscde_tools/nscde_style_state.shlib.in" \
   "nscde_tools/nscde_sessiond.in" \
   "nscde_tools/nscde_stylemgr.in" \
   "nscde_tools/nscde_fontset_migrate.in" \
   "nscde_tools/nscde_asset_tiergen.in" \
   "nscde_tools/getfont.in" \
   "nscde_tools/fontmgr.in" \
   "nscde_tools/confget.in" \
   "nscde_tools/confset.in" \
   "nscde_tools/palette_colorgen.in" \
   "nscde_tools/themegen.in" \
   "nscde_tools/generate_app_menus.in" \
   "nscde_tools/generate_subpanels.in" \
   "nscde_tools/fpexec.in" \
   "nscde_tools/fpseticon.in" \
   "nscde_tools/subpanel_menuitem_props.in"
do
   sync_file "$rel" "legacy-shims/$(basename "$rel")"
done

for rel in "$SOURCE_DIR"/nscde_tools/nscde_labwc*.in; do
   sync_file "$(printf '%s' "${rel#$SOURCE_DIR/}")" "legacy-shims/$(basename "$rel")"
done

clean_dir "assets/palettes"
clean_dir "assets/fontsets"
clean_dir "assets/backdrops"
clean_dir "assets/photos"
clean_dir "assets/fvwm"
clean_dir "assets/icons/NsCDE"
clean_dir "assets/defaults"
sync_dir "data/palettes" "assets/palettes"
sync_dir "data/fontsets" "assets/fontsets"
sync_dir "data/backdrops" "assets/backdrops"
sync_dir "data/photos" "assets/photos"
sync_dir "data/icons/NsCDE" "assets/icons/NsCDE"

for rel in \
   "data/fvwm/Font-75dpi.fvwmconf" \
   "data/fvwm/Font-96dpi.fvwmconf" \
   "data/fvwm/Font-120dpi.fvwmconf" \
   "data/fvwm/Font-144dpi.fvwmconf" \
   "data/fvwm/Font-192dpi.fvwmconf" \
   "data/fvwm/Keybindings.cua" \
   "data/fvwm/Keybindings.nscde1x"
do
   sync_file "$rel" "assets/fvwm/$(basename "$rel")"
done

for rel in \
   "data/defaults/AppMenus.conf" \
   "data/defaults/FrontPanel.actions" \
   "data/defaults/Subpanels.actions" \
   "data/defaults/WSM.conf" \
   "data/defaults/Keymenu-cua.actions" \
   "data/defaults/Keymenu-nscde1x.actions"
do
   sync_file "$rel" "assets/defaults/$(basename "$rel")"
done

clean_dir "xdg/applications"
clean_dir "xdg/desktop-directories"
clean_dir "xdg/icons/NsCDE"
clean_dir "xdg/menus"
clean_dir "xdg/wayland-sessions"
sync_dir "xdg/applications" "xdg/applications"
sync_dir "xdg/desktop-directories" "xdg/desktop-directories"
sync_dir "xdg/icons/NsCDE" "xdg/icons/NsCDE"
sync_dir "xdg/menus" "xdg/menus"
sync_dir "xdg/wayland-sessions" "xdg/wayland-sessions"

echo "Synchronized standalone Wayland scaffold from $SOURCE_DIR"
