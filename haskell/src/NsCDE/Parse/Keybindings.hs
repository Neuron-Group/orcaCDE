module NsCDE.Parse.Keybindings
  ( ParsedKeybinding(..)
  , loadParsedKeybindings
  , parseKeybindingsContents
  , resolveKeybindingFile
  ) where

import System.Directory (doesFileExist)
import System.FilePath ((</>))

import NsCDE.Foundation.Common (trim)
import NsCDE.Foundation.EnvFile (KeyValue)
import NsCDE.Foundation.Settings (lookupText)

data ParsedKeybinding = ParsedKeybinding
  { parsedKeyName :: String
  , parsedContext :: String
  , parsedModifier :: String
  , parsedAction :: String
  } deriving (Eq, Show)

loadParsedKeybindings :: [KeyValue] -> IO [ParsedKeybinding]
loadParsedKeybindings env = do
  maybePath <- resolveKeybindingFile env
  case maybePath of
    Nothing -> pure []
    Just path -> do
      contents <- readFile path
      pure (parseKeybindingsContents contents)

resolveKeybindingFile :: [KeyValue] -> IO (Maybe FilePath)
resolveKeybindingFile env = do
  let kbdSet = lookupText env "NSCDE_KBD_BIND_SET" "cua"
      fvwmUserDir = lookupText env "FVWM_USERDIR" (lookupText env "HOME" "" </> ".NsCDE")
      dataDir = lookupText env "NSCDE_DATADIR" ""
      candidates =
        [ fvwmUserDir </> ("Keybindings." ++ kbdSet)
        , dataDir </> "fvwm" </> ("Keybindings." ++ kbdSet)
        , dataDir </> "fvwm" </> "Keybindings.cua"
        ]
  pickFirstExisting candidates

pickFirstExisting :: [FilePath] -> IO (Maybe FilePath)
pickFirstExisting [] = pure Nothing
pickFirstExisting (candidate:rest) = do
  exists <- doesFileExist candidate
  if exists
    then pure (Just candidate)
    else pickFirstExisting rest

parseKeybindingsContents :: String -> [ParsedKeybinding]
parseKeybindingsContents contents =
  foldr collectLine [] (lines contents)

collectLine :: String -> [ParsedKeybinding] -> [ParsedKeybinding]
collectLine rawLine acc =
  case parseKeybindingLine rawLine of
    Just binding -> binding : acc
    Nothing -> acc

parseKeybindingLine :: String -> Maybe ParsedKeybinding
parseKeybindingLine rawLine =
  let stripped = trim rawLine
      rest0 =
        case stripped of
          ('#':_) -> ""
          "" -> ""
          _ -> stripped
  in if null rest0 || shouldSkip rest0
       then Nothing
       else do
         let rest1 =
               if "Silent " `isPrefixOf` rest0
                 then drop (length ("Silent " :: String)) rest0
                 else rest0
         rest2 <- stripPrefix "Key " rest1
         (keyName, rest3) <- nextField rest2
         (contextName, rest4) <- nextField rest3
         (modifierName, actionText) <- nextField rest4
         if null actionText
           then Nothing
           else Just ParsedKeybinding
             { parsedKeyName = keyName
             , parsedContext = contextName
             , parsedModifier = modifierName
             , parsedAction = actionText
             }

shouldSkip :: String -> Bool
shouldSkip value =
  or
    [ "Test " `isPrefixOf` value
    , "InfoStoreAdd" `isPrefixOf` value
    , "Silent PointerKey" `isPrefixOf` value
    ]

nextField :: String -> Maybe (String, String)
nextField value =
  case break (== ' ') value of
    ("", _) -> Nothing
    (_, "") -> Nothing
    (field, rest) -> Just (field, trim rest)

stripPrefix :: Eq a => [a] -> [a] -> Maybe [a]
stripPrefix [] value = Just value
stripPrefix _ [] = Nothing
stripPrefix (left:leftRest) (right:rightRest)
  | left == right = stripPrefix leftRest rightRest
  | otherwise = Nothing

isPrefixOf :: Eq a => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (left:leftRest) (right:rightRest) =
  left == right && isPrefixOf leftRest rightRest
