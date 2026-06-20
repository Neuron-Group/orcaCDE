module NsCDE.Parse.AppMenus
  ( loadAppMenuEntries
  , parseAppMenuContents
  , resolveUserAppMenusPath
  ) where

import Data.List (nubBy, sortOn)
import System.Directory (doesFileExist)
import System.FilePath ((</>))

import NsCDE.Domain.Menu (AppMenuEntry(..))
import NsCDE.Foundation.Common (trim)
import NsCDE.Foundation.EnvFile (KeyValue)
import NsCDE.Foundation.Settings (lookupText)

loadAppMenuEntries :: [KeyValue] -> IO [AppMenuEntry]
loadAppMenuEntries env = do
  systemEntries <- loadAppMenuFile (lookupText env "NSCDE_DATADIR" "" </> "defaults" </> "AppMenus.conf")
  userEntries <- loadAppMenuFile (resolveUserAppMenusPath env)
  pure (dedupeAppMenuEntries (systemEntries ++ userEntries))

resolveUserAppMenusPath :: [KeyValue] -> FilePath
resolveUserAppMenusPath env =
  lookupText env "FVWM_USERDIR" (lookupText env "HOME" "" </> ".NsCDE") </> "AppMenus.conf"

loadAppMenuFile :: FilePath -> IO [AppMenuEntry]
loadAppMenuFile "" = pure []
loadAppMenuFile path = do
  exists <- doesFileExist path
  if exists
    then do
      contents <- readFile path
      pure (parseAppMenuContents contents)
    else pure []

parseAppMenuContents :: String -> [AppMenuEntry]
parseAppMenuContents contents =
  foldr collectLine [] (lines contents)

collectLine :: String -> [AppMenuEntry] -> [AppMenuEntry]
collectLine rawLine acc =
  case parseAppMenuLine rawLine of
    Just entry -> entry : acc
    Nothing -> acc

parseAppMenuLine :: String -> Maybe AppMenuEntry
parseAppMenuLine rawLine
  | null trimmedLine = Nothing
  | "#" `isPrefixOf` trimmedLine = Nothing
  | otherwise = do
      (className, rest1) <- splitField trimmedLine
      (_, rest2) <- splitField rest1
      (rawLabel, action) <- splitField rest2
      let displayLabel = cleanLabel rawLabel
      if null displayLabel || null action
        then Nothing
        else Just AppMenuEntry
          { appMenuClass = className
          , appMenuRawLabel = rawLabel
          , appMenuDisplayLabel = displayLabel
          , appMenuAction = action
          , appMenuSortLine = trimmedLine
          }
  where
    trimmedLine = trim rawLine

splitField :: String -> Maybe (String, String)
splitField value =
  case break (== ',') value of
    (_, []) -> Nothing
    (field, _:rest) -> Just (field, rest)

dedupeAppMenuEntries :: [AppMenuEntry] -> [AppMenuEntry]
dedupeAppMenuEntries =
  nubBy sameRawLabel . sortOn sortKey
  where
    sameRawLabel left right = appMenuRawLabel left == appMenuRawLabel right
    sortKey entry = (appMenuRawLabel entry, appMenuSortLine entry)

cleanLabel :: String -> String
cleanLabel =
  trim . dropShortcutSuffix . stripGettextMarker

dropShortcutSuffix :: String -> String
dropShortcutSuffix =
  takeWhile (/= '\t')

stripGettextMarker :: String -> String
stripGettextMarker "" = ""
stripGettextMarker value
  | "$[gt." `isPrefixOf` value =
      let afterPrefix = drop (length ("$[gt." :: String)) value
      in case break (== ']') afterPrefix of
           (label, ']':rest) -> label ++ stripGettextMarker rest
           _ -> value
  | otherwise =
      let (prefix, suffix) = breakOnSubstring "$[gt." value
      in prefix ++ stripGettextMarker suffix

breakOnSubstring :: String -> String -> (String, String)
breakOnSubstring needle haystack =
  go [] haystack
  where
    go prefix remaining
      | needle `isPrefixOf` remaining = (reverse prefix, remaining)
      | null remaining = (reverse prefix, remaining)
      | otherwise =
          case remaining of
            next:rest -> go (next : prefix) rest
            [] -> (reverse prefix, remaining)

isPrefixOf :: Eq a => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (left:leftRest) (right:rightRest) =
  left == right && isPrefixOf leftRest rightRest
