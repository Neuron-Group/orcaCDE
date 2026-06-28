#!/bin/sh
set -eu

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nscde-wayland-launcher-check.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

LAUNCHER_BIN=${NSCDE_LAUNCHER_BIN:-nscde_labwc}

if ! command -v "$LAUNCHER_BIN" >/dev/null 2>&1; then
   echo "Missing launcher binary: $LAUNCHER_BIN" >&2
   exit 1
fi

LAUNCHER_PATH=$(command -v "$LAUNCHER_BIN")
LAUNCHER_ROOT=$(CDPATH= cd -- "$(dirname -- "$LAUNCHER_PATH")/.." && pwd)

HOME_DIR="$WORK_DIR/home"
CONFIG_DIR="$WORK_DIR/config"
CACHE_DIR="$WORK_DIR/cache"
DATA_DIR="$WORK_DIR/data"

mkdir -p "$HOME_DIR" "$CONFIG_DIR" "$CACHE_DIR" "$DATA_DIR"

HOME="$HOME_DIR" \
XDG_CONFIG_HOME="$CONFIG_DIR" \
XDG_CACHE_HOME="$CACHE_DIR" \
XDG_DATA_HOME="$DATA_DIR" \
NSCDE_LABWC_PREPARE_ONLY=1 \
NSCDE_LABWC_AUTOSTART_TERMINAL=0 \
"$LAUNCHER_BIN"

LABWC_CONFIG_DIR="$CONFIG_DIR/labwc-nscde"
STATE_DIR="$CACHE_DIR/nscde-stage1"
THEME_FILE="$DATA_DIR/themes/NsCDE-Stage1/labwc/themerc"
THEME_MENU_ACTIVE_FILE="$DATA_DIR/themes/NsCDE-Stage1/labwc/menu-active.xpm"
THEME_CLOSE_2X_FILE="$DATA_DIR/themes/NsCDE-Stage1/labwc/2x/close.xbm"

test -s "$LABWC_CONFIG_DIR/rc.xml"
test -s "$LABWC_CONFIG_DIR/menu.xml"
test -s "$LABWC_CONFIG_DIR/autostart"
test -s "$LABWC_CONFIG_DIR/environment"
test -s "$LABWC_CONFIG_DIR/shutdown"
test -s "$STATE_DIR/panel-layout.env"
test -s "$THEME_FILE"
test -s "$THEME_MENU_ACTIVE_FILE"
test -s "$THEME_CLOSE_2X_FILE"

grep -q 'nscde_labwc_paneld' "$LABWC_CONFIG_DIR/autostart"
grep -q 'nscde_backdropd' "$LABWC_CONFIG_DIR/autostart"
! grep -q 'nscde_labwc_bg' "$LABWC_CONFIG_DIR/autostart"
grep -q 'nscde-runtime.*daemon' "$LABWC_CONFIG_DIR/autostart"
grep -q '<labwc_config>' "$LABWC_CONFIG_DIR/rc.xml"
grep -q 'Style Manager' "$LABWC_CONFIG_DIR/menu.xml"
grep -q '^NSCDE_PANEL_LAYOUT_SOURCE=haskell-runtime$' "$STATE_DIR/panel-layout.env"
test ! -e "$LAUNCHER_ROOT/libexec/nscde/tools/nscde_labwc_menugen"

printf '%s\n' "launcher-check: ok"
printf '%s\n' "labwc-config=$LABWC_CONFIG_DIR"
printf '%s\n' "state-dir=$STATE_DIR"
