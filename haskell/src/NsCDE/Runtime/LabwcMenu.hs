module NsCDE.Runtime.LabwcMenu
  ( publishLabwcMenuXml
  ) where

import Data.Char (isSpace)
import Data.List (find, nubBy, sortOn)
import System.Directory (createDirectoryIfMissing, doesFileExist, findExecutable, renameFile)
import System.Environment (getEnvironment)
import System.FilePath ((</>))

type KeyValue = (String, String)

data AppMenuEntry = AppMenuEntry
  { appMenuClass :: String
  , appMenuRawLabel :: String
  , appMenuDisplayLabel :: String
  , appMenuAction :: String
  , appMenuSortLine :: String
  }

publishLabwcMenuXml :: FilePath -> IO ()
publishLabwcMenuXml configDir = do
  env <- getEnvironment
  terminal <- resolveTerminal env
  appEntries <- loadAppMenuEntries env
  createDirectoryIfMissing True configDir
  writeAtomicFile (configDir </> "menu.xml") (renderMenuXml env terminal appEntries)

resolveTerminal :: [KeyValue] -> IO String
resolveTerminal env =
  case lookupText env "NSCDE_LABWC_TERMINAL" "" of
    "" -> firstAvailable ["weston-terminal", "xterm"]
    terminal -> pure terminal

firstAvailable :: [String] -> IO String
firstAvailable [] = pure "weston-terminal"
firstAvailable (candidate:rest) = do
  resolved <- findExecutable candidate
  case resolved of
    Just _ -> pure candidate
    Nothing -> firstAvailable rest

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
      pure (foldr collectLine [] (lines contents))
    else pure []

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
  nubBy sameRawLabel
    . sortOn (\entry -> (appMenuRawLabel entry, appMenuSortLine entry))
  where
    sameRawLabel left right = appMenuRawLabel left == appMenuRawLabel right

renderMenuXml :: [KeyValue] -> String -> [AppMenuEntry] -> String
renderMenuXml env terminal appEntries =
  unlines $
    [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    , "<openbox_menu xmlns=\"http://openbox.org/3.4/menu\">"
    , "  <menu id=\"root-menu\" label=\"NsCDE\">"
    , "    <item label=\"Terminal\">"
    , renderExecuteAction 6 terminal
    , "    </item>"
    , "    <separator label=\"Style\" />"
    , "    <item label=\"Style Manager\">"
    , renderExecuteAction 6 (renderWaylandQtCommand (toolsDir </> "nscde_labwc_stylemgr"))
    , "    </item>"
    , "    <menu id=\"style-managers-menu\" label=\"Style Managers\">"
    ] ++
    renderStyleManagerMenu toolsDir ++
    [ "    </menu>"
    , "    <separator label=\"Applications\" />"
    ] ++
    renderApplicationMenu appEntries terminal ++
    [ "    <separator label=\"Workspaces\" />"
    ] ++
    renderWorkspaceMenu workspaces ++
    [ "    <separator label=\"Session\" />"
    , "    <item label=\"System Action...\">"
    , renderExecuteAction 6 (renderWaylandQtCommand (toolsDir </> "nscde_labwc_sysaction"))
    , "    </item>"
    , "    <item label=\"Reconfigure labwc\">"
    , "      <action name=\"Reconfigure\" />"
    , "    </item>"
    , "    <item label=\"Exit labwc\">"
    , "      <action name=\"Exit\" />"
    , "    </item>"
    , "  </menu>"
    , "</openbox_menu>"
    ]
  where
    toolsDir = lookupText env "NSCDE_TOOLSDIR" ""
    workspaces = resolveWorkspaces env

renderStyleManagerMenu :: FilePath -> [String]
renderStyleManagerMenu toolsDir =
  concatMap renderStyleManagerItem styleManagers ++
  [ "    <separator />"
  , "    <item label=\"Icon Box\">"
  , renderExecuteAction 6 (renderWaylandQtCommand (toolsDir </> "nscde_labwc_iconbox"))
  , "    </item>"
  , "    <item label=\"System Information\">"
  , renderExecuteAction 6 (renderWaylandQtCommand (toolsDir </> "nscde_labwc_sysinfo"))
  , "    </item>"
  , "    <separator />"
  , "    <item label=\"System Action...\">"
  , renderExecuteAction 6 (renderWaylandQtCommand (toolsDir </> "nscde_labwc_sysaction"))
  , "    </item>"
  ]
  where
    styleManagers =
      [ ("Color Manager", "nscde_labwc_colormgr")
      , ("Font Manager", "nscde_labwc_fontmgr")
      , ("Backdrop Manager", "nscde_labwc_backdropmgr")
      , ("Window Manager", "nscde_labwc_windowmgr")
      , ("Workspace Manager", "nscde_labwc_wsm")
      ]
    renderStyleManagerItem (label, executable) =
      [ "    <item label=\"" ++ escapeXml label ++ "\">"
      , renderExecuteAction 6 (renderWaylandQtCommand (toolsDir </> executable))
      , "    </item>"
      ]

renderApplicationMenu :: [AppMenuEntry] -> String -> [String]
renderApplicationMenu appEntries terminal =
  snd (foldl appendMenuItem ("", []) appEntries)
  where
    appendMenuItem (previousClass, rendered) entry =
      case mapAppMenuAction terminal (appMenuAction entry) of
        Nothing -> (previousClass, rendered)
        Just command ->
          let separator =
                if null previousClass || previousClass == appMenuClass entry
                  then []
                  else ["    <separator />"]
              itemLines =
                [ "    <item label=\"" ++ escapeXml (appMenuDisplayLabel entry) ++ "\">"
                , renderExecuteAction 6 command
                , "    </item>"
                ]
          in (appMenuClass entry, rendered ++ separator ++ itemLines)

mapAppMenuAction :: String -> String -> Maybe String
mapAppMenuAction terminal action
  | action == "f_WideTerm" = Just terminal
  | "Exec exec " `isPrefixOf` action = Just (trimQuoted (drop (length ("Exec exec " :: String)) action))
  | "Module FvwmScript " `isPrefixOf` action = Nothing
  | "f_ToggleFvwmModule FvwmScript " `isPrefixOf` action = Nothing
  | "f_ToggleFvwmFunc " `isPrefixOf` action = Nothing
  | "f_ToggleExecWindow " `isPrefixOf` action = Nothing
  | "f_FvwmLogMgmt " `isPrefixOf` action = Nothing
  | otherwise = Nothing

renderWorkspaceMenu :: [String] -> [String]
renderWorkspaceMenu workspaces =
  concatMap renderWorkspaceItem (zip [1 :: Int ..] workspaces)
  where
    renderWorkspaceItem (index, name) =
      [ "    <item label=\"Workspace " ++ escapeXml name ++ "\">"
      , "      <action name=\"GoToDesktop\" to=\"" ++ show index ++ "\" />"
      , "    </item>"
      ]

renderExecuteAction :: Int -> String -> String
renderExecuteAction indent command =
  replicate indent ' '
    ++ "<action name=\"Execute\"><command>"
    ++ escapeXml command
    ++ "</command></action>"

renderWaylandQtCommand :: FilePath -> String
renderWaylandQtCommand target =
  "sh -c " ++ shellQuote ("QT_QPA_PLATFORM=wayland " ++ target)

resolveWorkspaces :: [KeyValue] -> [String]
resolveWorkspaces env =
  case splitCommaList workspaceText of
    [] -> ["One", "Two", "Three", "Four"]
    names -> names
  where
    workspaceText = lookupText env "NSCDE_WORKSPACES" (lookupText env "NSCDE_LABWC_WORKSPACES" "")

writeAtomicFile :: FilePath -> String -> IO ()
writeAtomicFile path contents = do
  let tmpPath = path ++ ".tmp"
  writeFile tmpPath contents
  renameFile tmpPath path

lookupText :: [KeyValue] -> String -> String -> String
lookupText env key fallback =
  case find ((== key) . fst) env of
    Just (_, value) -> value
    Nothing -> fallback

cleanLabel :: String -> String
cleanLabel =
  trim
    . dropShortcutSuffix
    . stripGettextMarker

dropShortcutSuffix :: String -> String
dropShortcutSuffix value =
  takeWhile (/= '\t') value

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
      | otherwise = go (head remaining : prefix) (tail remaining)

trimQuoted :: String -> String
trimQuoted value =
  case trim value of
    '"':rest ->
      case reverse rest of
        '"':remaining -> reverse remaining
        _ -> '"' : rest
    trimmedValue -> trimmedValue

splitCommaList :: String -> [String]
splitCommaList raw =
  filter (not . null) (map trim (splitOnComma raw))

splitOnComma :: String -> [String]
splitOnComma "" = [""]
splitOnComma value =
  case break (== ',') value of
    (chunk, []) -> [chunk]
    (chunk, _:rest) -> chunk : splitOnComma rest

trim :: String -> String
trim = dropWhileEnd isSpace . dropWhile isSpace

dropWhileEnd :: (a -> Bool) -> [a] -> [a]
dropWhileEnd predicate = reverse . dropWhile predicate . reverse

escapeXml :: String -> String
escapeXml =
  concatMap escapeChar
  where
    escapeChar '&' = "&amp;"
    escapeChar '<' = "&lt;"
    escapeChar '>' = "&gt;"
    escapeChar '"' = "&quot;"
    escapeChar '\'' = "&apos;"
    escapeChar ch = [ch]

shellQuote :: String -> String
shellQuote value =
  "'" ++ concatMap escapeChar value ++ "'"
  where
    escapeChar '\'' = "'\"'\"'"
    escapeChar ch = [ch]

isPrefixOf :: Eq a => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (left:leftRest) (right:rightRest) =
  left == right && isPrefixOf leftRest rightRest
