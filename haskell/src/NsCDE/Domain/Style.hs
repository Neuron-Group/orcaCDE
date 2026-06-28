module NsCDE.Domain.Style
  ( FocusPolicy(..)
  , DeskBackdrop(..)
  , IconFill(..)
  , IconPlacement(..)
  , IconSize(..)
  , StyleState(..)
  , defaultStyleState
  , lookupDeskBackdrop
  , styleBackdropDesk1Image
  , styleBackdropDesk1Mode
  , styleSelectedPaletteFile
  ) where

import NsCDE.Domain.Backdrop (BackdropMode, renderBackdropMode)

data FocusPolicy
  = MouseFocus
  | SloppyFocus
  | ClickToFocus
  deriving (Eq, Show)

data IconPlacement
  = IconPlacementWorkspace
  | IconPlacementIconBox
  deriving (Eq, Show)

data IconFill
  = IconFillBottomLeft
  | IconFillTopLeft
  | IconFillBottomRight
  | IconFillTopRight
  deriving (Eq, Show)

data DeskBackdrop = DeskBackdrop
  { deskBackdropDesk :: Int
  , deskBackdropMode :: Maybe BackdropMode
  , deskBackdropImage :: String
  } deriving (Eq, Show)

data IconSize = IconSize
  { styleIconDefaultWidth :: Int
  , styleIconDefaultHeight :: Int
  , styleIconMaxWidth :: Int
  , styleIconMaxHeight :: Int
  } deriving (Eq, Show)

data StyleState = StyleState
  { stylePalettePath :: FilePath
  , stylePaletteFile :: FilePath
  , stylePaletteName :: String
  , styleFpVariant :: String
  , styleFocusPolicy :: FocusPolicy
  , styleAutoRaise :: Bool
  , styleRaiseDelayMs :: Int
  , styleRaiseTransient :: Bool
  , styleLowerTransient :: Bool
  , styleStackTransient :: Bool
  , styleOpaqueMovePercent :: Int
  , styleMoveThresholdPx :: Int
  , styleIconPlacement :: IconPlacement
  , styleIconFill :: IconFill
  , styleIconSize :: IconSize
  , styleRaiseFrontPanelOnPage :: Bool
  , stylePagerPreview :: Bool
  , styleEdgeThicknessPx :: Int
  , styleEdgeResistancePx :: Int
  , styleEdgeMoveResistancePx :: Int
  , styleEdgeMoveDelayMs :: Int
  , styleFontsetName :: String
  , styleFontVariableNormalMedium :: String
  , styleFontMonospacedNormalMedium :: String
  , styleDeskBackdrops :: [DeskBackdrop]
  } deriving (Eq, Show)

defaultStyleState :: StyleState
defaultStyleState =
  StyleState
    { stylePalettePath = ""
    , stylePaletteFile = ""
    , stylePaletteName = ""
    , styleFpVariant = "8"
    , styleFocusPolicy = MouseFocus
    , styleAutoRaise = False
    , styleRaiseDelayMs = 0
    , styleRaiseTransient = True
    , styleLowerTransient = True
    , styleStackTransient = True
    , styleOpaqueMovePercent = 100
    , styleMoveThresholdPx = 0
    , styleIconPlacement = IconPlacementWorkspace
    , styleIconFill = IconFillBottomLeft
    , styleIconSize =
        IconSize
          { styleIconDefaultWidth = 48
          , styleIconDefaultHeight = 48
          , styleIconMaxWidth = 128
          , styleIconMaxHeight = 128
          }
    , styleRaiseFrontPanelOnPage = False
    , stylePagerPreview = False
    , styleEdgeThicknessPx = 0
    , styleEdgeResistancePx = 0
    , styleEdgeMoveResistancePx = 0
    , styleEdgeMoveDelayMs = 0
    , styleFontsetName = ""
    , styleFontVariableNormalMedium = ""
    , styleFontMonospacedNormalMedium = ""
    , styleDeskBackdrops = []
    }

lookupDeskBackdrop :: Int -> StyleState -> Maybe DeskBackdrop
lookupDeskBackdrop deskNumber styleState =
  go (styleDeskBackdrops styleState)
  where
    go [] = Nothing
    go (backdrop:rest)
      | deskBackdropDesk backdrop == deskNumber = Just backdrop
      | otherwise = go rest

styleBackdropDesk1Mode :: StyleState -> String
styleBackdropDesk1Mode styleState =
  case lookupDeskBackdrop 1 styleState of
    Just backdrop ->
      case deskBackdropMode backdrop of
        Just mode -> renderBackdropMode mode
        Nothing -> ""
    Nothing -> ""

styleBackdropDesk1Image :: StyleState -> String
styleBackdropDesk1Image styleState =
  case lookupDeskBackdrop 1 styleState of
    Just backdrop -> deskBackdropImage backdrop
    Nothing -> ""

styleSelectedPaletteFile :: StyleState -> FilePath -> FilePath
styleSelectedPaletteFile styleState fallbackPaletteFile
  | null (stylePalettePath styleState) = paletteFileOrFallback
  | otherwise = stylePalettePath styleState
  where
    paletteFileOrFallback
      | null (stylePaletteFile styleState) = fallbackPaletteFile
      | otherwise = stylePaletteFile styleState
