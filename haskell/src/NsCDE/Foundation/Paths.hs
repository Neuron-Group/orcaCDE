module NsCDE.Foundation.Paths
  ( RuntimePaths(..)
  , resolveRuntimePaths
  ) where

import System.FilePath ((</>))

import NsCDE.Foundation.EnvFile (KeyValue)
import NsCDE.Foundation.Settings (lookupText)

data RuntimePaths = RuntimePaths
  { runtimeStateDir :: FilePath
  , runtimeSessionFile :: FilePath
  , runtimePanelFile :: FilePath
  , runtimePanelLayoutFile :: FilePath
  , runtimeWorkspacesFile :: FilePath
  , runtimeBackdropsFile :: FilePath
  , runtimeWindowsFile :: FilePath
  , runtimeSubpanelsFile :: FilePath
  , runtimePagerFile :: FilePath
  , runtimeTaskdFile :: FilePath
  , runtimeCapabilitiesFile :: FilePath
  , runtimeCommandFifo :: FilePath
  , runtimePagerFifo :: FilePath
  , runtimeToplevelFifo :: FilePath
  , runtimeSocketFile :: FilePath
  , runtimePidFile :: FilePath
  , runtimeStyleFile :: FilePath
  } deriving (Eq, Show)

resolveRuntimePaths :: [KeyValue] -> RuntimePaths
resolveRuntimePaths env =
  let homeDir = lookupText env "HOME" "/tmp"
      cacheHome = lookupText env "XDG_CACHE_HOME" (homeDir </> ".cache")
      stateDir = lookupText env "NSCDE_STATE_DIR" (cacheHome </> "nscde-stage1")
  in RuntimePaths
      { runtimeStateDir = stateDir
      , runtimeSessionFile = stateDir </> "session.env"
      , runtimePanelFile = stateDir </> "panel.env"
      , runtimePanelLayoutFile = stateDir </> "panel-layout.env"
      , runtimeWorkspacesFile = stateDir </> "workspaces.env"
      , runtimeBackdropsFile = stateDir </> "backdrops.env"
      , runtimeWindowsFile = stateDir </> "windows.env"
      , runtimeSubpanelsFile = stateDir </> "subpanels.env"
      , runtimePagerFile = stateDir </> "pager.env"
      , runtimeTaskdFile = stateDir </> "taskd.env"
      , runtimeCapabilitiesFile = stateDir </> "capabilities"
      , runtimeCommandFifo = stateDir </> "sessiond.fifo"
      , runtimePagerFifo = stateDir </> "pagerd.fifo"
      , runtimeToplevelFifo = stateDir </> "topleveld.fifo"
      , runtimeSocketFile = stateDir </> "runtime.sock"
      , runtimePidFile = stateDir </> "runtime.pid"
      , runtimeStyleFile = stateDir </> "style.env"
      }
