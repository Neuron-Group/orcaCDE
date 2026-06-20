module NsCDE.Parse.PaletteDp
  ( loadPaletteEntries
  , parsePaletteContents
  ) where

import System.Directory (doesFileExist)

parsePaletteContents :: String -> [String]
parsePaletteContents contents =
  foldr collectLine [] (lines contents)

loadPaletteEntries :: FilePath -> IO [String]
loadPaletteEntries "" = pure []
loadPaletteEntries palettePath = do
  exists <- doesFileExist palettePath
  if exists
    then do
      contents <- readFile palettePath
      pure (parsePaletteContents contents)
    else pure []

collectLine :: String -> [String] -> [String]
collectLine rawLine acc =
  case normalizePaletteLine rawLine of
    Nothing -> acc
    Just color -> color : acc

normalizePaletteLine :: String -> Maybe String
normalizePaletteLine rawLine =
  let line =
        case rawLine of
          '#':rest -> rest
          value -> value
  in case split16 line of
       Just (rr16, gg16, bb16) ->
         Just ('#' : take 2 rr16 ++ take 2 gg16 ++ take 2 bb16)
       Nothing -> Nothing

split16 :: String -> Maybe (String, String, String)
split16 value =
  let rr16 = take 4 value
      gg16 = take 4 (drop 4 value)
      bb16 = take 4 (drop 8 value)
  in if length rr16 == 4 && length gg16 == 4 && length bb16 == 4
       then Just (rr16, gg16, bb16)
       else Nothing
