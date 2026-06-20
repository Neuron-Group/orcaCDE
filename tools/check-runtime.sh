#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nscde-wayland-runtime-check.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

RUNTIME_BIN=${NSCDE_RUNTIME_BIN:-nscde-runtime}

if ! command -v "$RUNTIME_BIN" >/dev/null 2>&1; then
   echo "Missing runtime binary: $RUNTIME_BIN" >&2
   exit 1
fi

: "${NSCDE_STATIC_PANEL_LAYOUT_FILE:?Set NSCDE_STATIC_PANEL_LAYOUT_FILE or use nix run .#runtime-check}"
: "${NSCDE_STATIC_SESSION_ENV_FILE:?Set NSCDE_STATIC_SESSION_ENV_FILE or use nix run .#runtime-check}"

mkdir -p "$WORK_DIR/home"

PANEL_LAYOUT_FILE="$WORK_DIR/panel-layout.env"
CONFIG_DIR="$WORK_DIR/labwc"

"$RUNTIME_BIN" panel-layout publish "$NSCDE_STATIC_PANEL_LAYOUT_FILE" > "$PANEL_LAYOUT_FILE"

HOME="$WORK_DIR/home" \
NSCDE_DATADIR="$ROOT_DIR/assets" \
FVWM_USERDIR="$WORK_DIR/home/.NsCDE" \
NSCDE_TOOLSDIR="$ROOT_DIR/legacy-shims" \
NSCDE_LABWC_WORKSPACES="Alpha,Beta" \
NSCDE_LABWC_TERMINAL="xterm" \
"$RUNTIME_BIN" labwc-menu publish "$CONFIG_DIR"

HOME="$WORK_DIR/home" \
NSCDE_ROOT="$ROOT_DIR" \
NSCDE_TOOLSDIR="$ROOT_DIR/legacy-shims" \
NSCDE_DATADIR="$ROOT_DIR/assets" \
NSCDE_THEME_NAME="NsCDE-Stage1" \
NSCDE_LABWC_WORKSPACES="Alpha,Beta" \
NSCDE_LABWC_CURRENT_WORKSPACE="Alpha" \
NSCDE_LABWC_TITLE_FONT_NAME="DejaVu Sans" \
NSCDE_LABWC_TITLE_FONT_SIZE="10" \
NSCDE_RUNTIME_BIN="$RUNTIME_BIN" \
NSCDE_STATIC_PANEL_LAYOUT_FILE="$NSCDE_STATIC_PANEL_LAYOUT_FILE" \
NSCDE_STATIC_SESSION_ENV_FILE="$NSCDE_STATIC_SESSION_ENV_FILE" \
"$RUNTIME_BIN" labwc-session publish "$CONFIG_DIR"

HOME="$WORK_DIR/home" \
NSCDE_THEME_NAME="NsCDE-Stage1" \
NSCDE_LABWC_WORKSPACES="Alpha,Beta" \
NSCDE_LABWC_CURRENT_WORKSPACE="Alpha" \
NSCDE_LABWC_TITLE_FONT_NAME="DejaVu Sans" \
NSCDE_LABWC_TITLE_FONT_SIZE="10" \
"$RUNTIME_BIN" labwc-rc publish "$CONFIG_DIR"

grep -q '^NSCDE_PANEL_LAYOUT_SOURCE=haskell-runtime$' "$PANEL_LAYOUT_FILE"
grep -q '^NSCDE_PANEL_PROFILE=reference$' "$PANEL_LAYOUT_FILE"
grep -q '^NSCDE_LABWC_WORKSPACES=Alpha,Beta$' "$CONFIG_DIR/environment"
grep -q 'nscde_sessiond' "$CONFIG_DIR/autostart"
grep -q '<item label="Style Manager">' "$CONFIG_DIR/menu.xml"
grep -q '<item label="Workspace Alpha">' "$CONFIG_DIR/menu.xml"
grep -q '<command>xterm</command>' "$CONFIG_DIR/menu.xml"
grep -q '<number>2</number>' "$CONFIG_DIR/rc.xml"
grep -q '<name>Alpha</name>' "$CONFIG_DIR/rc.xml"
grep -q '<name>Beta</name>' "$CONFIG_DIR/rc.xml"

printf '%s\n' "runtime-check: ok"
printf '%s\n' "panel-layout=$PANEL_LAYOUT_FILE"
printf '%s\n' "config-dir=$CONFIG_DIR"
