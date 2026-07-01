module NsCDE.Parse.PaletteDp
  ( loadPaletteColors
  , loadPaletteEntries
  , parsePaletteColors
  , parsePaletteContents
  , resolvePalettePath
  ) where

import System.Directory (doesFileExist)
import System.FilePath ((</>), (<.>), takeExtension)

import NsCDE.Domain.Palette (PaletteColor, parseHexColor16, renderHexColor8)

parsePaletteContents :: String -> [String]
parsePaletteContents contents =
  map renderHexColor8 (parsePaletteColors contents)

parsePaletteColors :: String -> [PaletteColor]
parsePaletteColors contents =
  foldr collectColor [] (lines contents)

loadPaletteEntries :: FilePath -> IO [String]
loadPaletteEntries "" = pure []
loadPaletteEntries palettePath = do
  exists <- doesFileExist palettePath
  if exists
    then do
      contents <- readFile palettePath
      pure (parsePaletteContents contents)
    else pure []

loadPaletteColors :: FilePath -> IO [PaletteColor]
loadPaletteColors "" = pure []
loadPaletteColors palettePath = do
  exists <- doesFileExist palettePath
  if exists
    then do
      contents <- readFile palettePath
      pure (parsePaletteColors contents)
    else pure []

resolvePalettePath :: FilePath -> FilePath -> String -> IO (Maybe FilePath)
resolvePalettePath _ _ "" = pure Nothing
resolvePalettePath fvwmUserDir dataDir paletteName = do
  directExists <- doesFileExist paletteName
  if directExists
    then pure (Just paletteName)
    else firstExistingPalette candidatePaths
  where
    paletteFileName
      | takeExtension paletteName == ".dp" = paletteName
      | otherwise = paletteName <.> "dp"
    candidatePaths =
      [ fvwmUserDir </> "palettes" </> paletteFileName
      , dataDir </> "palettes" </> paletteFileName
      ]

collectColor :: String -> [PaletteColor] -> [PaletteColor]
collectColor rawLine acc =
  case parseHexColor16 rawLine of
    Nothing -> acc
    Just color -> color : acc

firstExistingPalette :: [FilePath] -> IO (Maybe FilePath)
firstExistingPalette [] = pure Nothing
firstExistingPalette (candidate:rest) = do
  exists <- doesFileExist candidate
  if exists
    then pure (Just candidate)
    else firstExistingPalette rest
