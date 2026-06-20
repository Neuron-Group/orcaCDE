module NsCDE.Parse.PaletteDp
  ( loadPaletteColors
  , loadPaletteEntries
  , parsePaletteColors
  , parsePaletteContents
  ) where

import System.Directory (doesFileExist)

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

collectColor :: String -> [PaletteColor] -> [PaletteColor]
collectColor rawLine acc =
  case parseHexColor16 rawLine of
    Nothing -> acc
    Just color -> color : acc
