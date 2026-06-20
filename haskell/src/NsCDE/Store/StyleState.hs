module NsCDE.Store.StyleState
  ( ResolvedStyleState(..)
  , readStyleEntries
  , readResolvedStyleState
  , readStyleState
  , resolveStyleEntries
  , writeResolvedStyleEntries
  , writeStyleEntries
  ) where

import System.Directory (createDirectoryIfMissing)

import NsCDE.Domain.Style (StyleState, styleSelectedPaletteFile)
import NsCDE.Foundation.Common (writeAtomicFile)
import NsCDE.Foundation.EnvFile (KeyValue, readEnvFileIfExists, renderEnvFile)
import NsCDE.Foundation.Paths (RuntimePaths(..))
import NsCDE.Parse.PaletteDp (loadPaletteEntries)
import NsCDE.Parse.StyleState (parseStyleStateEntries)

data ResolvedStyleState = ResolvedStyleState
  { resolvedStyleState :: StyleState
  , resolvedStylePaletteFile :: FilePath
  , resolvedStylePaletteEntries :: [KeyValue]
  } deriving (Eq, Show)

readStyleEntries :: RuntimePaths -> IO [KeyValue]
readStyleEntries paths =
  readEnvFileIfExists (runtimeStyleFile paths)

readResolvedStyleState :: RuntimePaths -> FilePath -> IO ResolvedStyleState
readResolvedStyleState paths fallbackPaletteFile =
  readStyleEntries paths >>= resolveStyleEntries fallbackPaletteFile

readStyleState :: RuntimePaths -> IO StyleState
readStyleState paths =
  parseStyleStateEntries <$> readStyleEntries paths

resolveStyleEntries :: FilePath -> [KeyValue] -> IO ResolvedStyleState
resolveStyleEntries fallbackPaletteFile styleEntries = do
  let styleState = parseStyleStateEntries styleEntries
      paletteFile = styleSelectedPaletteFile styleState fallbackPaletteFile
  paletteEntries <- loadPaletteEnvEntries paletteFile
  pure
    ResolvedStyleState
      { resolvedStyleState = styleState
      , resolvedStylePaletteFile = paletteFile
      , resolvedStylePaletteEntries = paletteEntries
      }

writeResolvedStyleEntries :: RuntimePaths -> FilePath -> [KeyValue] -> IO ResolvedStyleState
writeResolvedStyleEntries paths fallbackPaletteFile styleUpdates = do
  mergedEntries <- writeStyleEntries paths styleUpdates
  resolveStyleEntries fallbackPaletteFile mergedEntries

writeStyleEntries :: RuntimePaths -> [KeyValue] -> IO [KeyValue]
writeStyleEntries paths styleUpdates = do
  createDirectoryIfMissing True (runtimeStateDir paths)
  existingEntries <- readStyleEntries paths
  let mergedEntries = mergeStyleEntries existingEntries styleUpdates
  writeAtomicFile (runtimeStyleFile paths) (renderEnvFile mergedEntries)
  pure mergedEntries

mergeStyleEntries :: [KeyValue] -> [KeyValue] -> [KeyValue]
mergeStyleEntries =
  foldl mergeStyleEntry

mergeStyleEntry :: [KeyValue] -> KeyValue -> [KeyValue]
mergeStyleEntry existingEntries (key, value) =
  filter ((/= key) . fst) existingEntries ++ [(key, value)]

loadPaletteEnvEntries :: FilePath -> IO [KeyValue]
loadPaletteEnvEntries palettePath =
  zipPaletteEntries <$> loadPaletteEntries palettePath

zipPaletteEntries :: [String] -> [KeyValue]
zipPaletteEntries colors =
  [ ("NSCDE_PALETTE_" ++ show index, color)
  | (index, color) <- zip [1 :: Int ..] colors
  ]
