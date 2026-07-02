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
BACKDROPD_LOG="$WORK_DIR/backdropd.log"
BACKDROPD_PID=""
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
BACKDROP_SOURCE_DIR="$FVWM_USERDIR/backdrops"
BACKDROP_NAME="RuntimeCheckBackdrop"
BACKDROP_FILE="$BACKER_DIR/Desk1-$BACKDROP_NAME.png"
DEFAULT_BACKDROP_FILE="$BACKER_DIR/Desk1-Ankh.png"
BACKDROP_STATE_FILE="$STATE_DIR/backdrops.env"
BOGUS_BACKDROP_FILE="$WORK_DIR/bogus-backdrop.pm"
SWAYBG_LOG="$WORK_DIR/swaybg.log"
FAKE_SWAYBG="$WORK_DIR/fake-swaybg"
NO_RUNTIME_DIR="$WORK_DIR/no-runtime"

cleanup() {
   terminate_pid "$BACKDROPD_PID"
   terminate_pid "$DAEMON_PID"
   rm -rf "$WORK_DIR"
}

trap cleanup EXIT HUP INT TERM

terminate_pid() {
   _pid=${1:-}
   _attempt=0

   if [ -z "$_pid" ]; then
      return 0
   fi
   if ! kill -0 "$_pid" 2>/dev/null; then
      wait "$_pid" 2>/dev/null || true
      return 0
   fi

   kill "$_pid" 2>/dev/null || true
   while kill -0 "$_pid" 2>/dev/null; do
      _attempt=$((_attempt + 1))
      if [ "$_attempt" -ge 50 ]; then
         kill -KILL "$_pid" 2>/dev/null || true
         break
      fi
      sleep 0.1
   done
   wait "$_pid" 2>/dev/null || true
}

mkdir -p "$STATE_DIR"
mkdir -p "$NO_RUNTIME_DIR"
cat > "$FAKE_SWAYBG" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${SWAYBG_LOG:?}"
exec sleep 60
EOF
chmod +x "$FAKE_SWAYBG"

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
mkdir -p "$BACKER_DIR" "$BACKDROP_SOURCE_DIR"
cat > "$BACKDROP_SOURCE_DIR/$BACKDROP_NAME.pm" <<'EOF'
/* XPM */
static char * runtime_check_backdrop[] = {
"1 1 1 1",
"  c #123456",
" "
};
EOF

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

HOME="$WORK_DIR/home" \
NSCDE_TOOLSDIR="$TOOLS_DIR" \
NSCDE_STATE_DIR="$STATE_DIR" \
XDG_RUNTIME_DIR="$NO_RUNTIME_DIR" \
WAYLAND_DISPLAY="missing-wayland-display" \
SWAYBG_BIN="$FAKE_SWAYBG" \
SWAYBG_LOG="$SWAYBG_LOG" \
"$TOOLS_DIR/nscde_backdropd" >"$BACKDROPD_LOG" 2>&1 &
BACKDROPD_PID=$!

QUERY_FILE="$WORK_DIR/query-workspaces.env"
PANEL_QUERY_FILE="$WORK_DIR/query-panel.env"
PANEL_STYLE_APPLY_FILE="$WORK_DIR/query-panel-after-style-apply.env"
BACKDROP_QUERY_FILE="$WORK_DIR/query-backdrops.env"
SESSION_QUERY_FILE="$WORK_DIR/query-session.env"
STYLE_QUERY_FILE="$WORK_DIR/query-style.env"
PY_STYLE_QUERY_FILE="$WORK_DIR/python-query-style.txt"
CAPS_FILE="$WORK_DIR/query-capabilities.env"
TASKD_QUERY_FILE="$WORK_DIR/query-taskd.env"
SUBSCRIBE_FILE="$WORK_DIR/subscribe-workspaces.env"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query workspaces > "$QUERY_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query panel > "$PANEL_QUERY_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query backdrops > "$BACKDROP_QUERY_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query taskd > "$TASKD_QUERY_FILE"

STYLE_FILE_SAVED="$WORK_DIR/style.saved.env"
mv "$STYLE_FILE" "$STYLE_FILE_SAVED"
HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
python - <<'EOF' > "$PY_STYLE_QUERY_FILE"
import os
root_dir = os.environ["NSCDE_RUNTIME_ROOT"]
path = os.path.join(root_dir, "legacy-shims", "nscde_runtime_client.py.in")
ns = {"__name__": "runtime_client_test", "__file__": path}
with open(path, "r", encoding="utf-8") as handle:
   code = compile(handle.read(), path, "exec")
exec(code, ns)
print(ns["style_state"]())
EOF
mv "$STYLE_FILE_SAVED" "$STYLE_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" subscribe workspaces > "$SUBSCRIBE_FILE" &
SUBSCRIBE_PID=$!

attempt=0
while ! grep -q '^NSCDE_CURRENT_WORKSPACE=Alpha$' "$SUBSCRIBE_FILE" 2>/dev/null; do
   attempt=$((attempt + 1))
   if [ "$attempt" -ge 50 ]; then
      echo "runtime-check: subscribe did not emit initial workspace state" >&2
      cat "$DAEMON_LOG" >&2 || true
      kill "$SUBSCRIBE_PID" 2>/dev/null || true
      wait "$SUBSCRIBE_PID" 2>/dev/null || true
      exit 1
   fi
   sleep 0.1
done

kill "$SUBSCRIBE_PID" 2>/dev/null || true
wait "$SUBSCRIBE_PID" 2>/dev/null || true

grep -q '^NSCDE_CURRENT_WORKSPACE=Alpha$' "$QUERY_FILE"
grep -q '^NSCDE_WORKSPACE_COUNT=2$' "$QUERY_FILE"
grep -q '^NSCDE_PALETTE_1=#' "$PANEL_QUERY_FILE"
grep -q '^NSCDE_BACKDROP_WORKSPACE=Alpha$' "$BACKDROP_QUERY_FILE"
grep -q '^NSCDE_BACKDROP_DESK=1$' "$BACKDROP_QUERY_FILE"
grep -q '^NSCDE_BACKDROP_IMAGE_NAME=Ankh$' "$BACKDROP_QUERY_FILE"
grep -q "^NSCDE_BACKDROP_IMAGE=$DEFAULT_BACKDROP_FILE\$" "$BACKDROP_QUERY_FILE"
grep -q '^NSCDE_BACKDROP_MODE=tiled$' "$BACKDROP_QUERY_FILE"
grep -q '^NSCDE_TASK_COUNT=0$' "$TASKD_QUERY_FILE"
grep -q '^NSCDE_TASK_FOCUSED=$' "$TASKD_QUERY_FILE"
grep -q '^NSCDE_TASK_COMMAND_FIFO='"$STATE_DIR"'/topleveld.fifo$' "$TASKD_QUERY_FILE"
grep -q '^{}$' "$PY_STYLE_QUERY_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$TOOLS_DIR/nscde_labwc_taskd"

grep -q '^NSCDE_TASK_COUNT=0$' "$STATE_DIR/taskd.env"
grep -q '^NSCDE_TASK_FOCUSED=$' "$STATE_DIR/taskd.env"
grep -q '^NSCDE_TASK_COMMAND_FIFO='"$STATE_DIR"'/topleveld.fifo$' "$STATE_DIR/taskd.env"

if grep -q "send_fifo_command\\|send_pager_command" "$TOOLS_DIR/nscde_labwc_wsm"; then
   echo "runtime-check: workspace manager still contains FIFO control fallback" >&2
   exit 1
fi

if grep -q "send_fifo_command" "$TOOLS_DIR/nscde_labwc_iconbox"; then
   echo "runtime-check: icon box still contains FIFO control fallback" >&2
   exit 1
fi

if grep -q "session_fifo_path\\|labwc\", \"--reconfigure\\|pkill\", \"-TERM\", \"labwc\\|weston-terminal\\|\"xterm\"\\|\"foot\"\\|\"alacritty\"\\|acpimgr\\|sudo\", \"-n\"" "$TOOLS_DIR/nscde_labwc_sysaction"; then
   echo "runtime-check: sysaction still contains direct logout/reload/failsafe/power fallback outside the runtime daemon" >&2
   exit 1
fi

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl workspace-switch Beta

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query workspaces > "$QUERY_FILE"

grep -q '^NSCDE_CURRENT_WORKSPACE=Beta$' "$QUERY_FILE"

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
"$RUNTIME_BIN" ctl color-select Charcoal 8

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl backdrop-select 1 tiled "$BACKDROP_NAME"

attempt=0
while ! test -s "$BACKDROP_FILE"; do
   attempt=$((attempt + 1))
   if [ "$attempt" -ge 50 ]; then
      echo "runtime-check: runtime-owned backdrop materialization did not refresh Desk1 asset" >&2
      ls -l "$BACKER_DIR" >&2 || true
      cat "$DAEMON_LOG" >&2 || true
      exit 1
   fi
   sleep 0.1
done

if ! identify "$BACKDROP_FILE" >/dev/null 2>&1; then
   echo "runtime-check: runtime-owned backdrop materialization did not produce a valid PNG asset" >&2
   ls -l "$BACKER_DIR" >&2 || true
   identify "$BACKDROP_FILE" >&2 || true
   exit 1
fi

cat > "$KEYBIND_FILE" <<EOF
<keyboard>
  <bogus />
</keyboard>
EOF

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl style-apply

attempt=0
while ! grep -F -q -- "-i $BACKDROP_FILE" "$SWAYBG_LOG" 2>/dev/null; do
   attempt=$((attempt + 1))
   if [ "$attempt" -ge 50 ]; then
      echo "runtime-check: backdrop daemon did not launch swaybg" >&2
      cat "$BACKDROPD_LOG" >&2 || true
      cat "$DAEMON_LOG" >&2 || true
      exit 1
   fi
   sleep 0.1
done

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query style > "$STYLE_QUERY_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query backdrops > "$BACKDROP_QUERY_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query session > "$SESSION_QUERY_FILE"

printf '%s\n' 'runtime-check-bogus-backdrop' > "$BOGUS_BACKDROP_FILE"
cat > "$BACKDROP_STATE_FILE" <<EOF
NSCDE_BACKDROP_WORKSPACE=Hacked
NSCDE_BACKDROP_DESK=99
NSCDE_BACKDROP_MODE=photo
NSCDE_BACKDROP_IMAGE_NAME=Bogus
NSCDE_BACKDROP_IMAGE=$BOGUS_BACKDROP_FILE
NSCDE_BACKDROP_COLOR=#123456
NSCDE_BACKDROP_OUTPUT_COUNT=1
NSCDE_BACKDROP_OUTPUT_default_IMAGE=$BOGUS_BACKDROP_FILE
NSCDE_BACKDROP_OUTPUT_default_MODE=photo
NSCDE_BACKDROP_OUTPUT_default_COLOR=#123456
EOF

sleep 2
if grep -F -q -- "-i $BOGUS_BACKDROP_FILE" "$SWAYBG_LOG" 2>/dev/null; then
   echo "runtime-check: backdrop daemon consumed compatibility backdrops.env as live input" >&2
   cat "$BACKDROPD_LOG" >&2 || true
   cat "$SWAYBG_LOG" >&2 || true
   exit 1
fi

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl workspace-switch Alpha

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl workspace-switch Beta

attempt=0
while ! grep -q "^NSCDE_BACKDROP_IMAGE=$BACKDROP_FILE\$" "$BACKDROP_STATE_FILE" 2>/dev/null; do
   attempt=$((attempt + 1))
   if [ "$attempt" -ge 50 ]; then
      echo "runtime-check: runtime-owned backdrop mirror was not restored after workspace refresh" >&2
      cat "$BACKDROP_STATE_FILE" >&2 || true
      cat "$BACKDROPD_LOG" >&2 || true
      exit 1
   fi
   sleep 0.1
done

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query backdrops > "$BACKDROP_QUERY_FILE"

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" query session > "$SESSION_QUERY_FILE"

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
if grep -q '<bogus />' "$KEYBIND_FILE"; then
   echo "runtime-check: daemon-owned style-apply did not refresh labwc keybind xml" >&2
   exit 1
fi

cat > "$KEYBIND_FILE" <<EOF
<keyboard>
  <refresh-bogus />
</keyboard>
EOF

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl refresh keybinds

attempt=0
while grep -q '<refresh-bogus />' "$KEYBIND_FILE" 2>/dev/null; do
   attempt=$((attempt + 1))
   if [ "$attempt" -ge 50 ]; then
      echo "runtime-check: daemon-owned refresh keybinds did not refresh labwc keybind xml" >&2
      cat "$DAEMON_LOG" >&2 || true
      exit 1
   fi
   sleep 0.1
done

cat > "$CONFIG_DIR/menu.xml" <<EOF
<broken-menu />
EOF

cat > "$CONFIG_DIR/rc.xml" <<EOF
<broken-rc />
EOF

HOME="$WORK_DIR/home" \
NSCDE_STATE_DIR="$STATE_DIR" \
"$RUNTIME_BIN" ctl reload

attempt=0
while grep -q '<broken-menu />' "$CONFIG_DIR/menu.xml" 2>/dev/null; do
   attempt=$((attempt + 1))
   if [ "$attempt" -ge 50 ]; then
      echo "runtime-check: daemon-owned reload did not refresh menu.xml" >&2
      cat "$DAEMON_LOG" >&2 || true
      exit 1
   fi
   sleep 0.1
done

attempt=0
while grep -q '<broken-rc />' "$CONFIG_DIR/rc.xml" 2>/dev/null; do
   attempt=$((attempt + 1))
   if [ "$attempt" -ge 50 ]; then
      echo "runtime-check: daemon-owned reload did not refresh rc.xml" >&2
      cat "$DAEMON_LOG" >&2 || true
      exit 1
   fi
   sleep 0.1
done

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
grep -q '^NSCDE_BACKDROP_WORKSPACE=Beta$' "$BACKDROP_QUERY_FILE"
grep -q '^NSCDE_BACKDROP_DESK=2$' "$BACKDROP_QUERY_FILE"
grep -q "^NSCDE_BACKDROP_IMAGE_NAME=$BACKDROP_NAME\$" "$BACKDROP_QUERY_FILE"
grep -q "^NSCDE_BACKDROP_IMAGE=$BACKDROP_FILE\$" "$BACKDROP_QUERY_FILE"
grep -q '^NSCDE_BACKDROP_MODE=tiled$' "$BACKDROP_QUERY_FILE"
grep -q '^NSCDE_BACKDROP_COLOR=#' "$BACKDROP_QUERY_FILE"
grep -q "^NSCDE_BACKDROP_IMAGE=$BACKDROP_FILE\$" "$SESSION_QUERY_FILE"
grep -q '^NSCDE_BACKDROP_COLOR=#' "$SESSION_QUERY_FILE"
grep -q '^NSCDE_BACKDROP_WORKSPACE=Beta$' "$BACKDROP_STATE_FILE"
grep -q '^NSCDE_BACKDROP_DESK=2$' "$BACKDROP_STATE_FILE"
grep -q "^NSCDE_BACKDROP_IMAGE_NAME=$BACKDROP_NAME\$" "$BACKDROP_STATE_FILE"
grep -q '^NSCDE_BACKDROP_OUTPUT_COUNT=1$' "$BACKDROP_STATE_FILE"
grep -q "^NSCDE_BACKDROP_OUTPUT_default_IMAGE=$BACKDROP_FILE\$" "$BACKDROP_STATE_FILE"
grep -q '^NSCDE_BACKDROP_OUTPUT_default_MODE=tiled$' "$BACKDROP_STATE_FILE"
grep -q '^NSCDE_BACKDROP_OUTPUT_default_COLOR=#' "$BACKDROP_STATE_FILE"
grep -F -q -- "-m tile" "$SWAYBG_LOG"
grep -q '^NSCDE_FP_VARIANT=8$' "$PANEL_STYLE_APPLY_FILE"
grep -q '^NSCDE_PALETTE_1=#' "$PANEL_STYLE_APPLY_FILE"
grep -Eq '^gtk-font-name *= *"?DejaVu Serif Book 11"?$' "$GTK3_SETTINGS_FILE"
grep -Eq '^general *= *"DejaVu Serif,11"$' "$QT5CT_FILE"
grep -Eq '^fixed *= *"DejaVu Sans Mono,12"$' "$QT5CT_FILE"
grep -Eq '^Gtk/FontName "DejaVu Serif Book 11"$' "$XSETTINGSD_FILE"
grep -q 'FONT_VARIABLE_NORMAL_MEDIUM_NAME DejaVu Serif' "$XDEFAULTS_FONTDEFS"
grep -q 'FONT_MONOSPACED_NORMAL_MEDIUM_NAME DejaVu Sans Mono' "$XDEFAULTS_FONTDEFS"
test -s "$STATE_DIR/session.env"
test -s "$STATE_DIR/panel.env"
test -s "$BACKDROP_STATE_FILE"
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
