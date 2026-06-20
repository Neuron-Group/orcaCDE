# Anticipated Haskell Runtime Layout

This directory is now the start of the `NsCDE` semantic runtime layer in the
`Wayland`/`labwc` rewrite.

Current implemented slice:

- `app/nscde-runtime.hs`
  - first runtime CLI entrypoint
- `src/NsCDE/Runtime/PanelLayout.hs`
  - typed panel-layout policy transform
- `src/NsCDE/Runtime/LabwcSession.hs`
  - typed `labwc` session-file publisher for `autostart`, `environment`, and
    `shutdown`, plus `rc.xml` generation from normalized launcher inputs
- `src/NsCDE/Runtime/EnvFile.hs`
  - shared key/value file reader for the first runtime contract

Current live contract:

- `Nix` materializes a static reference panel profile
- the Haskell runtime reads that profile plus runtime env overrides
- the runtime publishes normalized `panel-layout.env`
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
