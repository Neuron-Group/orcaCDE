# Anticipated Nix Layout

This directory is the planned home for `NsCDE`-local `Nix` material related to
the `Wayland` rewrite.

The root workspace `flake.nix` remains the integration entrypoint. This local
tree is reserved for `NsCDE`-specific declarative assembly concerns such as:

- wrappers
- profile defaults
- static config materialization
- reusable `Nix` modules for session assembly

Current implemented slice:

- `modules/reference-panel-layout.nix`
  - materializes the static reference panel profile consumed by the first
    Haskell runtime extraction
- `modules/reference-labwc-session-env.nix`
  - materializes static `labwc` session defaults for the launcher path

It should not become the owner of live runtime session policy.
