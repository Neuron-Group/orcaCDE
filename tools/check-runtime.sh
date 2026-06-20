#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nscde-wayland-runtime-check.XXXXXX")

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
KEYBIND_FILE="$WORK_DIR/labwc-keybinds.xml"
STATE_DIR="$WORK_DIR/state"
DAEMON_LOG="$WORK_DIR/runtime-daemon.log"
DAEMON_PID=""

cleanup() {
   if [ -n "$DAEMON_PID" ]; then
      kill "$DAEMON_PID" 2>/dev/null || true
      wait "$DAEMON_PID" 2>/dev/null || true
   fi
   rm -rf "$WORK_DIR"
}

trap cleanup EXIT HUP INT TERM

"$RUNTIME_BIN" panel-layout publish "$NSCDE_STATIC_PANEL_LAYOUT_FILE" > "$PANEL_LAYOUT_FILE"

HOME="$WORK_DIR/home" \
NSCDE_DATADIR="$ROOT_DIR/assets" \
FVWM_USERDIR="$WORK_DIR/home/.NsCDE" \
NSCDE_TOOLSDIR="$ROOT_DIR/legacy-shims" \
NSCDE_LABWC_WORKSPACES="Alpha,Beta" \
NSCDE_LABWC_TERMINAL="xterm" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" labwc-menu publish "$CONFIG_DIR"

HOME="$WORK_DIR/home" \
NSCDE_DATADIR="$ROOT_DIR/assets" \
FVWM_USERDIR="$WORK_DIR/home/.NsCDE" \
NSCDE_TOOLSDIR="$ROOT_DIR/legacy-shims" \
NSCDE_LABWC_TERMINAL="xterm" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" labwc-keybinds publish > "$KEYBIND_FILE"

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
NSCDE_STATE_DIR="$STATE_DIR" \
NSCDE_STATIC_PANEL_LAYOUT_FILE="$NSCDE_STATIC_PANEL_LAYOUT_FILE" \
NSCDE_STATIC_SESSION_ENV_FILE="$NSCDE_STATIC_SESSION_ENV_FILE" \
"$RUNTIME_BIN" labwc-session publish "$CONFIG_DIR"

HOME="$WORK_DIR/home" \
NSCDE_THEME_NAME="NsCDE-Stage1" \
NSCDE_LABWC_WORKSPACES="Alpha,Beta" \
NSCDE_LABWC_CURRENT_WORKSPACE="Alpha" \
NSCDE_LABWC_TITLE_FONT_NAME="DejaVu Sans" \
NSCDE_LABWC_TITLE_FONT_SIZE="10" \
NSCDE_LABWC_KEYBIND_XML_FILE="$KEYBIND_FILE" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" labwc-rc publish "$CONFIG_DIR"

HOME="$WORK_DIR/home" \
NSCDE_ROOT="$ROOT_DIR" \
NSCDE_TOOLSDIR="$ROOT_DIR/legacy-shims" \
NSCDE_DATADIR="$ROOT_DIR/assets" \
NSCDE_THEME_NAME="NsCDE-Stage1" \
NSCDE_LABWC_WORKSPACES="Alpha,Beta" \
NSCDE_LABWC_CURRENT_WORKSPACE="Alpha" \
NSCDE_RUNTIME_BIN="$RUNTIME_BIN" \
NSCDE_STATE_DIR="$STATE_DIR" \
NSCDE_STATIC_PANEL_LAYOUT_FILE="$NSCDE_STATIC_PANEL_LAYOUT_FILE" \
"$RUNTIME_BIN" daemon >"$DAEMON_LOG" 2>&1 &
DAEMON_PID=$!

SOCKET_FILE="$STATE_DIR/runtime.sock"
attempt=0
while [ ! -S "$SOCKET_FILE" ]; do
   attempt=$((attempt + 1))
   if [ "$attempt" -ge 50 ]; then
      echo "runtime-check: daemon socket not ready" >&2
      cat "$DAEMON_LOG" >&2 || true
      exit 1
   fi
   sleep 0.1
done

QUERY_FILE="$WORK_DIR/query-workspaces.env"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query workspaces > "$QUERY_FILE"

grep -q '^NSCDE_CURRENT_WORKSPACE=Alpha$' "$QUERY_FILE"
grep -q '^NSCDE_WORKSPACE_COUNT=2$' "$QUERY_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl workspace-switch Beta

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query workspaces > "$QUERY_FILE"

grep -q '^NSCDE_CURRENT_WORKSPACE=Beta$' "$QUERY_FILE"

CAPS_FILE="$WORK_DIR/query-capabilities.env"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query capabilities > "$CAPS_FILE"

grep -q '^NSCDE_PANEL_LAYOUT_SOURCE=haskell-runtime$' "$PANEL_LAYOUT_FILE"
grep -q '^NSCDE_PANEL_PROFILE=reference$' "$PANEL_LAYOUT_FILE"
grep -q '^NSCDE_LABWC_WORKSPACES=Alpha,Beta$' "$CONFIG_DIR/environment"
grep -q '<keyboard>' "$KEYBIND_FILE"
grep -q 'W-Return' "$KEYBIND_FILE"
grep -q 'nscde-runtime.*daemon' "$CONFIG_DIR/autostart"
grep -q '<item label="Style Manager">' "$CONFIG_DIR/menu.xml"
grep -q '<item label="Workspace Alpha">' "$CONFIG_DIR/menu.xml"
grep -q '<command>xterm</command>' "$CONFIG_DIR/menu.xml"
grep -q '<number>2</number>' "$CONFIG_DIR/rc.xml"
grep -q '<name>Alpha</name>' "$CONFIG_DIR/rc.xml"
grep -q '<name>Beta</name>' "$CONFIG_DIR/rc.xml"
grep -q '<keyboard>' "$CONFIG_DIR/rc.xml"
grep -q '^supports-live-theme-reload=1$' "$CAPS_FILE"
test -s "$STATE_DIR/session.env"
test -s "$STATE_DIR/panel.env"
test -s "$STATE_DIR/workspaces.env"

printf '%s\n' "runtime-check: ok"
printf '%s\n' "panel-layout=$PANEL_LAYOUT_FILE"
printf '%s\n' "keybinds=$KEYBIND_FILE"
printf '%s\n' "config-dir=$CONFIG_DIR"
printf '%s\n' "state-dir=$STATE_DIR"
