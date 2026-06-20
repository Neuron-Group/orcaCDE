# Standalone Repo Split

## Purpose

This tree is the standalone repository layout for the `Wayland` runtime,
living beside the original `NsCDE` source tree.

The assumption behind this layout is:

- the `Wayland` path is already diverging structurally from the legacy
  `FVWM`/`X11` runtime
- the rewrite can no longer treat the original `NsCDE` repository as the only
  honest long-term owner of the new runtime
- selected legacy assets still matter, but they should be copied explicitly
  instead of remaining hidden dependencies

## What is imported

Imported code:

- `labwc/` as a standalone-owned compositor submodule
- `haskell/`
- `nix/`
- `src/nscde_wayland_common/`
- `src/nscde_common/nscde-pixel-icon.[ch]`
- `src/nscde_paneld/`
- `src/nscde_pagerd/`
- `src/nscde_toplevel/`
- `bin/nscde_labwc.in`
- temporary `legacy-shims/` for shell-era glue still on the migration path
- `lib/python/` because the current theme and manager helpers still depend on
  those modules

Imported assets:

- `data/palettes/`
- `data/fontsets/`
- `data/backdrops/`
- `data/photos/`
- selected `data/fvwm/Font-*.fvwmconf`
- selected `data/fvwm/Keybindings.*`
- `data/icons/NsCDE/`
- selected `data/defaults/*`
- `xdg/` session, application, menu, and icon-theme assets

## What is intentionally not imported

This standalone runtime repo does not copy the full legacy repository.

Not imported as primary source:

- the `fvwm3` backend path
- the bulk of legacy `lib/scripts/` `FvwmScript` UI code
- `autotools` packaging as the target end-state
- old generated outputs as the source of truth

## Near-term expectation

This is the runtime home for the `Wayland` path, but it still contains
transitional imported assets and shell-era compatibility seams.

Near-term work should:

1. keep moving runtime ownership from `legacy-shims/` into `haskell/`
2. keep `src/` focused on `Wayland`-native mechanics only
3. keep asset extraction explicit through `ASSETS.manifest`
4. treat `NsCDE/` as a historical behavior reference and optional sync source,
   not the place where the new runtime architecture should keep living

## Bootstrap build root

This repo now includes a standalone bootstrap project root:

- `flake.nix`
- `cabal.project`
- `nscde-wayland-runtime.cabal`
- `tools/check-runtime.sh`
- `tools/check-launcher.sh`

Current buildable slice:

- the extracted `Haskell` runtime builds as `nscde-runtime`
- the extracted native `Wayland` daemons build as:
  - `nscde-paneld`
  - `nscde-pagerd`
  - `nscde-toplevel`
  - combined `nscde-wayland-clients`
- the flake default package is now `nscde-wayland-bootstrap`, combining the
  current launcher, session wrapper, extracted assets, runtime, and native
  clients
- the reference static panel/session contracts are materialized from
  `nix/modules/`
- `nix run .#runtime-check` verifies the extracted runtime path end to end
- `nix run .#launcher-check` verifies the packaged launcher prepare-only path
- `nix flake check` verifies the combined standalone bootstrap outputs
- the standalone flake now builds its packaged launcher against the bundled
  `labwc/` submodule instead of defaulting to upstream `nixpkgs` `labwc`

Current limitation:

- `legacy-shims/` still owns too much session/theme/style glue for the tree to
  count as a fully standalone runtime
- some of those remaining pieces still live as `.in` templates because they
  rely on configure-style substitution during packaging
- `menu.xml` generation has already moved out of that set: the standalone
  launcher now uses `nscde-runtime` for menu publishing, and the packaged
  bootstrap no longer ships `nscde_labwc_menugen`
- keybind generation has now moved with it: the standalone launcher prefers
  `nscde-runtime labwc-keybinds publish`, and `nscde_labwc_keybindgen` remains
  only as a compatibility wrapper

## Repo layout decision

Yes: the rewrite is now laid out as a standalone repository beside the
original `NsCDE` tree.

That arrangement matches the technical reality better than keeping the
`Wayland` runtime framed as an extension of the legacy repo:

- `NsCDE/` stays available as behavior reference, upstream history, and asset
  source during migration
- `NsCDE-Wayland/` becomes the direct owner of the new runtime layout
- only currently used assets are copied in, with provenance tracked in
  `ASSETS.manifest`
- remaining `.in` files are treated as temporary migration seams, not as the
  long-term structure of the new repo
