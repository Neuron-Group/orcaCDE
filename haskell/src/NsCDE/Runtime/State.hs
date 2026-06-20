module NsCDE.Runtime.State
  ( RuntimeState(..)
  , fallbackCommand
  , fallbackQuery
  , handleCompatCommandLine
  , handleRuntimeCommand
  , loadRuntimeState
  , writeCompatibilityOutputs
  , queryTopicEntries
  , ensureCompatibilityFifos
  ) where

import Control.Monad (unless, when)
import Data.Bits ((.|.))
import Data.List (intercalate)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))
import System.IO.Error (catchIOError)
import System.Posix.Files (createNamedPipe, fileExist, getFileStatus, isNamedPipe, ownerReadMode, ownerWriteMode, removeLink)
import System.Posix.IO (OpenFileFlags(..), OpenMode(..), closeFd, defaultFileFlags, fdWrite, openFd)
import System.Posix.Types (FileMode)
import System.Process (rawSystem)

import NsCDE.Domain.Runtime
import NsCDE.Foundation.Common (splitCommaList, writeAtomicFile)
import NsCDE.Foundation.EnvFile (KeyValue, readEnvFileIfExists, renderEnvFile)
import NsCDE.Foundation.Paths
import NsCDE.Foundation.Settings (lookupText)
import NsCDE.Parse.PaletteDp (loadPaletteEntries)
import NsCDE.Parse.Subpanels (loadSubpanels, renderSubpanelsEnv)
import NsCDE.Policy.PanelLayout (emitPanelLayout, loadStaticPanelProfile)

data RuntimeState = RuntimeState
  { runtimeBackendName :: String
  , runtimeVersionString :: String
  , runtimeRootDir :: FilePath
  , runtimeDataDir :: FilePath
  , runtimeToolsDir :: FilePath
  , runtimeFvwmUserDir :: FilePath
  , runtimeThemeName :: String
  , runtimeWorkspaces :: [String]
  , runtimeCurrentWorkspace :: String
  , runtimePaletteFile :: FilePath
  , runtimePanelLayoutExternal :: Bool
  , runtimeLabwcConfigDir :: FilePath
  , runtimeWaylandDisplay :: String
  , runtimeDisplayName :: String
  , runtimePanelLayoutEntries :: [KeyValue]
  , runtimeSubpanelEntries :: [KeyValue]
  , runtimePaletteEntries :: [KeyValue]
  , runtimeCapabilityEntries :: [KeyValue]
  , runtimeFpVariant :: String
  , runtimePaths :: RuntimePaths
  } deriving (Eq, Show)

loadRuntimeState :: [KeyValue] -> IO RuntimeState
loadRuntimeState env = do
  let paths = resolveRuntimePaths env
      homeDir = lookupText env "HOME" ""
      rootDir = lookupText env "NSCDE_ROOT" ""
      dataDir =
        lookupText env "NSCDE_DATADIR" $
          if null rootDir
            then ""
            else rootDir </> "share" </> "NsCDE"
      backendName = lookupText env "NSCDE_BACKEND" "labwc"
      workspaceNames =
        case splitCommaList (lookupText env "NSCDE_WORKSPACES" (lookupText env "NSCDE_LABWC_WORKSPACES" "One,Two,Three,Four")) of
          [] -> ["One", "Two", "Three", "Four"]
          names -> names
      currentWorkspace =
        let fallbackWorkspace =
              case workspaceNames of
                firstWorkspace:_ -> firstWorkspace
                [] -> "One"
        in lookupText env "NSCDE_CURRENT_WORKSPACE" (lookupText env "NSCDE_LABWC_CURRENT_WORKSPACE" fallbackWorkspace)
  panelLayoutEntries <- loadPanelLayoutEntries env paths
  subpanelEntries <- fmap renderSubpanelsEnv (loadSubpanels env)
  paletteColors <- loadPaletteEntries (lookupText env "NSCDE_PALETTE_FILE" "")
  fpVariant <- loadFrontPanelVariant paths
  pure RuntimeState
    { runtimeBackendName = backendName
    , runtimeVersionString = lookupText env "NSCDE_VERSION" "unknown"
    , runtimeRootDir = rootDir
    , runtimeDataDir = dataDir
    , runtimeToolsDir = lookupText env "NSCDE_TOOLSDIR" ""
    , runtimeFvwmUserDir = lookupText env "FVWM_USERDIR" (homeDir </> ".NsCDE")
    , runtimeThemeName = lookupText env "NSCDE_THEME_NAME" (lookupText env "NSCDE_LABWC_THEME_NAME" "NsCDE-Stage1")
    , runtimeWorkspaces = workspaceNames
    , runtimeCurrentWorkspace = currentWorkspace
    , runtimePaletteFile = lookupText env "NSCDE_PALETTE_FILE" ""
    , runtimePanelLayoutExternal = lookupText env "NSCDE_PANEL_LAYOUT_EXTERNAL" "0" == "1"
    , runtimeLabwcConfigDir = lookupText env "NSCDE_LABWC_CONFIG_DIR" ""
    , runtimeWaylandDisplay = lookupText env "WAYLAND_DISPLAY" ""
    , runtimeDisplayName = lookupText env "DISPLAY" ""
    , runtimePanelLayoutEntries = panelLayoutEntries
    , runtimeSubpanelEntries = subpanelEntries
    , runtimePaletteEntries = zipPaletteEntries paletteColors
    , runtimeCapabilityEntries = capabilityEntries backendName
    , runtimeFpVariant = fpVariant
    , runtimePaths = paths
    }

writeCompatibilityOutputs :: RuntimeState -> IO ()
writeCompatibilityOutputs runtimeState = do
  let paths = runtimePaths runtimeState
  createDirectoryIfMissing True (runtimeStateDir paths)
  writeEnvFile (runtimeSessionFile paths) (sessionEntries runtimeState)
  unless (null (runtimePanelLayoutEntries runtimeState)) $
    writeEnvFile (runtimePanelLayoutFile paths) (runtimePanelLayoutEntries runtimeState)
  writeEnvFile (runtimePanelFile paths) (panelEntries runtimeState)
  writeEnvFile (runtimeWorkspacesFile paths) (workspacesEntries runtimeState)
  writeEnvFile (runtimePagerFile paths) (pagerEntries runtimeState)
  writeEnvFile (runtimeSubpanelsFile paths) (runtimeSubpanelEntries runtimeState)
  writeEnvFile (runtimeCapabilitiesFile paths) (runtimeCapabilityEntries runtimeState)
  windowsExist <- doesFileExist (runtimeWindowsFile paths)
  unless windowsExist $
    writeEnvFile (runtimeWindowsFile paths) initialWindowsEntries
  taskdExist <- doesFileExist (runtimeTaskdFile paths)
  unless taskdExist $
    writeEnvFile (runtimeTaskdFile paths) initialTaskEntries

ensureCompatibilityFifos :: RuntimeState -> IO ()
ensureCompatibilityFifos runtimeState = do
  let paths = runtimePaths runtimeState
  createDirectoryIfMissing True (runtimeStateDir paths)
  mapM_ ensureFifo
    [ runtimeCommandFifo paths
    , runtimePagerFifo paths
    , runtimeToplevelFifo paths
    ]

handleRuntimeCommand :: RuntimeCommand -> RuntimeState -> IO (RuntimeState, String)
handleRuntimeCommand command runtimeState =
  case command of
    CommandWorkspaceSwitch workspaceName ->
      if workspaceName `elem` runtimeWorkspaces runtimeState
        then do
          let updatedState = runtimeState {runtimeCurrentWorkspace = workspaceName}
          writeWorkspaceOutputs updatedState
          forwarded <- writeCompatCommand (runtimePagerFifo (runtimePaths updatedState)) ("switch_workspace:" ++ workspaceName)
          pure (updatedState, bridgeMessage forwarded "workspace updated")
        else pure (runtimeState, "workspace not found")
    CommandWorkspaceRename oldWorkspace newWorkspace ->
      if null newWorkspace || oldWorkspace == newWorkspace || oldWorkspace `notElem` runtimeWorkspaces runtimeState
        then pure (runtimeState, "workspace rename skipped")
        else do
          let renamedWorkspaces = map (\workspaceName -> if workspaceName == oldWorkspace then newWorkspace else workspaceName) (runtimeWorkspaces runtimeState)
              renamedCurrent =
                if runtimeCurrentWorkspace runtimeState == oldWorkspace
                  then newWorkspace
                  else runtimeCurrentWorkspace runtimeState
              updatedState =
                runtimeState
                  { runtimeWorkspaces = renamedWorkspaces
                  , runtimeCurrentWorkspace = renamedCurrent
                  }
          writeWorkspaceOutputs updatedState
          pure (updatedState, "workspace renamed")
    CommandWindow windowCommand windowId -> do
      forwarded <- writeCompatCommand (runtimeToplevelFifo (runtimePaths runtimeState)) (renderWindowCompat windowCommand windowId)
      pure (runtimeState, bridgeMessage forwarded "window command forwarded")
    CommandReload -> do
      reloadBackend runtimeState
      pure (runtimeState, "reload requested")

handleCompatCommandLine :: String -> RuntimeState -> IO (RuntimeState, String)
handleCompatCommandLine rawLine runtimeState =
  case parseCompatCommandLine rawLine of
    Just command -> handleRuntimeCommand command runtimeState
    Nothing -> pure (runtimeState, "ignored")

queryTopicEntries :: RuntimeState -> RuntimeTopic -> IO [KeyValue]
queryTopicEntries runtimeState topic =
  case topic of
    TopicSession -> pure (sessionEntries runtimeState)
    TopicPanel -> pure (panelEntries runtimeState)
    TopicPanelLayout ->
      if null (runtimePanelLayoutEntries runtimeState)
        then readEnvFileIfExists (runtimePanelLayoutFile (runtimePaths runtimeState))
        else pure (runtimePanelLayoutEntries runtimeState)
    TopicWorkspaces -> pure (workspacesEntries runtimeState)
    TopicSubpanels -> pure (runtimeSubpanelEntries runtimeState)
    TopicPager -> pure (pagerEntries runtimeState)
    TopicCapabilities -> pure (runtimeCapabilityEntries runtimeState)
    TopicWindows -> loadOrDefault (runtimeWindowsFile (runtimePaths runtimeState)) initialWindowsEntries
    TopicTaskd -> loadOrDefault (runtimeTaskdFile (runtimePaths runtimeState)) initialTaskEntries

fallbackQuery :: [KeyValue] -> RuntimeTopic -> IO [KeyValue]
fallbackQuery env topic = do
  runtimeState <- loadRuntimeState env
  queryTopicEntries runtimeState topic

fallbackCommand :: [KeyValue] -> RuntimeCommand -> IO Bool
fallbackCommand env command =
  let paths = resolveRuntimePaths env
  in case command of
       CommandWorkspaceSwitch workspaceName ->
         writeCompatCommand (runtimeCommandFifo paths) ("switch_workspace:" ++ workspaceName)
       CommandWorkspaceRename oldWorkspace newWorkspace ->
         writeCompatCommand (runtimeCommandFifo paths) ("rename_workspace:" ++ oldWorkspace ++ ":" ++ newWorkspace)
       CommandReload ->
         writeCompatCommand (runtimeCommandFifo paths) "reload"
       CommandWindow windowCommand windowId ->
         writeCompatCommand (runtimeToplevelFifo paths) (renderWindowCompat windowCommand windowId)

loadPanelLayoutEntries :: [KeyValue] -> RuntimePaths -> IO [KeyValue]
loadPanelLayoutEntries env paths
  | lookupText env "NSCDE_PANEL_LAYOUT_EXTERNAL" "0" == "1" =
      readEnvFileIfExists (runtimePanelLayoutFile paths)
  | otherwise =
      case lookupText env "NSCDE_STATIC_PANEL_LAYOUT_FILE" "" of
        "" -> readEnvFileIfExists (runtimePanelLayoutFile paths)
        staticPath -> do
          staticExists <- doesFileExist staticPath
          if staticExists
            then do
              profile <- loadStaticPanelProfile staticPath
              pure (emitPanelLayout profile)
            else readEnvFileIfExists (runtimePanelLayoutFile paths)

loadFrontPanelVariant :: RuntimePaths -> IO String
loadFrontPanelVariant paths = do
  styleEntries <- readEnvFileIfExists (runtimeStyleFile paths)
  pure $
    case lookupText styleEntries "NSCDE_FP_VARIANT" "8" of
      "5" -> "5"
      _ -> "8"

sessionEntries :: RuntimeState -> [KeyValue]
sessionEntries runtimeState =
  [ ("NSCDE_BACKEND", runtimeBackendName runtimeState)
  , ("NSCDE_VERSION", runtimeVersionString runtimeState)
  , ("NSCDE_LABWC_CONFIG_DIR", runtimeLabwcConfigDir runtimeState)
  , ("WAYLAND_DISPLAY", runtimeWaylandDisplay runtimeState)
  , ("DISPLAY", runtimeDisplayName runtimeState)
  , ("NSCDE_SESSION_COMMAND_FIFO", runtimeCommandFifo (runtimePaths runtimeState))
  ]

panelEntries :: RuntimeState -> [KeyValue]
panelEntries runtimeState =
  [ ("NSCDE_BACKEND", runtimeBackendName runtimeState)
  , ("NSCDE_THEME_NAME", runtimeThemeName runtimeState)
  , ("NSCDE_WORKSPACES", renderWorkspaceList (runtimeWorkspaces runtimeState))
  , ("NSCDE_CURRENT_WORKSPACE", runtimeCurrentWorkspace runtimeState)
  , ("NSCDE_SESSION_COMMAND_FIFO", runtimeCommandFifo (runtimePaths runtimeState))
  , ("NSCDE_FP_VARIANT", runtimeFpVariant runtimeState)
  ] ++ runtimePaletteEntries runtimeState

workspacesEntries :: RuntimeState -> [KeyValue]
workspacesEntries runtimeState =
  [ ("NSCDE_WORKSPACES", renderWorkspaceList (runtimeWorkspaces runtimeState))
  , ("NSCDE_WORKSPACE_COUNT", show (length (runtimeWorkspaces runtimeState)))
  , ("NSCDE_CURRENT_WORKSPACE", runtimeCurrentWorkspace runtimeState)
  , ("NSCDE_PAGER_COMMAND_FIFO", runtimePagerFifo (runtimePaths runtimeState))
  ]

pagerEntries :: RuntimeState -> [KeyValue]
pagerEntries runtimeState =
  [ ("NSCDE_PAGER_WORKSPACES", renderWorkspaceList (runtimeWorkspaces runtimeState))
  , ("NSCDE_PAGER_CURRENT", runtimeCurrentWorkspace runtimeState)
  , ("NSCDE_PAGER_COUNT", show (length (runtimeWorkspaces runtimeState)))
  , ("NSCDE_PAGER_INDEX", show (workspaceIndex runtimeState))
  , ("NSCDE_PAGER_COMMAND_FIFO", runtimePagerFifo (runtimePaths runtimeState))
  ]

initialWindowsEntries :: [KeyValue]
initialWindowsEntries =
  [ ("NSCDE_WINDOW_COUNT", "0")
  , ("NSCDE_FOCUSED_WINDOW", "")
  ]

initialTaskEntries :: [KeyValue]
initialTaskEntries =
  [ ("NSCDE_TASK_COUNT", "0")
  , ("NSCDE_TASK_FOCUSED", "")
  ]

capabilityEntries :: String -> [KeyValue]
capabilityEntries backendName =
  case backendName of
    "labwc" ->
      map (`pairCapability` "1")
        [ "supports-server-side-decoration-control"
        , "supports-live-theme-reload"
        , "supports-workspace-switch"
        , "supports-layer-shell"
        , "supports-foreign-toplevel"
        ]
    _ ->
      map (`pairCapability` "1")
        [ "supports-pages"
        , "supports-server-side-decoration-control"
        , "supports-live-theme-reload"
        , "supports-window-icons-as-separate-objects"
        , "supports-fvwm-commands"
        ]

pairCapability :: String -> String -> KeyValue
pairCapability = (,)

zipPaletteEntries :: [String] -> [KeyValue]
zipPaletteEntries colors =
  [ ("NSCDE_PALETTE_" ++ show index, color)
  | (index, color) <- zip [1 :: Int ..] colors
  ]

renderWorkspaceList :: [String] -> String
renderWorkspaceList =
  intercalate ","

workspaceIndex :: RuntimeState -> Int
workspaceIndex runtimeState =
  case findIndex 1 (runtimeWorkspaces runtimeState) of
    Just index -> index
    Nothing -> 0
  where
    findIndex _ [] = Nothing
    findIndex index (workspaceName:rest)
      | workspaceName == runtimeCurrentWorkspace runtimeState = Just index
      | otherwise = findIndex (index + 1) rest

writeWorkspaceOutputs :: RuntimeState -> IO ()
writeWorkspaceOutputs runtimeState = do
  let paths = runtimePaths runtimeState
  writeEnvFile (runtimePanelFile paths) (panelEntries runtimeState)
  writeEnvFile (runtimeWorkspacesFile paths) (workspacesEntries runtimeState)
  writeEnvFile (runtimePagerFile paths) (pagerEntries runtimeState)

writeEnvFile :: FilePath -> [KeyValue] -> IO ()
writeEnvFile targetPath entries =
  writeAtomicFile targetPath (renderEnvFile entries)

loadOrDefault :: FilePath -> [KeyValue] -> IO [KeyValue]
loadOrDefault targetPath fallbackEntries = do
  entries <- readEnvFileIfExists targetPath
  pure $
    if null entries
      then fallbackEntries
      else entries

ensureFifo :: FilePath -> IO ()
ensureFifo targetPath = do
  exists <- fileExist targetPath
  if exists
    then do
      fileStatus <- getFileStatus targetPath
      unless (isNamedPipe fileStatus) $ do
        removeLink targetPath
        createNamedPipe targetPath (ownerReadMode `unionMode` ownerWriteMode)
    else createNamedPipe targetPath (ownerReadMode `unionMode` ownerWriteMode)

writeCompatCommand :: FilePath -> String -> IO Bool
writeCompatCommand targetPath commandLine =
  catchIOError
    (do
      fd <- openFd targetPath WriteOnly defaultFileFlags {nonBlock = True}
      _ <- fdWrite fd (commandLine ++ "\n")
      closeFd fd
      pure True)
    (\_ -> pure False)

reloadBackend :: RuntimeState -> IO ()
reloadBackend runtimeState =
  case runtimeBackendName runtimeState of
    "labwc" -> do
      _ <- rawSystem "pkill" ["-HUP", "-x", "labwc"]
      pure ()
    _ -> pure ()

bridgeMessage :: Bool -> String -> String
bridgeMessage forwarded successMessage =
  if forwarded
    then successMessage
    else successMessage ++ " (compat bridge unavailable)"

renderWindowCompat :: RuntimeWindowCommand -> Int -> String
renderWindowCompat windowCommand windowId =
  case windowCommand of
    WindowActivate -> "activate:" ++ show windowId
    WindowClose -> "close:" ++ show windowId
    WindowMinimize -> "minimize:" ++ show windowId
    WindowRestore -> "restore:" ++ show windowId
    WindowMaximize -> "maximize:" ++ show windowId

parseCompatCommandLine :: String -> Maybe RuntimeCommand
parseCompatCommandLine rawLine =
  case wordsAndValue rawLine of
    ("reload", _) -> Just CommandReload
    ("switch_workspace", workspaceName) -> Just (CommandWorkspaceSwitch workspaceName)
    ("rename_workspace", renameValue) ->
      case splitOnce ':' renameValue of
        Just (oldWorkspace, newWorkspace) -> Just (CommandWorkspaceRename oldWorkspace newWorkspace)
        Nothing -> Nothing
    ("focus_window", windowIdText) ->
      parseWindowCompat WindowActivate windowIdText
    ("activate", windowIdText) ->
      parseWindowCompat WindowActivate windowIdText
    ("close", windowIdText) ->
      parseWindowCompat WindowClose windowIdText
    ("minimize", windowIdText) ->
      parseWindowCompat WindowMinimize windowIdText
    ("restore", windowIdText) ->
      parseWindowCompat WindowRestore windowIdText
    ("maximize", windowIdText) ->
      parseWindowCompat WindowMaximize windowIdText
    _ -> Nothing
  where
    wordsAndValue lineText =
      case splitOnce ':' lineText of
        Just pair -> pair
        Nothing -> (lineText, "")

parseWindowCompat :: RuntimeWindowCommand -> String -> Maybe RuntimeCommand
parseWindowCompat windowCommand windowIdText =
  case reads windowIdText of
    [(windowId, "")] -> Just (CommandWindow windowCommand windowId)
    _ -> Nothing

splitOnce :: Char -> String -> Maybe (String, String)
splitOnce separator value =
  case break (== separator) value of
    (_, "") -> Nothing
    (left, _:right) -> Just (left, right)

unionMode :: FileMode -> FileMode -> FileMode
unionMode = (.|.)
