# Anticipated Nix Wrappers

Reserved for generated or template-backed wrapper entrypoints that:

- export `NSCDE_*` and `XDG_*` defaults
- inject dependency closures and tool paths
- expose flake app entrypoints consistently

Wrappers should stay small and inspectable.
