module NsCDE.Integration.MotifColors
  ( motifColorsFromBackground
  ) where

import NsCDE.Domain.Palette

motifColorsFromBackground :: PaletteColor -> MotifColors
motifColorsFromBackground bgColor
  | bgBrightness < xmColorDarkThreshold =
      calculateDarkBackground bgColor bgBrightness
  | bgBrightness > xmColorLiteThreshold =
      calculateLightBackground bgColor bgBrightness
  | otherwise =
      calculateMediumBackground bgColor bgBrightness
  where
    bgBrightness = brightness bgColor

calculateDarkBackground :: PaletteColor -> Double -> MotifColors
calculateDarkBackground bgColor bgBrightness =
  let (fgColor, disabledFgColor) = resolveForegroundColors bgBrightness
  in MotifColors
      { motifBgColor = bgColor
      , motifFgColor = fgColor
      , motifTsColor = lightenColor bgColor xmColorDarkTsFactor
      , motifBsColor = lightenColor bgColor xmColorDarkBsFactor
      , motifSelColor = lightenColor bgColor xmColorDarkSelFactor
      , motifDisabledFgColor = disabledFgColor
      }

calculateLightBackground :: PaletteColor -> Double -> MotifColors
calculateLightBackground bgColor bgBrightness =
  let (fgColor, disabledFgColor) = resolveForegroundColors bgBrightness
  in MotifColors
      { motifBgColor = bgColor
      , motifFgColor = fgColor
      , motifTsColor = darkenColor bgColor xmColorLiteTsFactor
      , motifBsColor = darkenColor bgColor xmColorLiteBsFactor
      , motifSelColor = darkenColor bgColor xmColorLiteSelFactor
      , motifDisabledFgColor = disabledFgColor
      }

calculateMediumBackground :: PaletteColor -> Double -> MotifColors
calculateMediumBackground bgColor bgBrightness =
  let (fgColor, disabledFgColor) = resolveForegroundColors bgBrightness
      selFactor =
        xmColorLoSelFactor +
          (bgBrightness * (xmColorHiSelFactor - xmColorLoSelFactor) / xmMaxShort)
      bsFactor =
        xmColorLoBsFactor +
          (bgBrightness * (xmColorHiBsFactor - xmColorLoBsFactor) / xmMaxShort)
      tsFactor =
        xmColorLoTsFactor +
          (bgBrightness * (xmColorHiTsFactor - xmColorLoTsFactor) / xmMaxShort)
  in MotifColors
      { motifBgColor = bgColor
      , motifFgColor = fgColor
      , motifTsColor = lightenColor bgColor tsFactor
      , motifBsColor = darkenColor bgColor bsFactor
      , motifSelColor = darkenColor bgColor selFactor
      , motifDisabledFgColor = disabledFgColor
      }

resolveForegroundColors :: Double -> (PaletteColor, PaletteColor)
resolveForegroundColors bgBrightness
  | bgBrightness > xmForegroundThreshold =
      ( solidColor 0
      , solidColor 32768
      )
  | otherwise =
      ( solidColor 65535
      , solidColor 45800
      )

solidColor :: Int -> PaletteColor
solidColor value =
  PaletteColor
    { paletteRed16 = value
    , paletteGreen16 = value
    , paletteBlue16 = value
    }

lightenColor :: PaletteColor -> Double -> PaletteColor
lightenColor color factor =
  PaletteColor
    { paletteRed16 = lightenComponent (paletteRed16 color) factor
    , paletteGreen16 = lightenComponent (paletteGreen16 color) factor
    , paletteBlue16 = lightenComponent (paletteBlue16 color) factor
    }

darkenColor :: PaletteColor -> Double -> PaletteColor
darkenColor color factor =
  PaletteColor
    { paletteRed16 = darkenComponent (paletteRed16 color) factor
    , paletteGreen16 = darkenComponent (paletteGreen16 color) factor
    , paletteBlue16 = darkenComponent (paletteBlue16 color) factor
    }

lightenComponent :: Int -> Double -> Int
lightenComponent component factor =
  clampComponent $
    floor (componentValue + factor * (xmMaxShort - componentValue) / 100.0)
  where
    componentValue = fromIntegral component

darkenComponent :: Int -> Double -> Int
darkenComponent component factor =
  clampComponent $
    floor (componentValue - (componentValue * factor) / 100.0)
  where
    componentValue = fromIntegral component

clampComponent :: Int -> Int
clampComponent value =
  max 0 (min 65535 value)

brightness :: PaletteColor -> Double
brightness color =
  ((intensity * xmIntensityFactor) +
    (lightness * xmLightFactor) +
    (luminosity * xmLuminosityFactor)) / 100.0
  where
    red = fromIntegral (paletteRed16 color)
    green = fromIntegral (paletteGreen16 color)
    blue = fromIntegral (paletteBlue16 color)
    intensity = (red + green + blue) / 3.0
    luminosity =
      (xmRedLuminosity * red) +
      (xmGreenLuminosity * green) +
      (xmBlueLuminosity * blue)
    lightness = (minimum [red, green, blue] + maximum [red, green, blue]) / 2.0

xmColorLiteSelFactor :: Double
xmColorLiteSelFactor = 15

xmColorLiteBsFactor :: Double
xmColorLiteBsFactor = 40

xmColorLiteTsFactor :: Double
xmColorLiteTsFactor = 20

xmColorLoSelFactor :: Double
xmColorLoSelFactor = 15

xmColorLoBsFactor :: Double
xmColorLoBsFactor = 60

xmColorLoTsFactor :: Double
xmColorLoTsFactor = 50

xmColorHiSelFactor :: Double
xmColorHiSelFactor = 15

xmColorHiBsFactor :: Double
xmColorHiBsFactor = 40

xmColorHiTsFactor :: Double
xmColorHiTsFactor = 60

xmColorDarkSelFactor :: Double
xmColorDarkSelFactor = 15

xmColorDarkBsFactor :: Double
xmColorDarkBsFactor = 30

xmColorDarkTsFactor :: Double
xmColorDarkTsFactor = 50

xmRedLuminosity :: Double
xmRedLuminosity = 0.30

xmGreenLuminosity :: Double
xmGreenLuminosity = 0.59

xmBlueLuminosity :: Double
xmBlueLuminosity = 0.11

xmIntensityFactor :: Double
xmIntensityFactor = 75

xmLightFactor :: Double
xmLightFactor = 0

xmLuminosityFactor :: Double
xmLuminosityFactor = 25

xmMaxShort :: Double
xmMaxShort = 65535

xmColorLiteThreshold :: Double
xmColorLiteThreshold = 93 * (xmMaxShort / 100)

xmColorDarkThreshold :: Double
xmColorDarkThreshold = 20 * (xmMaxShort / 100)

xmForegroundThreshold :: Double
xmForegroundThreshold = 70 * (xmMaxShort / 100)
