#!/bin/sh
set -eu

ROOT_DIR=${NSCDE_RUNTIME_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nscde-wayland-runtime-check.XXXXXX")
TOOLS_DIR=${NSCDE_RUNTIME_TOOLSDIR:-"$ROOT_DIR/legacy-shims"}

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
STATE_DIR="$WORK_DIR/state"
THEME_DIR="$WORK_DIR/home/.local/share/themes/NsCDE-Stage1/labwc"
KEYBIND_FILE="$STATE_DIR/labwc-keybinds.xml"
STYLE_FILE="$STATE_DIR/style.env"
DAEMON_LOG="$WORK_DIR/runtime-daemon.log"
DAEMON_PID=""
FVWM_USERDIR="$WORK_DIR/home/.NsCDE"
GTK3_SETTINGS_DIR="$WORK_DIR/home/.config/gtk-3.0"
GTK3_SETTINGS_FILE="$GTK3_SETTINGS_DIR/settings.ini"
QT5CT_DIR="$WORK_DIR/home/.config/qt5ct"
QT5CT_FILE="$QT5CT_DIR/qt5ct.conf"
STYLE_MGR_INI="$FVWM_USERDIR/StyleMgr.ini"
XSETTINGSD_FILE="$FVWM_USERDIR/Xsettingsd.conf"
XDEFAULTS_FONTDEFS="$FVWM_USERDIR/Xdefaults.fontdefs"
FONTSET_NAME="DejaVuSerif"
FONT_VARIABLE_NORMAL_MEDIUM='xft:DejaVu Serif:Medium:Book:size=11'
FONT_MONOSPACED_NORMAL_MEDIUM='xft:DejaVu Sans Mono:Medium:Book:size=12'
BACKER_DIR="$FVWM_USERDIR/backer"
BACKDROP_NAME="RuntimeCheckBackdrop"
BACKDROP_FILE="$BACKER_DIR/Desk1-$BACKDROP_NAME.pm"
BG_HELPER_ENV="$STATE_DIR/bg-helper.env"

cleanup() {
   if [ -n "$DAEMON_PID" ]; then
      kill "$DAEMON_PID" 2>/dev/null || true
      wait "$DAEMON_PID" 2>/dev/null || true
   fi
   rm -rf "$WORK_DIR"
}

trap cleanup EXIT HUP INT TERM

CHECK_TOOLS_DIR="$WORK_DIR/tools"
mkdir -p "$CHECK_TOOLS_DIR"
mkdir -p "$STATE_DIR"
for tool_path in "$TOOLS_DIR"/*; do
   ln -s "$tool_path" "$CHECK_TOOLS_DIR/$(basename "$tool_path")"
done
rm -f "$CHECK_TOOLS_DIR/nscde_labwc_bg"
cat > "$CHECK_TOOLS_DIR/nscde_labwc_bg" <<EOF
#!/bin/sh
cat > "$BG_HELPER_ENV" <<BGEOF
NSCDE_PALETTE_FILE=\${NSCDE_PALETTE_FILE:-}
NSCDE_BACKDROP_IMAGE=\${NSCDE_BACKDROP_IMAGE:-}
NSCDE_BACKDROP_MODE=\${NSCDE_BACKDROP_MODE:-}
BGEOF
EOF
chmod +x "$CHECK_TOOLS_DIR/nscde_labwc_bg"
TOOLS_DIR="$CHECK_TOOLS_DIR"

"$RUNTIME_BIN" panel-layout publish "$NSCDE_STATIC_PANEL_LAYOUT_FILE" > "$PANEL_LAYOUT_FILE"

HOME="$WORK_DIR/home" \
NSCDE_DATADIR="$ROOT_DIR/assets" \
FVWM_USERDIR="$FVWM_USERDIR" \
NSCDE_TOOLSDIR="$TOOLS_DIR" \
NSCDE_LABWC_WORKSPACES="Alpha,Beta" \
NSCDE_LABWC_TERMINAL="xterm" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" labwc-menu publish "$CONFIG_DIR"

HOME="$WORK_DIR/home" \
NSCDE_DATADIR="$ROOT_DIR/assets" \
FVWM_USERDIR="$FVWM_USERDIR" \
NSCDE_TOOLSDIR="$TOOLS_DIR" \
NSCDE_LABWC_TERMINAL="xterm" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" labwc-keybinds publish > "$KEYBIND_FILE"

HOME="$WORK_DIR/home" \
NSCDE_DATADIR="$ROOT_DIR/assets" \
NSCDE_THEME_NAME="NsCDE-Stage1" \
NSCDE_PALETTE_FILE="$ROOT_DIR/assets/palettes/Charcoal.dp" \
"$RUNTIME_BIN" labwc-theme publish > /dev/null

HOME="$WORK_DIR/home" \
NSCDE_ROOT="$ROOT_DIR" \
NSCDE_TOOLSDIR="$TOOLS_DIR" \
NSCDE_DATADIR="$ROOT_DIR/assets" \
NSCDE_THEME_NAME="NsCDE-Stage1" \
NSCDE_LABWC_WORKSPACES="Alpha,Beta" \
NSCDE_LABWC_CURRENT_WORKSPACE="Alpha" \
NSCDE_LABWC_CONFIG_DIR="$CONFIG_DIR" \
NSCDE_LABWC_TITLE_FONT_NAME="DejaVu Sans" \
NSCDE_LABWC_TITLE_FONT_SIZE="10" \
NSCDE_RUNTIME_BIN="$RUNTIME_BIN" \
NSCDE_STATE_DIR="$STATE_DIR" \
NSCDE_STATIC_PANEL_LAYOUT_FILE="$NSCDE_STATIC_PANEL_LAYOUT_FILE" \
NSCDE_STATIC_SESSION_ENV_FILE="$NSCDE_STATIC_SESSION_ENV_FILE" \
"$RUNTIME_BIN" labwc-session publish "$CONFIG_DIR"

mkdir -p "$STATE_DIR" "$FVWM_USERDIR" "$GTK3_SETTINGS_DIR" "$QT5CT_DIR"
mkdir -p "$BACKER_DIR"
printf '%s\n' 'runtime-check-backdrop' > "$BACKDROP_FILE"

cat > "$STYLE_MGR_INI" <<EOF
[FontMgr]
integrate_gtk3=1
integrate_qt5=1
integrate_xresources=1
EOF

cat > "$GTK3_SETTINGS_FILE" <<EOF
[Settings]
gtk-font-name=Old Font 10
EOF

cat > "$QT5CT_FILE" <<EOF
[Fonts]
general="Old Font,10"
fixed="Old Mono,10"
EOF

cat > "$XSETTINGSD_FILE" <<EOF
Gtk/FontName "Old Font 10"
EOF

HOME="$WORK_DIR/home" \
NSCDE_THEME_NAME="NsCDE-Stage1" \
NSCDE_LABWC_WORKSPACES="Alpha,Beta" \
NSCDE_LABWC_CURRENT_WORKSPACE="Alpha" \
NSCDE_LABWC_CONFIG_DIR="$CONFIG_DIR" \
NSCDE_LABWC_TITLE_FONT_NAME="DejaVu Sans" \
NSCDE_LABWC_TITLE_FONT_SIZE="10" \
NSCDE_LABWC_KEYBIND_XML_FILE="$KEYBIND_FILE" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" labwc-rc publish "$CONFIG_DIR"

cat > "$STYLE_FILE" <<EOF
NSCDE_FP_VARIANT=5
NSCDE_PALETTE_PATH=$ROOT_DIR/assets/palettes/Charcoal.dp
EOF

HOME="$WORK_DIR/home" \
NSCDE_ROOT="$ROOT_DIR" \
NSCDE_TOOLSDIR="$TOOLS_DIR" \
NSCDE_DATADIR="$ROOT_DIR/assets" \
NSCDE_THEME_NAME="NsCDE-Stage1" \
NSCDE_LABWC_CONFIG_DIR="$CONFIG_DIR" \
NSCDE_LABWC_WORKSPACES="Alpha,Beta" \
NSCDE_LABWC_CURRENT_WORKSPACE="Alpha" \
NSCDE_LABWC_KEYBIND_XML_FILE="$KEYBIND_FILE" \
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
PANEL_QUERY_FILE="$WORK_DIR/query-panel.env"
PANEL_STYLE_APPLY_FILE="$WORK_DIR/query-panel-after-style-apply.env"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query workspaces > "$QUERY_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query panel > "$PANEL_QUERY_FILE"

grep -q '^NSCDE_CURRENT_WORKSPACE=Alpha$' "$QUERY_FILE"
grep -q '^NSCDE_WORKSPACE_COUNT=2$' "$QUERY_FILE"
grep -q '^NSCDE_PALETTE_1=#' "$PANEL_QUERY_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl workspace-switch Beta

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query workspaces > "$QUERY_FILE"

grep -q '^NSCDE_CURRENT_WORKSPACE=Beta$' "$QUERY_FILE"

CAPS_FILE="$WORK_DIR/query-capabilities.env"
STYLE_QUERY_FILE="$WORK_DIR/query-style.env"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query capabilities > "$CAPS_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query style > "$STYLE_QUERY_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl style-set NSCDE_FOCUS_POLICY SloppyFocus

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl style-set NSCDE_AUTO_RAISE 1

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl style-set NSCDE_RAISE_DELAY 250

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl style-set NSCDE_FONTSET_NAME "$FONTSET_NAME"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl style-set NSCDE_FONT_VARIABLE_NORMAL_MEDIUM "$FONT_VARIABLE_NORMAL_MEDIUM"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl style-set NSCDE_FONT_MONOSPACED_NORMAL_MEDIUM "$FONT_MONOSPACED_NORMAL_MEDIUM"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl style-set NSCDE_BACKDROP_DESK_1_MODE tiled

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl style-set NSCDE_BACKDROP_DESK_1_IMAGE "$BACKDROP_NAME"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl style-apply

attempt=0
while [ ! -s "$BG_HELPER_ENV" ]; do
   attempt=$((attempt + 1))
   if [ "$attempt" -ge 50 ]; then
      echo "runtime-check: bg helper env not ready" >&2
      if [ -e "$BG_HELPER_ENV" ]; then
         cat "$BG_HELPER_ENV" >&2 || true
      fi
      cat "$DAEMON_LOG" >&2 || true
      exit 1
   fi
   sleep 0.1
done

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query style > "$STYLE_QUERY_FILE"

grep -v '^NSCDE_FP_VARIANT=' "$STYLE_FILE" | \
grep -v '^NSCDE_PALETTE_PATH=' > "$STYLE_FILE.tmp"
printf '%s\n' "NSCDE_FP_VARIANT=8" >> "$STYLE_FILE.tmp"
printf '%s\n' "NSCDE_PALETTE_PATH=$ROOT_DIR/assets/palettes/Charcoal.dp" >> "$STYLE_FILE.tmp"
mv "$STYLE_FILE.tmp" "$STYLE_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl style-apply

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query panel > "$PANEL_STYLE_APPLY_FILE"

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
grep -q '<followMouse>yes</followMouse>' "$CONFIG_DIR/rc.xml"
grep -q '<followMouseRequiresMovement>no</followMouseRequiresMovement>' "$CONFIG_DIR/rc.xml"
grep -q '<raiseOnFocus>yes</raiseOnFocus>' "$CONFIG_DIR/rc.xml"
grep -q '<raiseOnFocusDelay>250</raiseOnFocusDelay>' "$CONFIG_DIR/rc.xml"
grep -q '^supports-live-theme-reload=1$' "$CAPS_FILE"
grep -q '^NSCDE_FP_VARIANT=5$' "$STYLE_QUERY_FILE"
grep -q "^NSCDE_PALETTE_PATH=$ROOT_DIR/assets/palettes/Charcoal.dp\$" "$STYLE_QUERY_FILE"
grep -q '^NSCDE_FOCUS_POLICY=SloppyFocus$' "$STYLE_QUERY_FILE"
grep -q '^NSCDE_AUTO_RAISE=1$' "$STYLE_QUERY_FILE"
grep -q '^NSCDE_RAISE_DELAY=250$' "$STYLE_QUERY_FILE"
grep -q "^NSCDE_FONTSET_NAME=$FONTSET_NAME\$" "$STYLE_QUERY_FILE"
grep -q '^NSCDE_FP_VARIANT=8$' "$PANEL_STYLE_APPLY_FILE"
grep -q '^NSCDE_PALETTE_1=#' "$PANEL_STYLE_APPLY_FILE"
grep -Eq '^gtk-font-name *= *"?DejaVu Serif Book 11"?$' "$GTK3_SETTINGS_FILE"
grep -Eq '^general *= *"DejaVu Serif,11"$' "$QT5CT_FILE"
grep -Eq '^fixed *= *"DejaVu Sans Mono,12"$' "$QT5CT_FILE"
grep -Eq '^Gtk/FontName "DejaVu Serif Book 11"$' "$XSETTINGSD_FILE"
grep -q 'FONT_VARIABLE_NORMAL_MEDIUM_NAME DejaVu Serif' "$XDEFAULTS_FONTDEFS"
grep -q 'FONT_MONOSPACED_NORMAL_MEDIUM_NAME DejaVu Sans Mono' "$XDEFAULTS_FONTDEFS"
grep -q "^NSCDE_PALETTE_FILE=$ROOT_DIR/assets/palettes/Charcoal.dp\$" "$BG_HELPER_ENV"
grep -q "^NSCDE_BACKDROP_IMAGE=$BACKDROP_FILE\$" "$BG_HELPER_ENV"
grep -q '^NSCDE_BACKDROP_MODE=tiled$' "$BG_HELPER_ENV"
test -s "$STATE_DIR/session.env"
test -s "$STATE_DIR/panel.env"
test -s "$STATE_DIR/workspaces.env"
test -s "$THEME_DIR/themerc"
test -s "$THEME_DIR/menu-active.xpm"
test -s "$THEME_DIR/2x/close.xbm"
grep -q '^window.active.title.bg.color: #' "$THEME_DIR/themerc"

printf '%s\n' "runtime-check: ok"
printf '%s\n' "panel-layout=$PANEL_LAYOUT_FILE"
printf '%s\n' "keybinds=$KEYBIND_FILE"
printf '%s\n' "config-dir=$CONFIG_DIR"
printf '%s\n' "state-dir=$STATE_DIR"
