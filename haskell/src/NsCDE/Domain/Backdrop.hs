module NsCDE.Domain.Backdrop
  ( BackdropMode(..)
  , BackdropSelection(..)
  , BackdropPlan(..)
  , parseBackdropMode
  , renderBackdropMode
  ) where

data BackdropMode
  = BackdropModeTiled
  | BackdropModePhoto
  | BackdropModeAspect
  | BackdropModeUnknown String
  deriving (Eq, Show)

data BackdropSelection = BackdropSelection
  { backdropSelectionDesk :: Int
  , backdropSelectionMode :: BackdropMode
  , backdropSelectionImage :: String
  } deriving (Eq, Show)

data BackdropPlan = BackdropPlan
  { backdropPlanWorkspace :: String
  , backdropPlanDesk :: Int
  , backdropPlanMode :: Maybe BackdropMode
  , backdropPlanImage :: String
  , backdropPlanSourcePath :: Maybe FilePath
  , backdropPlanPaletteColor :: String
  , backdropPlanOutputMappings :: [(String, FilePath, String, String)]
  } deriving (Eq, Show)

parseBackdropMode :: String -> Maybe BackdropMode
parseBackdropMode value =
  case value of
    "" -> Nothing
    "tiled" -> Just BackdropModeTiled
    "photo" -> Just BackdropModePhoto
    "aspect" -> Just BackdropModeAspect
    _ -> Just (BackdropModeUnknown value)

renderBackdropMode :: BackdropMode -> String
renderBackdropMode mode =
  case mode of
    BackdropModeTiled -> "tiled"
    BackdropModePhoto -> "photo"
    BackdropModeAspect -> "aspect"
    BackdropModeUnknown value -> value
