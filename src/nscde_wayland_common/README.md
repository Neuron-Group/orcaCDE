# Anticipated Shared Wayland Native Helpers

This directory is reserved for common native helper code shared by `Wayland`
clients in the `NsCDE` rewrite.

Expected responsibilities:

- common logging helpers
- shared state-file readers/writers where native clients need them
- shared icon or drawing helpers that are not panel-specific
- common `Wayland` utility glue

This layer should support native clients without becoming the owner of desktop
policy.

Current implemented slice:

- `panel-layout-contract.[ch]`
  - shared parser/default contract for `panel-layout.env`
  - keeps the file-format boundary out of `nscde_paneld`-local code
  - lets Haskell/Nix publish one contract while C clients share the reader
