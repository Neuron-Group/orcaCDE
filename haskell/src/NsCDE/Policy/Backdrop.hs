module NsCDE.Policy.Backdrop
  ( backdropCandidatePaths
  , resolveBackdropPath
  ) where

import System.Directory (doesFileExist)
import System.FilePath ((</>))

backdropCandidatePaths :: FilePath -> FilePath -> String -> String -> [FilePath]
backdropCandidatePaths fvwmUserDir dataDir backdropMode backdropImage
  | null backdropImage = []
  | backdropMode == "tiled" =
      [ fvwmUserDir </> "backer" </> ("Desk1-" ++ backdropImage ++ ".pm")
      , fvwmUserDir </> "backdrops" </> (backdropImage ++ ".pm")
      , dataDir </> "backdrops" </> (backdropImage ++ ".pm")
      ]
  | backdropMode == "photo" || backdropMode == "aspect" =
      [ fvwmUserDir </> "backer" </> ("Desk1-" ++ backdropImage ++ ".pm")
      , fvwmUserDir </> "photos" </> (backdropImage ++ ".png")
      , dataDir </> "photos" </> (backdropImage ++ ".png")
      ]
  | otherwise = []

resolveBackdropPath :: FilePath -> FilePath -> String -> String -> IO (Maybe FilePath)
resolveBackdropPath fvwmUserDir dataDir backdropMode backdropImage =
  firstExistingPath (backdropCandidatePaths fvwmUserDir dataDir backdropMode backdropImage)

firstExistingPath :: [FilePath] -> IO (Maybe FilePath)
firstExistingPath [] = pure Nothing
firstExistingPath (candidate:rest) = do
  candidateExists <- doesFileExist candidate
  if candidateExists
    then pure (Just candidate)
    else firstExistingPath rest
