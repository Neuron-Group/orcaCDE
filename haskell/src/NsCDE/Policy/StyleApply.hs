module NsCDE.Policy.StyleApply
  ( applyResolvedStyleState
  , applyStyleState
  ) where

import NsCDE.Backend.Labwc.StyleApply (applyLabwcStyle)
import NsCDE.Domain.Runtime (RuntimeStyleContext)
import NsCDE.Domain.Style (StyleState)
import NsCDE.Store.StyleState (ResolvedStyleState(..))

applyStyleState :: String -> RuntimeStyleContext -> FilePath -> StyleState -> IO ()
applyStyleState backendName runtimeContext palettePath styleState =
  case backendName of
    "labwc" -> applyLabwcStyle runtimeContext palettePath styleState
    _ -> pure ()

applyResolvedStyleState :: String -> RuntimeStyleContext -> ResolvedStyleState -> IO ()
applyResolvedStyleState backendName runtimeContext resolvedStyle =
  applyStyleState
    backendName
    runtimeContext
    (resolvedStylePaletteFile resolvedStyle)
    (resolvedStyleState resolvedStyle)
