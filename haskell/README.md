# Anticipated Haskell Runtime Layout

This directory is now the start of the `NsCDE` semantic runtime layer in the
`Wayland`/`labwc` rewrite.

Current implemented slice:

- `app/nscde-runtime.hs`
  - thin runtime CLI entrypoint
- `src/NsCDE/Foundation/`
  - shared env-file, lookup, escaping, quoting, and atomic-write helpers
- `src/NsCDE/Domain/`
  - typed panel, menu, keybind, and session records
- `src/NsCDE/Parse/`
  - legacy `AppMenus.conf` and `Keybindings.*` import paths
- `src/NsCDE/Policy/`
  - typed panel-layout, menu, keybind, and session planning logic
- `src/NsCDE/Backend/Labwc/`
  - `menu.xml`, keybind XML, `rc.xml`, and session-file renderers
- `test/Main.hs`
  - runtime parser and renderer coverage under the Cabal test suite

Current live contract:

- `Nix` materializes a static reference panel profile
- the Haskell runtime reads that profile plus runtime env overrides
- the runtime publishes normalized `panel-layout.env`
- the runtime publishes `labwc` `menu.xml` from parsed `AppMenus.conf`
- the runtime publishes `labwc` keybind XML from parsed `Keybindings.*`
- the runtime publishes `labwc` session support files from launcher/session
  inputs
- the runtime now publishes `labwc` `rc.xml` from normalized workspace/theme/
  font/focus inputs and generated keybind XML fragments
- `nscde_paneld` consumes that file as its `Wayland`-native policy input

This is intentionally a first extraction, not the full runtime migration yet.
The existing shell publisher remains as the compatibility fallback.

Planned ownership:

- normalized state model
- backend-neutral command vocabulary
- session orchestration
- `labwc` config generation
- theme, menu, keybind, and panel policy generation
- migration and validation logic

Planned internal shape:

- `app/` for executable entrypoints
- `src/` for library code
- `test/` for runtime model and generator tests

Current commands:

- `nscde-runtime panel-layout publish [STATIC_PANEL_LAYOUT_FILE]`
- `nscde-runtime labwc-menu publish CONFIG_DIR`
- `nscde-runtime labwc-keybinds publish`
- `nscde-runtime labwc-rc publish CONFIG_DIR`
- `nscde-runtime labwc-session publish CONFIG_DIR`
