module NsCDE.Domain.Palette
  ( MotifColors(..)
  , PaletteColor(..)
  , parseHexColor8
  , parseHexColor16
  , renderHexColor8
  ) where

import Numeric (readHex, showHex)

data PaletteColor = PaletteColor
  { paletteRed16 :: Int
  , paletteGreen16 :: Int
  , paletteBlue16 :: Int
  } deriving (Eq, Show)

data MotifColors = MotifColors
  { motifBgColor :: PaletteColor
  , motifFgColor :: PaletteColor
  , motifTsColor :: PaletteColor
  , motifBsColor :: PaletteColor
  , motifSelColor :: PaletteColor
  , motifDisabledFgColor :: PaletteColor
  } deriving (Eq, Show)

parseHexColor8 :: String -> Maybe PaletteColor
parseHexColor8 rawValue =
  case stripHash rawValue of
    [r1, r2, g1, g2, b1, b2] -> do
      red <- parseHexComponent [r1, r2]
      green <- parseHexComponent [g1, g2]
      blue <- parseHexComponent [b1, b2]
      pure $
        PaletteColor
          { paletteRed16 = expandByte red
          , paletteGreen16 = expandByte green
          , paletteBlue16 = expandByte blue
          }
    _ -> Nothing

parseHexColor16 :: String -> Maybe PaletteColor
parseHexColor16 rawValue =
  case stripHash rawValue of
    [r1, r2, r3, r4, g1, g2, g3, g4, b1, b2, b3, b4] -> do
      red <- parseHexComponent [r1, r2, r3, r4]
      green <- parseHexComponent [g1, g2, g3, g4]
      blue <- parseHexComponent [b1, b2, b3, b4]
      pure $
        PaletteColor
          { paletteRed16 = red
          , paletteGreen16 = green
          , paletteBlue16 = blue
          }
    _ -> Nothing

renderHexColor8 :: PaletteColor -> String
renderHexColor8 color =
  "#" ++
    renderHexByte (paletteRed16 color `div` 256) ++
    renderHexByte (paletteGreen16 color `div` 256) ++
    renderHexByte (paletteBlue16 color `div` 256)

expandByte :: Int -> Int
expandByte value =
  clamp16 (value * 257)

parseHexComponent :: String -> Maybe Int
parseHexComponent rawValue =
  case readHex rawValue of
    [(parsedValue, "")] -> Just parsedValue
    _ -> Nothing

renderHexByte :: Int -> String
renderHexByte rawValue =
  case showHex (clamp8 rawValue) "" of
    [digit] -> ['0', digit]
    digits -> digits

stripHash :: String -> String
stripHash ('#':rest) = rest
stripHash value = value

clamp8 :: Int -> Int
clamp8 value =
  max 0 (min 255 value)

clamp16 :: Int -> Int
clamp16 value =
  max 0 (min 65535 value)
