module NsCDE.Backend.Labwc.SessionFiles
  ( renderAutostart
  , renderEnvironment
  , renderShutdown
  ) where

import NsCDE.Domain.Session
import NsCDE.Foundation.EnvFile (renderEnvFile)

renderAutostart :: SessionPlan -> String
renderAutostart =
  unlines . sessionAutostartLines

renderEnvironment :: SessionPlan -> String
renderEnvironment =
  renderEnvFile . sessionEnvironmentEntries

renderShutdown :: SessionPlan -> String
renderShutdown =
  unlines . sessionShutdownLines
