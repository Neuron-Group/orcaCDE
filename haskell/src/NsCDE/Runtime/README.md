# Anticipated Haskell Runtime Modules

Planned module families:

- `NsCDE.Runtime.Model`
- `NsCDE.Runtime.State`
- `NsCDE.Runtime.Commands`
- `NsCDE.Runtime.Session`
- `NsCDE.Runtime.Style`
- `NsCDE.Runtime.Generate.Labwc`
- `NsCDE.Runtime.Generate.Panel`
- `NsCDE.Runtime.Migrate`

This directory is a placeholder for the semantic runtime layer. It should own
desktop meaning and backend generation logic, not `Wayland` protocol loops.
