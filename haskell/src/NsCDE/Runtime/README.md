# Haskell Runtime Layer

This directory owns the semantic runtime layer for the standalone Wayland path.

Current ownership shape:

- `NsCDE.Runtime.State`
  - canonical normalized runtime state
  - semantic transitions and invalidation
- `NsCDE.Runtime.Daemon`
  - socket protocol, stream subscription, event sequencing
- `NsCDE.Runtime.Protocol`
  - frame decoding/encoding for `query`, legacy `subscribe`, and
    canonical `subscribe-events`
- `NsCDE.Policy.*`
  - pure or mostly-pure policy expansion for panel layout, keybinds,
    menu generation, backdrops, and session plans

Live-update contract:

- one-shot reads still use `query`
- compatibility streaming still uses `subscribe`
- canonical live updates now use `subscribe-events`
  - bootstrap `snapshot` frames establish initial state
  - sequenced `event` frames carry callback-driven invalidation and deltas
  - clients merge `RESET` / `UNSET` metadata against cached topic state

This layer owns desktop meaning and backend generation logic. Native `C`
clients remain transport consumers/producers and should not own panel, style,
menu, or workspace policy.
