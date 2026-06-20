module NsCDE.Parse.Subpanels
  ( Subpanel(..)
  , SubpanelEntry(..)
  , loadSubpanels
  , renderSubpanelsEnv
  ) where

import Data.List (find)
import System.Directory (doesFileExist)
import System.FilePath ((</>))

import NsCDE.Foundation.Common (trim)
import NsCDE.Foundation.EnvFile (KeyValue)
import NsCDE.Foundation.Settings (lookupText)

data Subpanel = Subpanel
  { subpanelIndex :: Int
  , subpanelName :: String
  , subpanelWidth :: String
  , subpanelEnabled :: String
  , subpanelEntries :: [SubpanelEntry]
  } deriving (Eq, Show)

data SubpanelEntry = SubpanelEntry
  { subpanelEntryTitle :: String
  , subpanelEntryType :: String
  , subpanelEntryIcon :: String
  , subpanelEntryCommand :: String
  } deriving (Eq, Show)

loadSubpanels :: [KeyValue] -> IO [Subpanel]
loadSubpanels env = do
  maybePath <- resolveSubpanelFile env
  case maybePath of
    Nothing -> pure []
    Just subpanelPath -> do
      contents <- readFile subpanelPath
      pure (parseSubpanelsContents env contents)

renderSubpanelsEnv :: [Subpanel] -> [KeyValue]
renderSubpanelsEnv subpanels =
  ("NSCDE_SUBPANEL_COUNT", show enabledCount) : concatMap renderSubpanel [1 .. 20]
  where
    enabledCount =
      length
        [ subpanel
        | subpanel <- subpanels
        , subpanelEnabled subpanel == "1"
        , not (null (subpanelEntries subpanel))
        ]
    renderSubpanel index =
      case find ((== index) . subpanelIndex) subpanels of
        Just subpanel ->
          [ ("NSCDE_SUBPANEL_" ++ show index ++ "_NAME", subpanelName subpanel)
          , ("NSCDE_SUBPANEL_" ++ show index ++ "_WIDTH", subpanelWidth subpanel)
          , ("NSCDE_SUBPANEL_" ++ show index ++ "_ENABLED", subpanelEnabled subpanel)
          , ("NSCDE_SUBPANEL_" ++ show index ++ "_ENTRY_COUNT", show (length (subpanelEntries subpanel)))
          ]
          ++ concatMap (renderEntry index) (zip [1 :: Int ..] (subpanelEntries subpanel))
        Nothing ->
          [ ("NSCDE_SUBPANEL_" ++ show index ++ "_NAME", "")
          , ("NSCDE_SUBPANEL_" ++ show index ++ "_WIDTH", "160")
          , ("NSCDE_SUBPANEL_" ++ show index ++ "_ENABLED", "0")
          , ("NSCDE_SUBPANEL_" ++ show index ++ "_ENTRY_COUNT", "0")
          ]
    renderEntry subpanelId (entryIndex, entry) =
      [ ("NSCDE_SUBPANEL_" ++ show subpanelId ++ "_ENTRY_" ++ show entryIndex ++ "_TITLE", subpanelEntryTitle entry)
      , ("NSCDE_SUBPANEL_" ++ show subpanelId ++ "_ENTRY_" ++ show entryIndex ++ "_TYPE", subpanelEntryType entry)
      , ("NSCDE_SUBPANEL_" ++ show subpanelId ++ "_ENTRY_" ++ show entryIndex ++ "_ICON", subpanelEntryIcon entry)
      , ("NSCDE_SUBPANEL_" ++ show subpanelId ++ "_ENTRY_" ++ show entryIndex ++ "_COMMAND", subpanelEntryCommand entry)
      ]

resolveSubpanelFile :: [KeyValue] -> IO (Maybe FilePath)
resolveSubpanelFile env = do
  let homeDir = lookupText env "HOME" ""
      userDir = lookupText env "FVWM_USERDIR" (homeDir </> ".NsCDE")
      dataDir = lookupText env "NSCDE_DATADIR" ""
      candidates =
        [ userDir </> "Subpanels.actions"
        , dataDir </> "defaults" </> "Subpanels.actions"
        ]
  pickFirstExisting candidates

pickFirstExisting :: [FilePath] -> IO (Maybe FilePath)
pickFirstExisting [] = pure Nothing
pickFirstExisting (candidate:rest) = do
  exists <- doesFileExist candidate
  if exists
    then pure (Just candidate)
    else pickFirstExisting rest

parseSubpanelsContents :: [KeyValue] -> String -> [Subpanel]
parseSubpanelsContents env contents =
  foldl (applyLine env) [] (lines contents)

applyLine :: [KeyValue] -> [Subpanel] -> String -> [Subpanel]
applyLine env acc rawLine =
  case splitFields rawLine of
    (panelId:nameField:value:_) | nameField == "NAME" ->
      updateSubpanel (parsePanelId panelId) acc $ \subpanel ->
        subpanel {subpanelName = stripGtMarkers value}
    (panelId:widthField:value:_) | widthField == "WIDTH" ->
      updateSubpanel (parsePanelId panelId) acc $ \subpanel ->
        subpanel {subpanelWidth = trim value}
    (panelId:enabledField:value:_) | enabledField == "ENABLED" ->
      updateSubpanel (parsePanelId panelId) acc $ \subpanel ->
        subpanel {subpanelEnabled = trim value}
    (panelId:entryField:title:entryType:iconPath:commandParts) | entryField == "ENTRY" ->
      let translatedCommand = translateSubpanelCommand env (joinRest commandParts)
          entry =
            SubpanelEntry
              { subpanelEntryTitle = stripGtMarkers title
              , subpanelEntryType = trim entryType
              , subpanelEntryIcon = trim iconPath
              , subpanelEntryCommand = translatedCommand
              }
      in updateSubpanel (parsePanelId panelId) acc $ \subpanel ->
           subpanel {subpanelEntries = subpanelEntries subpanel ++ [entry]}
    _ -> acc

updateSubpanel :: Int -> [Subpanel] -> (Subpanel -> Subpanel) -> [Subpanel]
updateSubpanel index acc updateFn =
  let current =
        case find ((== index) . subpanelIndex) acc of
          Just subpanel -> subpanel
          Nothing -> defaultSubpanel index
      updated = updateFn current
  in updated : filter ((/= index) . subpanelIndex) acc

defaultSubpanel :: Int -> Subpanel
defaultSubpanel index =
  Subpanel
    { subpanelIndex = index
    , subpanelName = ""
    , subpanelWidth = "160"
    , subpanelEnabled = "0"
    , subpanelEntries = []
    }

parsePanelId :: String -> Int
parsePanelId panelId =
  case panelId of
    'S':rest ->
      case reads rest of
        [(index, "")] -> index
        _ -> 0
    _ -> 0

splitFields :: String -> [String]
splitFields rawLine
  | null trimmedLine = []
  | "#" `isPrefixOf` trimmedLine = []
  | otherwise = splitOnComma trimmedLine
  where
    trimmedLine = trim rawLine

splitOnComma :: String -> [String]
splitOnComma [] = [""]
splitOnComma (',':rest) = "" : splitOnComma rest
splitOnComma (char:rest) =
  case splitOnComma rest of
    [] -> [[char]]
    token:tokens -> (char : token) : tokens

joinRest :: [String] -> String
joinRest [] = ""
joinRest (firstField:rest) =
  foldl (\acc value -> acc ++ "," ++ value) firstField rest

stripGtMarkers :: String -> String
stripGtMarkers "" = ""
stripGtMarkers value
  | "$[gt." `isPrefixOf` value =
      let afterPrefix = drop (length ("$[gt." :: String)) value
      in case break (== ']') afterPrefix of
           (label, ']':rest) -> label ++ stripGtMarkers rest
           _ -> value
  | otherwise =
      let (prefix, suffix) = breakOnSubstring "$[gt." value
      in prefix ++ stripGtMarkers suffix

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

translateSubpanelCommand :: [KeyValue] -> String -> String
translateSubpanelCommand env rawCommand =
  let backend = lookupText env "NSCDE_BACKEND" "labwc"
      toolsDir = lookupText env "NSCDE_TOOLSDIR" ""
      rootDir = lookupText env "NSCDE_ROOT" ""
      terminal = lookupText env "NSCDE_LABWC_TERMINAL" "xterm"
      unescaped = replaceSubstring "\\\"" "\"" rawCommand
      strippedWrapper = stripFvwmWrapper unescaped
      withInfoStore = replaceInfoStore strippedWrapper
  in case backend of
       "labwc" -> translateLabwcCommand toolsDir rootDir terminal withInfoStore
       _ -> withInfoStore

stripFvwmWrapper :: String -> String
stripFvwmWrapper commandText =
  case stripPrefix "nscde_fvwmclnt " commandText of
    Just inner ->
      trimQuoted inner
    Nothing -> commandText

translateLabwcCommand :: FilePath -> FilePath -> String -> String -> String
translateLabwcCommand toolsDir rootDir terminal commandText =
  case () of
    _ | "f_ToggleFvwmModule FvwmScript StyleMgr" `isPrefixOf` commandText ->
          "nscde_labwc_stylemgr"
      | "f_ToggleFvwmModule FvwmScript Sysinfo" `isPrefixOf` commandText ->
          "nscde_labwc_sysinfo"
      | "f_ToggleFvwmModule FvwmScript NProcMgr" `isPrefixOf` commandText ->
          "nscde_labwc_nprocmgr"
      | "f_ToggleFvwmModule FvwmScript " `isPrefixOf` commandText ->
          ""
      | "Module FvwmScript " `isPrefixOf` commandText ->
          ""
      | "f_ToggleFvwmFunc ExecDialog" `isPrefixOf` commandText ->
          terminal ++ " -e sh -c 'echo \"Enter command:\"; read cmd; eval \"$cmd\"; read'"
      | "f_ToggleFvwmFunc GWM" `isPrefixOf` commandText ->
          "QT_QPA_PLATFORM=wayland " ++ (toolsDir </> "nscde_labwc_wsm")
      | "f_ToggleFvwmFunc WatchWinMgrErrors" `isPrefixOf` commandText ->
          terminal ++ " -e journalctl -f"
      | "f_ToggleFvwmFunc " `isPrefixOf` commandText ->
          ""
      | "f_DisplayURL " `isPrefixOf` commandText ->
          "xdg-open " ++ rootDir </> "share" </> "doc" </> "nscde" </> takeLastField commandText
      | otherwise ->
          commandText

takeLastField :: String -> String
takeLastField value =
  trimQuoted (reverse (takeWhile (/= ' ') (reverse value)))

replaceInfoStore :: String -> String
replaceInfoStore value =
  case breakOnSubstring "$[infostore." value of
    (prefix, "") -> prefix
    (prefix, suffix) ->
      let afterPrefix = drop (length ("$[infostore." :: String)) suffix
      in case break (== ']') afterPrefix of
           (name, ']':rest) ->
             prefix ++ "${NSCDE_INFOSTORE_" ++ name ++ "}" ++ replaceInfoStore rest
           _ -> value

trimQuoted :: String -> String
trimQuoted value =
  case trim value of
    '"':rest ->
      case reverse rest of
        '"':remaining -> reverse remaining
        _ -> '"' : rest
    trimmedValue -> trimmedValue

replaceSubstring :: String -> String -> String -> String
replaceSubstring needle replacement =
  go
  where
    go "" = ""
    go value
      | needle `isPrefixOf` value =
          replacement ++ go (drop (length needle) value)
      | otherwise =
          case value of
            next:rest -> next : go rest
            [] -> []

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
