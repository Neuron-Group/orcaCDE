module NsCDE.Store.BackdropState
  ( readBackdropEntries
  , writeBackdropEntries
  ) where

import System.Directory (createDirectoryIfMissing)

import NsCDE.Foundation.Common (writeAtomicFile)
import NsCDE.Foundation.EnvFile (KeyValue, readEnvFileIfExists, renderEnvFile)
import NsCDE.Foundation.Paths (RuntimePaths(..))

readBackdropEntries :: RuntimePaths -> IO [KeyValue]
readBackdropEntries paths =
  readEnvFileIfExists (runtimeBackdropsFile paths)

writeBackdropEntries :: RuntimePaths -> [KeyValue] -> IO ()
writeBackdropEntries paths entries = do
  createDirectoryIfMissing True (runtimeStateDir paths)
  writeAtomicFile (runtimeBackdropsFile paths) (renderEnvFile entries)
