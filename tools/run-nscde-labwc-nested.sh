#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
KEEP_TEST_ROOT="${NSCDE_LABWC_KEEP_TEST_ROOT:-0}"
FULLSCREEN_NESTED="${NSCDE_LABWC_NESTED_FULLSCREEN:-0}"
NESTED_SIZE="${NSCDE_LABWC_NESTED_SIZE:-1280x720}"
TESTHOME="$(mktemp -d)"
TESTBIN="$TESTHOME/bin"
STARTUP_LOG="$TESTHOME/.cache/nscde-labwc-startup.log"

cleanup() {
  if [[ "$KEEP_TEST_ROOT" != "1" ]]; then
    rm -rf "$TESTHOME"
  else
    printf 'Kept test home: %s\n' "$TESTHOME"
  fi
}
trap cleanup EXIT INT TERM

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

require_file() {
  [[ -e "$1" ]] || {
    printf 'Missing required file: %s\n' "$1" >&2
    exit 1
  }
}

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  printf 'Error: WAYLAND_DISPLAY not set. Run this from a Wayland session.\n' >&2
  exit 1
fi

if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
  printf 'Error: XDG_RUNTIME_DIR not set. Run this from a Wayland session.\n' >&2
  exit 1
fi

require_cmd nix
require_cmd weston
require_cmd foot
require_file "$ROOT_DIR/flake.nix"
require_file "$ROOT_DIR/.gitmodules"

case "$NESTED_SIZE" in
  *x*)
    NESTED_WIDTH="${NESTED_SIZE%x*}"
    NESTED_HEIGHT="${NESTED_SIZE#*x}"
    ;;
  *)
    printf 'Invalid NSCDE_LABWC_NESTED_SIZE: %s\n' "$NESTED_SIZE" >&2
    exit 1
    ;;
esac

if [[ ! -e "$ROOT_DIR/labwc/meson.build" ]]; then
  require_cmd git
  printf 'Ensuring standalone labwc submodule is present...\n'
  git -C "$ROOT_DIR" submodule update --init --recursive
fi

printf 'Building standalone NsCDE-Wayland bootstrap...\n'
BOOTSTRAP_OUT="$(nix build --no-link --print-out-paths "path:$ROOT_DIR#nscde-wayland-bootstrap")"

mkdir -p "$TESTBIN"
cat > "$TESTBIN/nscde-test-terminal" <<'EOF'
#!/bin/sh
exec foot -o csd.preferred=server -o csd.size=0 "$@"
EOF
chmod +x "$TESTBIN/nscde-test-terminal"

printf 'Pre-generating standalone NsCDE-Wayland session files...\n'
XDG_CONFIG_HOME="$TESTHOME/.config" \
XDG_CACHE_HOME="$TESTHOME/.cache" \
XDG_DATA_HOME="$TESTHOME/.local/share" \
HOME="$TESTHOME" \
PATH="$TESTBIN:$PATH" \
NSCDE_LABWC_AUTOSTART_TERMINAL=0 \
NSCDE_LABWC_TERMINAL="$TESTBIN/nscde-test-terminal" \
NSCDE_LABWC_PREPARE_ONLY=1 \
NSCDE_LABWC_STARTUP_LOG="$STARTUP_LOG" \
  "$BOOTSTRAP_OUT/bin/nscde_labwc"

printf 'Starting nested Weston transport compositor...\n'
weston_args=(--backend=wayland --socket=nscde-stage1)
if [[ "$FULLSCREEN_NESTED" == "1" ]]; then
  weston_args+=(--fullscreen)
else
  weston_args+=(--width="$NESTED_WIDTH" --height="$NESTED_HEIGHT")
fi
weston_args+=(--shell=kiosk-shell.so)

printf 'Launching standalone NsCDE-Wayland with temporary HOME %s\n' "$TESTHOME"
XDG_CONFIG_HOME="$TESTHOME/.config" \
XDG_CACHE_HOME="$TESTHOME/.cache" \
XDG_DATA_HOME="$TESTHOME/.local/share" \
HOME="$TESTHOME" \
PATH="$TESTBIN:$PATH" \
NSCDE_LABWC_AUTOSTART_TERMINAL=0 \
NSCDE_LABWC_TERMINAL="$TESTBIN/nscde-test-terminal" \
NSCDE_LABWC_SKIP_PREPARE=1 \
NSCDE_LABWC_STARTUP_LOG="$STARTUP_LOG" \
weston "${weston_args[@]}" -- \
  env -u DISPLAY WAYLAND_DISPLAY=nscde-stage1 \
  "$BOOTSTRAP_OUT/bin/nscde_labwc" >/tmp/weston-nscde-stage1.log 2>&1
