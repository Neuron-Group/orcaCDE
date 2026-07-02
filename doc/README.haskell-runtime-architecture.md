# Haskell Runtime Architecture

## Purpose

This note defines the intended `Haskell` runtime shape for the `NsCDE`
`Wayland` rewrite, using the current refactor documents as the architectural
guardrail and the original `NsCDE` runtime as the behavior source.

It is specifically about runtime ownership:

- what should move out of legacy shell and Python code
- what should remain in native `C` helpers
- how the `Haskell` modules should depend on each other
- which entrypoints should exist
- which files, FIFOs, and generated artifacts each entrypoint should own

## Design constraints from the rewrite docs

The runtime design follows the existing repo guidance:

- `C` owns live `Wayland` protocol, rendering, input, and low-latency loops
- `Haskell` owns `NsCDE` meaning, state transforms, command routing, layout,
  style policy, menu generation, and backend generation
- `Nix` owns packaging, static defaults, wrapper assembly, and test closure
- generated files remain outputs, not the primary source of truth
- the original `NsCDE` configuration and helper logic remain the semantic
  reference until the new runtime has replaced them deliberately

## What the original `NsCDE` currently designates

After inspecting the current `NsCDE` tree, the semantic ownership already
clusters into a shape that matches the target `Haskell` layer well.

Current semantic owners worth transplanting:

- `nscde_backend.shlib`
  - XDG/runtime path resolution
  - normalized session/panel/window/workspace/backdrop state
  - capability flags
  - panel-layout publishing
  - subpanel normalization and command translation
  - palette parsing
  - backend adapter helpers
- `nscde_style_state.shlib`
  - normalized style state schema
  - state migration from legacy `FVWM` config
  - backend-facing style intent
- `style_managers.shlib`
  - palette/font/backdrop recording
  - toolkit font propagation
  - backend apply orchestration
- `nscde_labwc_menugen`
  - `AppMenus.conf` parsing
  - menu model to `labwc` XML mapping
- `nscde_labwc_keybindgen`
  - `Keybindings.*` parsing
  - key/action translation into `labwc` XML
- `nscde_labwc_theme`
  - palette-derived theme emission for `labwc`
- `Theme.py`, `ThemeGtk.py`, `MotifColors.py`
  - Motif/CDE color math
  - GTK theme file generation
  - themed image recoloring
- `getfont`, `fontmgr`, `backdropmgr`
  - fontset parsing and font conversion
  - backdrop/photo selection semantics
- `nscde_sessiond`
  - session command routing stub
  - state publication boundary

Current code that should stay outside the `Haskell` runtime:

- `src/nscde_paneld/nscde_paneld.c`
- `src/nscde_pagerd/nscde_pagerd.c`
- `src/nscde_toplevel/nscde_toplevel.c`

Those programs should consume normalized policy and publish events/state, but
they should not become the owner of layout policy, menu policy, or style
semantics.

## Top-level shape

The runtime is now one `Haskell` library plus one primary executable:

- library:
  - `NsCDE.Foundation.*`
  - `NsCDE.Domain.*`
  - `NsCDE.Parse.*`
  - `NsCDE.Policy.*`
  - `NsCDE.Backend.Labwc.*`
- executable: `nscde-runtime`

Tiny shell wrappers may remain for compatibility, but they should only export
environment and delegate to `nscde-runtime`.

The top-level runtime shape should be:

1. `nscde-runtime daemon`
   - long-lived session coordinator
   - canonical owner of normalized runtime state
   - command router between shell UIs, native daemons, and backend generators
2. `nscde-runtime render ...`
   - pure or mostly-pure artifact generation
   - `panel-layout.env`, `menu.xml`, `rc.xml`, `autostart`, `environment`,
     `shutdown`, theme files, toolkit fragments
3. `nscde-runtime style ...`
   - normalized style state read/write
   - style apply orchestration
4. `nscde-runtime import ...`
   - legacy file parsing and migration helpers
5. `nscde-runtime query ...`
   - stable read-side API for wrappers, tests, and native helper tooling
6. `nscde-runtime subscribe ...`
   - compatibility socket stream for older long-lived consumers
7. `nscde-runtime subscribe-events ...`
   - canonical persistent socket stream for live state consumers
   - primary event-driven read path for Qt clients, native `C` daemons, and
     compatibility bridges
   - bootstrap `snapshot` frames establish initial topic state
   - sequenced `event` frames carry callback-driven deltas with `RESET` /
     `UNSET` metadata for cache merge

Within `ctl`, the runtime also now owns typed artifact refresh intents:

- `ctl refresh keybinds`
- `ctl refresh menu`
- `ctl refresh rc`
- `ctl refresh theme`
- `ctl refresh session`

Those intents are narrower than a full backend `reload`: they let wrappers and
tests request specific runtime-owned artifact regeneration without reintroducing
direct local ownership of file-writing behavior.

The runtime also now owns semantic color selection through:

- `ctl color-select PALETTE COLORS`

That command resolves palette names to concrete palette files inside the
runtime layer and writes the normalized style state there, rather than leaving
each GUI client to rediscover palette-path precedence on its own.

The runtime also now owns backdrop selection and apply-time materialization through:

- `ctl backdrop-select DESK MODE IMAGE`

That command writes the normalized per-desk backdrop choice in the runtime
layer and materializes the corresponding desk-specific `backer/DeskN-*.pm`
asset there, so clients no longer need to decide which normalized keys to
mutate or how the live backdrop artifact should be generated.

## Current implemented slice

The current extracted runtime now owns these render-time paths directly:

- `panel-layout.env`
  - static profile import plus env override resolution
  - `StaticPanelProfile` remains the imported reference input
  - `PanelLayoutState` is the canonical runtime-owned published view
  - `PanelLayoutDelta` is the runtime delta shape for live callback updates
- `menu.xml`
  - parsed `AppMenus.conf` import
  - semantic menu model
  - `labwc` XML rendering
- keybind XML
  - parsed `Keybindings.*` import
  - key/action translation
  - `labwc` keyboard fragment rendering
- `themerc` and button glyph assets
  - palette import plus Motif/CDE color derivation
  - `labwc` theme file rendering
  - compatibility glyph asset emission
- `rc.xml`
  - typed theme/workspace/font/focus rendering
  - keybind fragment inclusion through `NSCDE_LABWC_KEYBIND_XML_FILE`
- style apply for `labwc`
  - daemon-owned `style.env` writes
  - typed `StyleState` parsing for palette, front-panel variant, focus policy,
    auto-raise, raise delay, transient/icon/page-edge settings, fonts, and
    per-desk backdrop selection
  - policy-routed apply dispatch
  - runtime-owned `rc.xml` regeneration during apply, rather than in-place XML
    patching in shell-era helpers
  - runtime-owned reload now regenerates `labwc` keybind XML, `menu.xml`,
    `rc.xml`, and theme files before sending the compositor reconfigure signal,
    so a live `reload` replays the current `Haskell` policy outputs instead of
    only reusing previously written artifacts
  - the same regeneration path is now exposed as typed runtime refresh
    commands, so targeted artifact updates use the daemon callback surface
    instead of growing new wrapper-local regeneration helpers
  - the current direct `labwc` apply surface is intentionally narrower than the
    stored style schema: focus policy, auto-raise, and raise delay now feed the
    generated `rc.xml`; transient handling, icon placement, and page-edge
    settings are typed and stored for later backend-native ownership rather
    than silently remaining shell-only
  - backdrop planning now includes runtime-owned default desk fallback derived
    from the classic `NsCDE` backdrop cycle (`Ankh`, `BrickWall`, `Convex`,
    `Toronto`) so a fresh standalone session still resolves a real asset path
    before any user backdrop customization exists
  - backdrop apply-time materialization for desk-specific `backer/DeskN-*.pm`
    outputs now also lives in the runtime layer, leaving the PyQt backdrop
    manager responsible only for UI preview and typed semantic apply requests
  - theme, backdrop, toolkit font integration, and reload orchestration
- `autostart`, `environment`, and `shutdown`
  - typed session-file planning and rendering
- `nscde-runtime daemon`
  - canonical owner of normalized session compatibility state in the
    standalone repo
  - publishes `session.env`, `panel.env`, `panel-layout.env`,
    `workspaces.env`, `pager.env`, `subpanels.env`, `capabilities`, and
    initial `windows.env` / `taskd.env`
  - serves socket-based `ctl`, `query`, legacy `subscribe`, and canonical
    `subscribe-events` requests
  - `subscribe-events` uses `TYPE=subscribe-events`, `TOPICS=...`, and
    optional `BOOTSTRAP=1|0`
  - emits `TYPE=snapshot` bootstrap frames and sequenced `TYPE=event` frames
    with `SEQ`, `EVENT`, `SOURCE`, `RESET`, and `UNSET`
  - surfaces backend action failures as `backend-action-failed` events on the
    session topic instead of silently swallowing effect errors
  - bridges current FIFO compatibility commands for `pagerd` and `toplevel`

The packaged launcher now prefers `nscde-runtime` for:

- `panel-layout publish`
- `labwc-menu publish`
- `labwc-keybinds publish`
- `labwc-theme publish`
- `labwc-rc publish`
- `labwc-session publish`
- session coordination through `daemon`
- shell/PyQt control reads and actions through `query` / `ctl`

The current compatibility shim boundary is:

- `nscde_labwc_keybindgen`
  - now a runtime-first wrapper
- `nscde_labwc_menugen`
  - no longer on the packaged launcher path
- `nscde_sessiond`
  - now a compatibility wrapper that execs `nscde-runtime daemon`
- `nscde_labwc_wsm`, `nscde_labwc_iconbox`, `nscde_labwc_colormgr`,
  `nscde_labwc_backdropmgr`, `nscde_labwc_stylemgr`,
  `nscde_labwc_sysaction`, `nscde_labwc_sysinfo`, `nscde_labwc_fontmgr`,
  `nscde_labwc_windowmgr`
  - now runtime-first clients with socket `query` plus canonical
    `subscribe-events`
  - workspace selection now uses a two-step contract shared with the native
    panel and generated menu actions: runtime `ctl workspace-switch` updates
    normalized workspace/backdrop state first, then the entrypoint performs
    the compositor-facing workspace move through the existing compatibility
    pager bridge or `GoToDesktop` action
  - `nscde_labwc_wsm` now shares that contract through the runtime client
    helper and fails loudly when either the runtime update or the compositor
    bridge is unavailable
  - `nscde_labwc_iconbox` now does the same for restore, maximize, and close:
    live window actions go through runtime `ctl`, and command failure is
    surfaced instead of silently falling back to the compatibility toplevel
    FIFO
  - `nscde_labwc_sysaction` now also treats runtime `ctl reload` as the
    required live restart path; it no longer silently falls back to session
    FIFO writes or direct `labwc --reconfigure`
  - `nscde_labwc_sysaction` logout now goes through runtime `ctl logout`
    instead of directly terminating `labwc`, so session action semantics keep
    moving behind the runtime command surface rather than staying in the GUI
  - `nscde_labwc_sysaction` failsafe terminal launch now also goes through
    runtime `ctl failsafe`, so the runtime owns terminal fallback resolution
    order instead of leaving that behavior embedded in the dialog
  - `nscde_labwc_sysaction` power actions now also go through runtime
    `ctl power ...`, so `acpimgr` execution and its privilege fallback are
    no longer owned directly by the dialog
  - `nscde_labwc_sysaction` and `nscde_labwc_stylemgr` now also consume
    runtime-published `capabilities` for power/system-action availability,
    so the live UI no longer probes those backend support details locally
  - remaining env-file / FIFO fallback in other tools is migration glue only,
    not the intended live API surface
- `nscde_labwc_taskd`
  - now a compatibility-only one-shot refresh shim
  - steady-state `taskd` state is derived by the runtime from `windows`

Current verified handoff:

- `nscde-runtime daemon`, `ctl`, `query`, legacy `subscribe`, and canonical
  `subscribe-events` now pass the standalone
  `runtime-check`
- the packaged launcher autostart now starts `nscde-runtime daemon`
- `runtime-check`, `launcher-check`, and `nix flake check` cover this
  transitional daemon-owned session path while native `C` clients still consume
  compatibility env files and FIFOs
  - `runtime-check` now also covers the daemon-owned style-apply handoff for
    `rc.xml`, theme, backdrop, and toolkit font updates
  - `runtime-check` now also asserts the fresh-session default backdrop plan,
    including workspace-to-desk mapping, default backdrop name, resolved asset
    path, and exported backdrop mode, to guard against the black-background
    regression that appeared when runtime backdrop planning stopped falling back
    to the legacy desk defaults
- the steady-state live runtime path is now socket-first and event-driven:
  long-lived clients bootstrap from runtime snapshots and then follow
  sequenced runtime events, `nscde_labwc_taskd` no longer owns a live
  subscribe loop, and the native `C` daemons no longer use fixed 1-second
  polling loops for live state updates

The current live-read preference is now:

- runtime socket `query`
  - primary one-shot read path for tools and startup sync
- runtime socket `subscribe-events`
  - primary event-driven path for long-lived UI and bridge clients
  - topic cache contract:
    `snapshot` replaces cached topic state
    `event` with `RESET=1` clears cached topic state before overlay
    `UNSET` removes named keys from cached topic state
- runtime socket `subscribe`
  - compatibility streaming path retained during migration
- env files and FIFOs
  - compatibility mirrors for legacy consumers and staged migration glue

That means `windows.env`, `workspaces.env`, `pager.env`, `panel.env`,
`panel-layout.env`, and `backdrops.env` remain important outputs, but they are
no longer the intended owner-facing live API for newly refactored clients.

The current live-write preference is now:

- runtime socket `ctl`
  - owner-facing semantic state updates such as palette, backdrop, workspace,
    logout, reload, and power requests
- compositor-native actions at the entrypoint edge
  - final `GoToDesktop` or pager activation step when a request needs both
    runtime semantic state change and an immediate compositor workspace move
- env files and FIFOs
  - compatibility bridges only, not the intended owner-facing command surface

## Runtime clarity checkpoint

The current runtime is already past the main polling-to-events transition.

Implemented checkpoint:

- steady-state live reads are socket-first through `query` and
  `subscribe-events`
- long-lived Qt tools consume runtime callbacks instead of file polling
- shell task-list publication is driven from runtime subscriptions instead of
  a `sleep 1` loop
- native `C` helpers now block on `Wayland`, runtime, signal, or file-system
  events instead of periodic live-state polling

Remaining work to count the runtime as architecturally clear:

1. shrink `legacy-shims/` further so it is wrappers and packaging glue only,
   not the owner of remaining session/style behavior
2. keep env/FIFO compatibility artifacts as mirrors only; owner-facing live
   clients now require the runtime socket as the normal live API
3. finish the `Haskell` module split away from leaf renderers and environment
   scraping into the intended `Foundation`/`Domain`/`Policy`/`Backend` graph
4. keep reconnect and startup semantics explicit and diagnosable now that the
   transition-only helpers are gone: owner-facing clients fail loudly when the
   runtime socket is unavailable or disconnects

## Dependency graph

The module graph should stay acyclic and narrow:

`Foundation -> Domain -> Parse/Store -> Policy -> Backend -> App/Daemon`

More explicitly:

- `Foundation`
  - no dependency on backend modules
- `Domain`
  - depends only on `Foundation`
- `Parse` and `Store`
  - depend on `Foundation` and `Domain`
- `Policy`
  - depends on `Foundation`, `Domain`, `Parse`, `Store`
  - does not depend on CLI code
- `Backend`
  - depends on `Foundation`, `Domain`, `Policy`
  - backend-specific renderers live here
- `App` and `Daemon`
  - depend on everything above
  - no lower layer depends on them

## Module tree

### 1. Foundation

`NsCDE.Foundation.*`

Responsibilities:

- filesystem helpers
- atomic write helpers
- env-file and ini-file primitives
- shell quoting and XML escaping
- process execution wrappers
- logging and diagnostics
- typed errors

Suggested modules:

- `Foundation.EnvFile`
- `Foundation.Ini`
- `Foundation.AtomicFile`
- `Foundation.Paths`
- `Foundation.Process`
- `Foundation.Text`
- `Foundation.Log`

Current implemented modules:

- `Foundation.EnvFile`
- `Foundation.Common`
- `Foundation.Settings`

### 2. Domain

`NsCDE.Domain.*`

Responsibilities:

- typed representation of `NsCDE` concepts
- no parsing and no file I/O

Suggested modules:

- `Domain.Backend`
  - backend id, capability set, reload semantics
- `Domain.Session`
  - session settings, command names, runtime directories
- `Domain.Workspace`
  - workspace list, current workspace, rename capability
- `Domain.Window`
  - normalized toplevel/window model
- `Domain.Output`
  - output geometry and scale snapshot
- `Domain.Palette`
  - raw CDE palette and derived Motif colorsets
- `Domain.Font`
  - font slots, fontset, toolkit font targets
- `Domain.Backdrop`
  - backdrop mode, image, per-output mapping
- `Domain.Panel`
  - panel profile, sections, modules, geometry
- `Domain.Subpanel`
  - subpanel entries and translated actions
- `Domain.Menu`
  - semantic root menu and application menu tree
- `Domain.Keymap`
  - normalized keybindings independent from `FVWM` syntax
- `Domain.Style`
  - normalized style state

### 3. Legacy import and migration

`NsCDE.Parse.*`

Responsibilities:

- parse legacy `NsCDE` inputs into typed domain values
- keep legacy file format knowledge out of backend renderers

Current implemented modules:

- `Parse.AppMenus`
- `Parse.Keybindings`

Suggested next modules:

- `Parse.PaletteDp`
  - port `nscde_palette_parse`, `nscde_palette_color`
- `Parse.Fontset`
  - port `.fontset` parsing from `getfont`, `fontmgr`,
    `nscde_style_record_fontset`
- `Parse.Subpanels`
  - port `nscde_subpanel_publish` input parsing
- `Parse.StyleMgrIni`
  - integration preferences now read in `_nscde_style_apply_fonts_labwc`
- `Parse.FvwmConfig`
  - focused migration readers from `nscde_style_migrate_from_fvwm`

### 4. State store and compatibility views

`NsCDE.Store.*`

Responsibilities:

- typed access to normalized runtime state
- publish compatibility env files used by current native clients and GUI tools

Suggested modules:

- `Store.SessionState`
- `Store.StyleState`
  - currently owns normalized `style.env` reads/writes plus
    `ResolvedStyleState`, which keeps palette path resolution and published
    panel palette entries out of `Runtime.State`
- `Store.WorkspaceState`
- `Store.WindowState`
- `Store.PanelState`
- `Store.PanelLayoutState`
- `Store.SubpanelState`
- `Store.BackdropState`
- `Store.CapabilityState`

Important rule:

- env files remain a compatibility transport
- the source of truth should be typed `Haskell` values in the daemon and
  stable normalized state files written by the store layer

### 5. Policy layer

`NsCDE.Policy.*`

Responsibilities:

- pure `NsCDE` semantics
- backend-agnostic transforms
- no raw `Wayland` or `FVWM` syntax

Suggested modules:

- `Policy.PanelLayout`
  - transplant `nscde_panel_layout_publish`
  - own scaling, section geometry, module widths, WSM sizing
  - evolve current `PanelLayout.hs` into this module
- `Policy.Subpanel`
  - translate parsed subpanel definitions into normalized runtime actions
- `Policy.StyleApply`
  - decide what must be regenerated and reloaded after style changes
- `Policy.ThemeIntent`
  - shared palette/font/theme intent across backends
- `Policy.Backdrop`
  - desk selection, mode resolution, per-output expansion rules
- `Policy.Menu`
  - root menu structure and grouping policy
- `Policy.Keymap`
  - normalized bindings and override precedence
- `Policy.SessionPlan`
  - helper autostart ordering, env export set, runtime bootstrap

### 6. Backend layer

`NsCDE.Runtime.Backend.*`

Responsibilities:

- render backend-specific outputs from typed policy models
- expose a small adapter contract

Suggested shared root:

- `Backend.Adapter`
  - explicit contract for:
    - session
    - outputs
    - workspaces
    - windows
    - menus
    - background
    - reload

Use a small record-based adapter, not a deep typeclass hierarchy.

Suggested `labwc` modules:

- `Backend.Labwc.RcXml`
  - split out of current `LabwcSession`
- `Backend.Labwc.MenuXml`
  - split out of current `LabwcMenu`
- `Backend.Labwc.KeybindXml`
  - port `nscde_labwc_keybindgen`
- `Backend.Labwc.Theme`
  - port `nscde_labwc_theme`
- `Backend.Labwc.SessionFiles`
  - `autostart`, `environment`, `shutdown`
- `Backend.Labwc.Reload`
  - current `SIGHUP`/command routing semantics

Suggested `fvwm` modules:

- `Backend.Fvwm.Config`
- `Backend.Fvwm.Reload`
- `Backend.Fvwm.Session`

Even if `fvwm` remains partial in the first `Haskell` pass, the module split
should reserve the boundary now so `labwc` code does not become the accidental
shape of the core.

### 7. Integration layer

`NsCDE.Runtime.Integration.*`

Responsibilities:

- generate toolkit-facing configs that are not compositor-specific but still
  belong to runtime policy

Suggested modules:

- `Integration.MotifColors`
  - port `MotifColors.py`
- `Integration.GtkTheme`
  - port `Theme.py` and `ThemeGtk.py`
- `Integration.FontTargets`
  - port `_nscde_style_apply_fonts_labwc`, `fontmgr -T`, `fontmgr -Q`,
    `fontmgr -X` logic into typed conversions
- `Integration.Xresources`
- `Integration.Dunst`
- `Integration.Xsettingsd`

This layer should not own style state. It should only render integration
outputs from `Domain.Style` and `Policy.ThemeIntent`.

### 8. App and daemon layer

`NsCDE.Runtime.App.*`

Responsibilities:

- CLI parsing
- command execution
- long-lived daemon wiring

Suggested modules:

- `App.Main`
- `App.Commands.PanelLayout`
- `App.Commands.Menu`
- `App.Commands.Keybinds`
- `App.Commands.Theme`
- `App.Commands.Style`
- `App.Commands.Import`
- `App.Commands.Query`
- `App.Daemon.Sessiond`

The current `haskell/app/nscde-runtime.hs` should stay thin and delegate
immediately into these command modules.

## Entry points and outputs

### Primary daemon

`nscde-runtime daemon`

Owns:

- command FIFO or socket endpoints
- canonical in-memory session state
- publication of compatibility env files
- backend reload requests

Publishes:

- `session.env`
- `panel.env`
- `panel-layout.env`
- `workspaces.env`
- `windows.env`
- `backdrops.env`
- `capabilities`
- `subpanels.env`
- `pager.env`
- `taskd.env`

### Render commands

`nscde-runtime render panel-layout`

- input:
  - static reference profile
  - environment overrides
  - normalized workspace/module settings
- output:
  - `panel-layout.env`
  - optionally stdout for wrapper compatibility

`nscde-runtime render labwc menu`

- input:
  - normalized menu model
  - `AppMenus.conf` imports
  - tool paths and workspace names
- output:
  - `menu.xml`

`nscde-runtime render labwc keybinds`

- input:
  - normalized keymap
  - parsed `Keybindings.*`
- output:
  - `keyboard` XML fragment or dedicated file

`nscde-runtime render labwc rc`

- input:
  - normalized session and style state
- output:
  - `rc.xml`

`nscde-runtime render labwc session-files`

- output:
  - `autostart`
  - `environment`
  - `shutdown`

`nscde-runtime render labwc theme`

- input:
  - normalized palette and motif color model
- output:
  - `themerc`
  - button glyph assets
  - later: additional theme metadata

### Style commands

`nscde-runtime style set ...`

- writes typed style state

`nscde-runtime style apply`

- reads normalized style state
- refreshes the daemon snapshot from `Store.StyleState` before publishing
  follow-on state
- regenerates required artifacts
- republish panel/style views
- requests compositor/helper reload

Outputs include:

- updated style state
- regenerated theme files
- toolkit config fragments
- backdrop refresh request
- panel state refresh

## How native clients should relate to the runtime

The native `C` helpers should become event bridges and renderers, not policy
owners.

Desired relationship:

- `nscde_paneld`
  - now uses runtime socket `query` plus canonical `subscribe-events` for
    `panel`, `panel-layout`, `workspaces`, and `subpanels`
  - keeps `panel.env`, `panel-layout.env`, and `subpanels.env` only as
    compatibility outputs for transitional consumers
  - renders and sends commands
  - does not decide layout policy
- `nscde_pagerd`
  - listens to `Wayland` workspace protocol
  - reports workspace events to the daemon
  - does not own workspace naming policy
- `nscde_toplevel`
  - listens to toplevel protocol
  - reports normalized window events to the daemon
  - does not own task-list semantics

Stage-one compatibility is allowed:

- keep env-file publication while migrating
- keep FIFO command format until the daemon stabilizes
- let native helpers use the runtime socket as the required owner-facing live
  API, with env/FIFO artifacts kept only as migration glue for external or
  compatibility consumers
- later move event ingress to a clearer socket protocol if needed

At this point compatibility guidance mainly applies to published mirrors and
compatibility command bridges. The live owner-facing path is runtime-socket
only and stays event-driven.

## Immediate refactor of the current Haskell seed

The existing `NsCDE-Wayland` `Haskell` runtime is a good seed, but it is still
too close to leaf renderers and environment scraping.

Current modules should evolve as follows:

- `EnvFile` -> `Foundation.EnvFile`
- `PanelLayout` -> `Policy.PanelLayout`
- `LabwcMenu` -> split into:
  - `Parse.AppMenus`
  - `Policy.Menu`
  - `Backend.Labwc.MenuXml`
- `LabwcSession` -> split into:
  - `Policy.SessionPlan`
  - `Backend.Labwc.RcXml`
  - `Backend.Labwc.SessionFiles`
- `Runtime.State`
  - keep daemon/state publication only
  - consume resolved style snapshots from `Store.StyleState` rather than
    reparsing raw style and palette files locally
  - continue moving style-apply parsing and backend execution into
    `Policy.StyleApply` and `Backend.Labwc.StyleApply`
- `app/nscde-runtime.hs` -> thin dispatcher only

Shared helper duplication currently present in `PanelLayout`, `LabwcMenu`, and
`LabwcSession` should be removed first. That is the smallest refactor that
starts to enforce the correct module graph.

## Recommended implementation order

1. extract `Foundation` and `Domain` from the current `Haskell` seed
2. move `panel-layout` fully under typed `Policy.PanelLayout`
3. port `menu.xml` and `keybind` generation through parsed ASTs
4. replace shell `nscde_sessiond` with `nscde-runtime daemon`
5. port `nscde_backend.shlib` state publication and adapter logic
6. port style state and style apply flow
7. port palette/motif/theme generation
8. shrink legacy shims to wrappers only

## Non-goals for the first Haskell pass

The first pass should not:

- move live `Wayland` protocol loops into `Haskell`
- rewrite `nscde_paneld`, `nscde_pagerd`, or `nscde_toplevel`
- invent a new panel/menu/workspace model unrelated to original `NsCDE`
- replace all compatibility env files before the daemon and clients are ready

## Decision summary

The `Haskell` runtime should become the owner of:

- normalized runtime and style state
- legacy config import and migration
- panel, menu, keybinding, theme, and session generation policy
- backend adapter selection and apply orchestration
- command routing and compatibility state publication

It should not become the owner of:

- `Wayland` protocol event loops
- panel rendering
- compositor decoration drawing
- packaging and wrapper assembly
