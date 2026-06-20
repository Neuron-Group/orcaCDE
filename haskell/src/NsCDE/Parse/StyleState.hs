module NsCDE.Parse.StyleState
  ( parseStyleStateEntries
  ) where

import Data.Char (toLower)

import NsCDE.Domain.Style
  ( FocusPolicy(..)
  , IconFill(..)
  , IconPlacement(..)
  , IconSize(..)
  , StyleState(..)
  , defaultStyleState
  )
import NsCDE.Foundation.Common (splitCommaList, trim)
import NsCDE.Foundation.EnvFile (KeyValue)
import NsCDE.Foundation.Settings (lookupText)

parseStyleStateEntries :: [KeyValue] -> StyleState
parseStyleStateEntries entries =
  defaultStyleState
    { stylePalettePath = lookupText entries "NSCDE_PALETTE_PATH" ""
    , stylePaletteFile = lookupText entries "NSCDE_PALETTE_FILE" ""
    , stylePaletteName = lookupText entries "NSCDE_PALETTE_NAME" ""
    , styleFpVariant =
        case lookupText entries "NSCDE_FP_VARIANT" (styleFpVariant defaultStyleState) of
          "5" -> "5"
          _ -> "8"
    , styleFocusPolicy =
        parseFocusPolicy
          (lookupText entries "NSCDE_FOCUS_POLICY" "MouseFocus")
    , styleAutoRaise =
        parseEnabled
          (lookupText entries "NSCDE_AUTO_RAISE" "0")
    , styleRaiseDelayMs =
        parseNonNegativeInt
          (styleRaiseDelayMs defaultStyleState)
          (lookupText entries "NSCDE_RAISE_DELAY" "0")
    , styleRaiseTransient =
        parseEnabled
          (lookupText entries "NSCDE_RAISE_TRANSIENT" "1")
    , styleLowerTransient =
        parseEnabled
          (lookupText entries "NSCDE_LOWER_TRANSIENT" "1")
    , styleStackTransient =
        parseEnabled
          (lookupText entries "NSCDE_STACK_TRANSIENT" "1")
    , styleOpaqueMovePercent =
        parseNonNegativeInt
          (styleOpaqueMovePercent defaultStyleState)
          (lookupText entries "NSCDE_OPAQUE_MOVE" "100")
    , styleMoveThresholdPx =
        parseNonNegativeInt
          (styleMoveThresholdPx defaultStyleState)
          (lookupText entries "NSCDE_MOVE_THRESHOLD" "0")
    , styleIconPlacement =
        parseIconPlacement
          (lookupText entries "NSCDE_ICON_PLACEMENT" "0")
    , styleIconFill =
        parseIconFill
          (lookupText entries "NSCDE_ICON_FILL" "bottom.left")
    , styleIconSize =
        parseIconSize
          (lookupText entries "NSCDE_ICON_SIZE" "48,48,128,128")
    , styleRaiseFrontPanelOnPage =
        parseEnabled
          (lookupText entries "NSCDE_RAISE_FP_ON_PAGE" "0")
    , stylePagerPreview =
        parseEnabled
          (lookupText entries "NSCDE_PAGER_PREVIEW" "0")
    , styleEdgeThicknessPx =
        parseNonNegativeInt
          (styleEdgeThicknessPx defaultStyleState)
          (lookupText entries "NSCDE_EDGE_THICKNESS" "0")
    , styleEdgeResistancePx =
        parseNonNegativeInt
          (styleEdgeResistancePx defaultStyleState)
          (lookupText entries "NSCDE_EDGE_RESISTANCE" "0")
    , styleEdgeMoveResistancePx =
        parseNonNegativeInt
          (styleEdgeMoveResistancePx defaultStyleState)
          (lookupText entries "NSCDE_EDGE_MOVE_RESISTANCE" "0")
    , styleEdgeMoveDelayMs =
        parseNonNegativeInt
          (styleEdgeMoveDelayMs defaultStyleState)
          (lookupText entries "NSCDE_EDGE_MOVE_DELAY" "0")
    , styleFontsetName = lookupText entries "NSCDE_FONTSET_NAME" ""
    , styleFontVariableNormalMedium =
        lookupText entries "NSCDE_FONT_VARIABLE_NORMAL_MEDIUM" ""
    , styleFontMonospacedNormalMedium =
        lookupText entries "NSCDE_FONT_MONOSPACED_NORMAL_MEDIUM" ""
    , styleBackdropDesk1Mode =
        lookupText entries "NSCDE_BACKDROP_DESK_1_MODE" ""
    , styleBackdropDesk1Image =
        lookupText entries "NSCDE_BACKDROP_DESK_1_IMAGE" ""
    }

parseFocusPolicy :: String -> FocusPolicy
parseFocusPolicy value =
  case map toLower (trim value) of
    "clicktofocus" -> ClickToFocus
    "sloppyfocus" -> SloppyFocus
    _ -> MouseFocus

parseIconPlacement :: String -> IconPlacement
parseIconPlacement value =
  case trim value of
    "1" -> IconPlacementIconBox
    _ -> IconPlacementWorkspace

parseIconFill :: String -> IconFill
parseIconFill value =
  case map toLower (trim value) of
    "top.left" -> IconFillTopLeft
    "bottom.right" -> IconFillBottomRight
    "top.right" -> IconFillTopRight
    _ -> IconFillBottomLeft

parseIconSize :: String -> IconSize
parseIconSize rawValue =
  case map parseInteger (splitCommaList rawValue) of
    [Just defWidth, Just defHeight, Just maxWidth, Just maxHeight] ->
      IconSize
        { styleIconDefaultWidth = max 0 defWidth
        , styleIconDefaultHeight = max 0 defHeight
        , styleIconMaxWidth = max 0 maxWidth
        , styleIconMaxHeight = max 0 maxHeight
        }
    _ -> styleIconSize defaultStyleState

parseEnabled :: String -> Bool
parseEnabled value =
  case map toLower (trim value) of
    "1" -> True
    "true" -> True
    "yes" -> True
    "on" -> True
    _ -> False

parseNonNegativeInt :: Int -> String -> Int
parseNonNegativeInt fallbackValue rawValue =
  case parseInteger rawValue of
    Just parsedValue -> max 0 parsedValue
    Nothing -> fallbackValue

parseInteger :: String -> Maybe Int
parseInteger rawValue =
  case reads (trim rawValue) of
    [(parsedValue, "")] -> Just parsedValue
    _ -> Nothing
