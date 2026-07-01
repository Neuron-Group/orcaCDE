module NsCDE.Policy.Backdrop
  ( backdropCandidatePaths
  , buildBackdropPlan
  , currentBackdropDesk
  , renderBackdropEntries
  , resolveBackdropPath
  ) where

import System.Directory (doesFileExist)
import System.FilePath ((</>))

import NsCDE.Domain.Backdrop
  ( BackdropMode(..)
  , BackdropPlan(..)
  , renderBackdropMode
  )
import NsCDE.Domain.Style
  ( DeskBackdrop(..)
  , StyleState
  , lookupDeskBackdrop
  )
import NsCDE.Foundation.EnvFile (KeyValue)

buildBackdropPlan :: FilePath -> FilePath -> [String] -> String -> StyleState -> [KeyValue] -> IO BackdropPlan
buildBackdropPlan fvwmUserDir dataDir workspaces currentWorkspace styleState paletteEntries =
  let deskNumber = currentBackdropDesk workspaces currentWorkspace
      primaryBackdrop =
        case lookupDeskBackdrop deskNumber styleState of
          Just backdrop -> Just backdrop
          Nothing ->
            case lookupDeskBackdrop 1 styleState of
              Just backdrop -> Just backdrop
              Nothing -> defaultDeskBackdrop deskNumber
      resolvedMode =
        case primaryBackdrop of
          Just backdrop -> deskBackdropMode backdrop
          Nothing -> Nothing
      resolvedImage =
        case primaryBackdrop of
          Just backdrop -> deskBackdropImage backdrop
          Nothing -> ""
      paletteColor = firstPaletteColor paletteEntries
  in do
    resolvedPath <-
      case primaryBackdrop of
        Just backdrop ->
          resolveBackdropPath
            fvwmUserDir
            dataDir
            (deskBackdropDesk backdrop)
            (deskBackdropMode backdrop)
            (deskBackdropImage backdrop)
        Nothing -> pure Nothing
    let outputMappings =
          case resolvedPath of
            Just path ->
              [ ("default", path, maybe "" renderBackdropMode resolvedMode, paletteColor) ]
            Nothing -> []
    pure BackdropPlan
      { backdropPlanWorkspace = currentWorkspace
      , backdropPlanDesk = deskNumber
      , backdropPlanMode = resolvedMode
      , backdropPlanImage = resolvedImage
      , backdropPlanSourcePath = resolvedPath
      , backdropPlanPaletteColor = paletteColor
      , backdropPlanOutputMappings = outputMappings
      }

currentBackdropDesk :: [String] -> String -> Int
currentBackdropDesk workspaces currentWorkspace =
  case findWorkspaceIndex 1 workspaces of
    Just index -> index
    Nothing -> 1
  where
    findWorkspaceIndex _ [] = Nothing
    findWorkspaceIndex index (workspaceName:rest)
      | workspaceName == currentWorkspace = Just index
      | otherwise = findWorkspaceIndex (index + 1) rest

renderBackdropEntries :: BackdropPlan -> [KeyValue]
renderBackdropEntries backdropPlan =
  [ ("NSCDE_BACKDROP_WORKSPACE", backdropPlanWorkspace backdropPlan)
  , ("NSCDE_BACKDROP_DESK", show (backdropPlanDesk backdropPlan))
  , ("NSCDE_BACKDROP_MODE", maybe "" renderBackdropMode (backdropPlanMode backdropPlan))
  , ("NSCDE_BACKDROP_IMAGE_NAME", backdropPlanImage backdropPlan)
  , ("NSCDE_BACKDROP_IMAGE", maybe "" id (backdropPlanSourcePath backdropPlan))
  , ("NSCDE_BACKDROP_COLOR", backdropPlanPaletteColor backdropPlan)
  , ("NSCDE_BACKDROP_OUTPUT_COUNT", show (length (backdropPlanOutputMappings backdropPlan)))
  ] ++ concatMap renderOutputMapping (backdropPlanOutputMappings backdropPlan)

renderOutputMapping :: (String, FilePath, String, String) -> [KeyValue]
renderOutputMapping (outputName, imagePath, modeText, colorText) =
  [ ("NSCDE_BACKDROP_OUTPUT_" ++ outputName ++ "_IMAGE", imagePath)
  , ("NSCDE_BACKDROP_OUTPUT_" ++ outputName ++ "_MODE", modeText)
  , ("NSCDE_BACKDROP_OUTPUT_" ++ outputName ++ "_COLOR", colorText)
  ]

backdropCandidatePaths :: FilePath -> FilePath -> Int -> Maybe BackdropMode -> String -> [FilePath]
backdropCandidatePaths fvwmUserDir dataDir deskNumber backdropMode backdropImage
  | null backdropImage = []
  | backdropMode == Just BackdropModeTiled =
      [ fvwmUserDir </> "backer" </> ("Desk" ++ show deskNumber ++ "-" ++ backdropImage ++ ".png")
      , fvwmUserDir </> "backer" </> ("Desk" ++ show deskNumber ++ "-" ++ backdropImage ++ ".pm")
      , fvwmUserDir </> "backdrops" </> (backdropImage ++ ".pm")
      , dataDir </> "backdrops" </> (backdropImage ++ ".pm")
      ]
  | backdropMode == Just BackdropModePhoto || backdropMode == Just BackdropModeAspect =
      [ fvwmUserDir </> "backer" </> ("Desk" ++ show deskNumber ++ "-" ++ backdropImage ++ ".png")
      , fvwmUserDir </> "backer" </> ("Desk" ++ show deskNumber ++ "-" ++ backdropImage ++ ".pm")
      , fvwmUserDir </> "photos" </> (backdropImage ++ ".png")
      , dataDir </> "photos" </> (backdropImage ++ ".png")
      ]
  | otherwise = []

resolveBackdropPath :: FilePath -> FilePath -> Int -> Maybe BackdropMode -> String -> IO (Maybe FilePath)
resolveBackdropPath fvwmUserDir dataDir deskNumber backdropMode backdropImage =
  firstExistingPath (backdropCandidatePaths fvwmUserDir dataDir deskNumber backdropMode backdropImage)

firstExistingPath :: [FilePath] -> IO (Maybe FilePath)
firstExistingPath [] = pure Nothing
firstExistingPath (candidate:rest) = do
  candidateExists <- doesFileExist candidate
  if candidateExists
    then pure (Just candidate)
    else firstExistingPath rest

firstPaletteColor :: [KeyValue] -> String
firstPaletteColor [] = "#506070"
firstPaletteColor ((key, value):rest)
  | key == "NSCDE_PALETTE_1" && not (null value) = value
  | otherwise = firstPaletteColor rest

defaultDeskBackdrop :: Int -> Maybe DeskBackdrop
defaultDeskBackdrop deskNumber =
  let normalizedDesk =
        case deskNumber of
          n | n <= 0 -> 1
          n -> ((n - 1) `mod` 8) + 1
      backdropName =
        case normalizedDesk of
          1 -> "Ankh"
          2 -> "BrickWall"
          3 -> "Convex"
          4 -> "Toronto"
          5 -> "Ankh"
          6 -> "BrickWall"
          7 -> "Convex"
          _ -> "Toronto"
  in Just
      DeskBackdrop
        { deskBackdropDesk = normalizedDesk
        , deskBackdropMode = Just BackdropModeTiled
        , deskBackdropImage = backdropName
        }
