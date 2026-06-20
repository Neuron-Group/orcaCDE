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

## Current implemented slice

The current extracted runtime now owns these render-time paths directly:

- `panel-layout.env`
  - static profile import plus env override resolution
- `menu.xml`
  - parsed `AppMenus.conf` import
  - semantic menu model
  - `labwc` XML rendering
- keybind XML
  - parsed `Keybindings.*` import
  - key/action translation
  - `labwc` keyboard fragment rendering
- `rc.xml`
  - typed theme/workspace/font/focus rendering
  - keybind fragment inclusion through `NSCDE_LABWC_KEYBIND_XML_FILE`
- `autostart`, `environment`, and `shutdown`
  - typed session-file planning and rendering

The packaged launcher now prefers `nscde-runtime` for:

- `panel-layout publish`
- `labwc-menu publish`
- `labwc-keybinds publish`
- `labwc-rc publish`
- `labwc-session publish`

The current compatibility shim boundary is:

- `nscde_labwc_keybindgen`
  - now a runtime-first wrapper
- `nscde_labwc_menugen`
  - no longer on the packaged launcher path

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
  - reads `panel.env`, `panel-layout.env`, `subpanels.env`
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
- later move event ingress to a clearer socket protocol if needed

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
