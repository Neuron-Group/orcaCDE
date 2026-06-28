module NsCDE.Runtime.State
  ( RuntimeState(..)
  , RuntimeTransition
  , performRuntimeTransitionEffects
  , runtimeTransitionMessage
  , runtimeTransitionState
  , runtimeTransitionTopics
  , fallbackCommand
  , fallbackQuery
  , handleCompatCommandLine
  , handleRuntimeCommand
  , loadRuntimeState
  , writeCompatibilityOutputs
  , queryTopicEntries
  , ensureCompatibilityFifos
  ) where

import Control.Monad (unless)
import Data.Bits ((.|.))
import Data.List (intercalate)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))
import System.IO.Error (catchIOError)
import System.Posix.Files (createNamedPipe, fileExist, getFileStatus, isNamedPipe, ownerReadMode, ownerWriteMode, removeLink)
import System.Posix.IO (OpenFileFlags(..), OpenMode(..), closeFd, defaultFileFlags, fdWrite, openFd)
import System.Posix.Types (FileMode)
import System.Process (createProcess, proc, waitForProcess)

import NsCDE.Domain.Runtime
import NsCDE.Domain.Style
  ( StyleState
  , styleFpVariant
  )
import NsCDE.Foundation.Common (splitCommaList, writeAtomicFile)
import NsCDE.Foundation.EnvFile
  ( KeyValue
  , parseEnvContents
  , readEnvFileIfExists
  , renderEnvFile
  )
import NsCDE.Foundation.Paths
import NsCDE.Foundation.Settings (lookupText)
import NsCDE.Policy.Backdrop (buildBackdropPlan, renderBackdropEntries)
import qualified NsCDE.Policy.StyleApply as StyleApply
import NsCDE.Parse.Subpanels (loadSubpanels, renderSubpanelsEnv)
import NsCDE.Policy.PanelLayout (emitPanelLayout, loadStaticPanelProfile)
import qualified NsCDE.Store.BackdropState as BackdropStore
import qualified NsCDE.Store.StyleState as StyleStore

data RuntimeEffect
  = RuntimeEffectCompatCommand FilePath String
  | RuntimeEffectApplyResolvedStyle StyleStore.ResolvedStyleState
  | RuntimeEffectReloadBackend

data RuntimeTransition = RuntimeTransition
  { runtimeTransitionState :: RuntimeState
  , runtimeTransitionTopics :: [RuntimeTopic]
  , runtimeTransitionEffects :: [RuntimeEffect]
  , runtimeTransitionMessage :: String
  }

data RuntimeState = RuntimeState
  { runtimeBackendName :: String
  , runtimeVersionString :: String
  , runtimeHomeDir :: FilePath
  , runtimeRootDir :: FilePath
  , runtimeDataDir :: FilePath
  , runtimeToolsDir :: FilePath
  , runtimeFvwmUserDir :: FilePath
  , runtimeXdgConfigHome :: FilePath
  , runtimeXdgCacheHome :: FilePath
  , runtimeXdgDataHome :: FilePath
  , runtimeXdgRuntimeDir :: FilePath
  , runtimeSystemPath :: FilePath
  , runtimeThemeName :: String
  , runtimeWorkspaces :: [String]
  , runtimeCurrentWorkspace :: String
  , runtimePaletteFallbackFile :: FilePath
  , runtimePaletteFile :: FilePath
  , runtimePanelLayoutExternal :: Bool
  , runtimeLabwcConfigDir :: FilePath
  , runtimeLabwcKeybindXmlFile :: FilePath
  , runtimeLabwcTitleFontName :: String
  , runtimeLabwcTitleFontSize :: String
  , runtimeLabwcTitleFontSlant :: String
  , runtimeLabwcTitleFontWeight :: String
  , runtimeWaylandDisplay :: String
  , runtimeDisplayName :: String
  , runtimePanelLayoutEntries :: [KeyValue]
  , runtimeSubpanelEntries :: [KeyValue]
  , runtimeBackdropEntries :: [KeyValue]
  , runtimeWindowsEntries :: [KeyValue]
  , runtimeTaskEntries :: [KeyValue]
  , runtimePaletteEntries :: [KeyValue]
  , runtimeCapabilityEntries :: [KeyValue]
  , runtimeFpVariant :: String
  , runtimeStyleState :: StyleState
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
      paletteFallbackFile = lookupText env "NSCDE_PALETTE_FILE" ""
  panelLayoutEntries <- loadPanelLayoutEntries env paths
  subpanelEntries <- fmap renderSubpanelsEnv (loadSubpanels env)
  resolvedStyle <- StyleStore.readResolvedStyleState paths paletteFallbackFile
  storedWindowsEntries <- readEnvFileIfExists (runtimeWindowsFile paths)
  let initialWindows =
        if null storedWindowsEntries
          then initialWindowsEntries
          else storedWindowsEntries
      initialTasks =
        deriveTaskEntries (runtimeToplevelFifo paths) initialWindows
  let baseState =
        RuntimeState
          { runtimeBackendName = backendName
          , runtimeVersionString = lookupText env "NSCDE_VERSION" "unknown"
          , runtimeHomeDir = homeDir
          , runtimeRootDir = rootDir
          , runtimeDataDir = dataDir
          , runtimeToolsDir = lookupText env "NSCDE_TOOLSDIR" ""
          , runtimeFvwmUserDir = lookupText env "FVWM_USERDIR" (homeDir </> ".NsCDE")
          , runtimeXdgConfigHome = lookupText env "XDG_CONFIG_HOME" (homeDir </> ".config")
          , runtimeXdgCacheHome = lookupText env "XDG_CACHE_HOME" (homeDir </> ".cache")
          , runtimeXdgDataHome = lookupText env "XDG_DATA_HOME" (homeDir </> ".local" </> "share")
          , runtimeXdgRuntimeDir = lookupText env "XDG_RUNTIME_DIR" ""
          , runtimeSystemPath = lookupText env "PATH" ""
          , runtimeThemeName = lookupText env "NSCDE_THEME_NAME" (lookupText env "NSCDE_LABWC_THEME_NAME" "NsCDE-Stage1")
          , runtimeWorkspaces = workspaceNames
          , runtimeCurrentWorkspace = currentWorkspace
          , runtimePaletteFallbackFile = paletteFallbackFile
          , runtimePaletteFile = StyleStore.resolvedStylePaletteFile resolvedStyle
          , runtimePanelLayoutExternal = lookupText env "NSCDE_PANEL_LAYOUT_EXTERNAL" "0" == "1"
          , runtimeLabwcConfigDir = lookupText env "NSCDE_LABWC_CONFIG_DIR" ""
          , runtimeLabwcKeybindXmlFile =
              lookupText env "NSCDE_LABWC_KEYBIND_XML_FILE" (runtimeStateDir paths </> "labwc-keybinds.xml")
          , runtimeLabwcTitleFontName = lookupText env "NSCDE_LABWC_TITLE_FONT_NAME" "Sans"
          , runtimeLabwcTitleFontSize = lookupText env "NSCDE_LABWC_TITLE_FONT_SIZE" "10"
          , runtimeLabwcTitleFontSlant = lookupText env "NSCDE_LABWC_TITLE_FONT_SLANT" "normal"
          , runtimeLabwcTitleFontWeight = lookupText env "NSCDE_LABWC_TITLE_FONT_WEIGHT" "bold"
          , runtimeWaylandDisplay = lookupText env "WAYLAND_DISPLAY" ""
          , runtimeDisplayName = lookupText env "DISPLAY" ""
          , runtimePanelLayoutEntries = panelLayoutEntries
          , runtimeSubpanelEntries = subpanelEntries
          , runtimeBackdropEntries = []
          , runtimeWindowsEntries = initialWindows
          , runtimeTaskEntries = initialTasks
          , runtimePaletteEntries = StyleStore.resolvedStylePaletteEntries resolvedStyle
          , runtimeCapabilityEntries = capabilityEntries backendName
          , runtimeFpVariant = styleFpVariant (StyleStore.resolvedStyleState resolvedStyle)
          , runtimeStyleState = StyleStore.resolvedStyleState resolvedStyle
          , runtimePaths = paths
          }
  refreshBackdropEntries baseState

writeCompatibilityOutputs :: RuntimeState -> IO ()
writeCompatibilityOutputs runtimeState = do
  let paths = runtimePaths runtimeState
  createDirectoryIfMissing True (runtimeStateDir paths)
  writeEnvFile (runtimeSessionFile paths) (sessionEntries runtimeState)
  unless (null (runtimePanelLayoutEntries runtimeState)) $
    writeEnvFile (runtimePanelLayoutFile paths) (runtimePanelLayoutEntries runtimeState)
  writeEnvFile (runtimePanelFile paths) (panelEntries runtimeState)
  writeEnvFile (runtimeWorkspacesFile paths) (workspacesEntries runtimeState)
  writeEnvFile (runtimeBackdropsFile paths) (runtimeBackdropEntries runtimeState)
  writeEnvFile (runtimePagerFile paths) (pagerEntries runtimeState)
  writeEnvFile (runtimeSubpanelsFile paths) (runtimeSubpanelEntries runtimeState)
  writeEnvFile (runtimeCapabilitiesFile paths) (runtimeCapabilityEntries runtimeState)
  writeEnvFile (runtimeWindowsFile paths) (runtimeWindowsEntries runtimeState)
  writeEnvFile (runtimeTaskdFile paths) (runtimeTaskEntries runtimeState)

ensureCompatibilityFifos :: RuntimeState -> IO ()
ensureCompatibilityFifos runtimeState = do
  let paths = runtimePaths runtimeState
  createDirectoryIfMissing True (runtimeStateDir paths)
  mapM_ ensureFifo
    [ runtimeCommandFifo paths
    , runtimePagerFifo paths
    , runtimeToplevelFifo paths
    ]

handleRuntimeCommand :: RuntimeCommand -> RuntimeState -> IO RuntimeTransition
handleRuntimeCommand command runtimeState =
  case command of
    CommandWorkspaceSwitch workspaceName ->
      if workspaceName `elem` runtimeWorkspaces runtimeState
        then do
          let updatedState = runtimeState {runtimeCurrentWorkspace = workspaceName}
          syncedState <- refreshBackdropEntries updatedState
          pure $
            RuntimeTransition
              { runtimeTransitionState = syncedState
              , runtimeTransitionTopics = changedWorkspaceTopics
              , runtimeTransitionEffects =
                  [ RuntimeEffectCompatCommand
                      (runtimePagerFifo (runtimePaths syncedState))
                      ("switch_workspace:" ++ workspaceName)
                  ]
              , runtimeTransitionMessage = "workspace updated"
              }
        else pure (unchangedTransition runtimeState "workspace not found")
    CommandWorkspaceRename oldWorkspace newWorkspace ->
      if null newWorkspace || oldWorkspace == newWorkspace || oldWorkspace `notElem` runtimeWorkspaces runtimeState
        then pure (unchangedTransition runtimeState "workspace rename skipped")
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
          syncedState <- refreshBackdropEntries updatedState
          pure $
            RuntimeTransition
              { runtimeTransitionState = syncedState
              , runtimeTransitionTopics = changedWorkspaceTopics
              , runtimeTransitionEffects =
                  [ RuntimeEffectCompatCommand
                      (runtimeCommandFifo (runtimePaths syncedState))
                      ("rename_workspace:" ++ oldWorkspace ++ ":" ++ newWorkspace)
                  ]
              , runtimeTransitionMessage = "workspace renamed"
              }
    CommandWindow windowCommand windowId ->
      pure $
        RuntimeTransition
          { runtimeTransitionState = runtimeState
          , runtimeTransitionTopics = []
          , runtimeTransitionEffects =
              [ RuntimeEffectCompatCommand
                  (runtimeToplevelFifo (runtimePaths runtimeState))
                  (renderWindowCompat windowCommand windowId)
              ]
          , runtimeTransitionMessage = "window command forwarded"
          }
    CommandPublishState topic entries ->
      publishRuntimeState topic entries runtimeState
    CommandStyleSet styleUpdates applyNow -> do
      resolvedStyle <-
        StyleStore.writeResolvedStyleEntries
          (runtimePaths runtimeState)
          (runtimePaletteFallbackFile runtimeState)
          styleUpdates
      updatedState <- refreshBackdropEntries (updateRuntimeStateFromResolvedStyle runtimeState resolvedStyle)
      pure
        RuntimeTransition
          { runtimeTransitionState = updatedState
          , runtimeTransitionTopics = changedStyleTopics runtimeState updatedState
          , runtimeTransitionEffects =
              [ RuntimeEffectApplyResolvedStyle resolvedStyle
              | applyNow
              ]
          , runtimeTransitionMessage =
              if applyNow then "style updated and applied" else "style updated"
          }
    CommandStyleApply -> do
      resolvedStyle <-
        StyleStore.readResolvedStyleState
          (runtimePaths runtimeState)
          (runtimePaletteFallbackFile runtimeState)
      updatedState <- refreshBackdropEntries (updateRuntimeStateFromResolvedStyle runtimeState resolvedStyle)
      pure
        RuntimeTransition
          { runtimeTransitionState = updatedState
          , runtimeTransitionTopics = changedStyleTopics runtimeState updatedState
          , runtimeTransitionEffects = [RuntimeEffectApplyResolvedStyle resolvedStyle]
          , runtimeTransitionMessage = "style applied"
          }
    CommandReload ->
      pure $
        RuntimeTransition
          { runtimeTransitionState = runtimeState
          , runtimeTransitionTopics = []
          , runtimeTransitionEffects = [RuntimeEffectReloadBackend]
          , runtimeTransitionMessage = "reload requested"
          }

handleCompatCommandLine :: String -> RuntimeState -> IO RuntimeTransition
handleCompatCommandLine rawLine runtimeState =
  case parseCompatCommandLine rawLine of
    Just command -> handleRuntimeCommand command runtimeState
    Nothing -> pure (unchangedTransition runtimeState "ignored")

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
    TopicBackdrops -> pure (runtimeBackdropEntries runtimeState)
    TopicSubpanels -> pure (runtimeSubpanelEntries runtimeState)
    TopicPager -> pure (pagerEntries runtimeState)
    TopicCapabilities -> pure (runtimeCapabilityEntries runtimeState)
    TopicWindows -> pure (runtimeWindowsEntries runtimeState)
    TopicTaskd -> pure (runtimeTaskEntries runtimeState)
    TopicStyle -> StyleStore.readStyleEntries (runtimePaths runtimeState)

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
       CommandPublishState _ _ ->
         pure False
       CommandStyleSet _ _ ->
         pure False
       CommandStyleApply ->
         pure False

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

sessionEntries :: RuntimeState -> [KeyValue]
sessionEntries runtimeState =
  [ ("NSCDE_BACKEND", runtimeBackendName runtimeState)
  , ("NSCDE_VERSION", runtimeVersionString runtimeState)
  , ("NSCDE_LABWC_CONFIG_DIR", runtimeLabwcConfigDir runtimeState)
  , ("WAYLAND_DISPLAY", runtimeWaylandDisplay runtimeState)
  , ("DISPLAY", runtimeDisplayName runtimeState)
  , ("NSCDE_SESSION_COMMAND_FIFO", runtimeCommandFifo (runtimePaths runtimeState))
  , ("NSCDE_BACKDROP_IMAGE", backdropValue "NSCDE_BACKDROP_IMAGE" runtimeState)
  , ("NSCDE_BACKDROP_COLOR", backdropValue "NSCDE_BACKDROP_COLOR" runtimeState)
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

writeEnvFile :: FilePath -> [KeyValue] -> IO ()
writeEnvFile targetPath entries =
  writeAtomicFile targetPath (renderEnvFile entries)

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
      maybePkill <- findExecutableInPath (runtimeSystemPath runtimeState) "pkill"
      case maybePkill of
        Just pkillPath -> do
          (_, _, _, processHandle) <- createProcess (proc pkillPath ["-HUP", "-x", "labwc"])
          _ <- waitForProcess processHandle
          pure ()
        Nothing ->
          pure ()
    _ -> pure ()

changedWorkspaceTopics :: [RuntimeTopic]
changedWorkspaceTopics =
  [ TopicPanel
  , TopicWorkspaces
  , TopicBackdrops
  , TopicPager
  ]

changedStyleTopics :: RuntimeState -> RuntimeState -> [RuntimeTopic]
changedStyleTopics previousState updatedState =
  TopicStyle :
    [ TopicPanel
    | runtimeFpVariant previousState /= runtimeFpVariant updatedState
        || runtimePaletteEntries previousState /= runtimePaletteEntries updatedState
    ]
    ++
    [ TopicBackdrops
    | runtimeCurrentWorkspace previousState /= runtimeCurrentWorkspace updatedState
        || runtimeStyleState previousState /= runtimeStyleState updatedState
        || runtimePaletteEntries previousState /= runtimePaletteEntries updatedState
    ]

unchangedTransition :: RuntimeState -> String -> RuntimeTransition
unchangedTransition runtimeState message =
  RuntimeTransition
    { runtimeTransitionState = runtimeState
    , runtimeTransitionTopics = []
    , runtimeTransitionEffects = []
    , runtimeTransitionMessage = message
    }

publishRuntimeState :: RuntimeTopic -> [KeyValue] -> RuntimeState -> IO RuntimeTransition
publishRuntimeState topic entries runtimeState =
  case topic of
    TopicWindows -> do
      let normalizedEntries = normalizeWindowsEntries entries
          updatedState = runtimeState
            { runtimeWindowsEntries = normalizedEntries
            , runtimeTaskEntries =
                deriveTaskEntries
                  (runtimeToplevelFifo (runtimePaths runtimeState))
                  normalizedEntries
            }
      pure $
        RuntimeTransition
          { runtimeTransitionState = updatedState
          , runtimeTransitionTopics = [TopicWindows, TopicTaskd]
          , runtimeTransitionEffects = []
          , runtimeTransitionMessage = "state published"
          }
    TopicWorkspaces ->
      publishWorkspaceLikeState entries runtimeState
    TopicPager ->
      publishWorkspaceLikeState entries runtimeState
    _ ->
      pure (unchangedTransition runtimeState "publish unsupported for topic")

updateRuntimeStateFromResolvedStyle :: RuntimeState -> StyleStore.ResolvedStyleState -> RuntimeState
updateRuntimeStateFromResolvedStyle runtimeState resolvedStyle =
  runtimeState
    { runtimePaletteFile = StyleStore.resolvedStylePaletteFile resolvedStyle
    , runtimePaletteEntries =
        case StyleStore.resolvedStylePaletteEntries resolvedStyle of
          [] -> runtimePaletteEntries runtimeState
          entries -> entries
    , runtimeFpVariant = styleFpVariant (StyleStore.resolvedStyleState resolvedStyle)
    , runtimeStyleState = StyleStore.resolvedStyleState resolvedStyle
    }

refreshBackdropEntries :: RuntimeState -> IO RuntimeState
refreshBackdropEntries runtimeState = do
  entries <- computeBackdropEntries runtimeState
  pure $
    runtimeState
      { runtimeBackdropEntries = entries
      }

computeBackdropEntries :: RuntimeState -> IO [KeyValue]
computeBackdropEntries runtimeState =
  fmap renderBackdropEntries $
    buildBackdropPlan
      (runtimeFvwmUserDir runtimeState)
      (runtimeDataDir runtimeState)
      (runtimeWorkspaces runtimeState)
      (runtimeCurrentWorkspace runtimeState)
      (runtimeStyleState runtimeState)
      (runtimePaletteEntries runtimeState)

writeBackdropOutputs :: RuntimeState -> IO ()
writeBackdropOutputs runtimeState =
  BackdropStore.writeBackdropEntries
    (runtimePaths runtimeState)
    (runtimeBackdropEntries runtimeState)

backdropValue :: String -> RuntimeState -> String
backdropValue key runtimeState =
  lookupBackdropValue key (runtimeBackdropEntries runtimeState)

lookupBackdropValue :: String -> [KeyValue] -> String
lookupBackdropValue _ [] = ""
lookupBackdropValue key ((candidateKey, value):rest)
  | key == candidateKey = value
  | otherwise = lookupBackdropValue key rest

normalizeWindowsEntries :: [KeyValue] -> [KeyValue]
normalizeWindowsEntries entries =
  let parsedEntries = parseEnvContents (renderEnvFile entries)
  in if null parsedEntries then initialWindowsEntries else parsedEntries

deriveTaskEntries :: FilePath -> [KeyValue] -> [KeyValue]
deriveTaskEntries commandFifo windowsEntries =
  [ ("NSCDE_TASK_COUNT", lookupEntry "NSCDE_WINDOW_COUNT" "0" windowsEntries)
  , ("NSCDE_TASK_FOCUSED", lookupEntry "NSCDE_FOCUSED_WINDOW" "" windowsEntries)
  , ("NSCDE_TASK_COMMAND_FIFO", commandFifo)
  ]

publishWorkspaceLikeState :: [KeyValue] -> RuntimeState -> IO RuntimeTransition
publishWorkspaceLikeState entries runtimeState = do
  let normalizedEntries = normalizeWorkspaceEntries entries
      publishedWorkspaces = publishedWorkspaceNames normalizedEntries
      resolvedWorkspaces =
        if null publishedWorkspaces
          then runtimeWorkspaces runtimeState
          else publishedWorkspaces
      resolvedCurrent =
        resolvePublishedCurrentWorkspace
          normalizedEntries
          resolvedWorkspaces
          (runtimeCurrentWorkspace runtimeState)
      updatedState =
        runtimeState
          { runtimeWorkspaces = resolvedWorkspaces
          , runtimeCurrentWorkspace = resolvedCurrent
          }
  syncedState <- refreshBackdropEntries updatedState
  pure $
    RuntimeTransition
      { runtimeTransitionState = syncedState
      , runtimeTransitionTopics = changedWorkspaceTopics
      , runtimeTransitionEffects = []
      , runtimeTransitionMessage = "state published"
      }

normalizeWorkspaceEntries :: [KeyValue] -> [KeyValue]
normalizeWorkspaceEntries entries =
  let parsedEntries = parseEnvContents (renderEnvFile entries)
  in if null parsedEntries then [] else parsedEntries

publishedWorkspaceNames :: [KeyValue] -> [String]
publishedWorkspaceNames entries =
  case splitCommaList (lookupEntry "NSCDE_WORKSPACES" "" entries) of
    [] -> splitCommaList (lookupEntry "NSCDE_PAGER_WORKSPACES" "" entries)
    names -> names

resolvePublishedCurrentWorkspace :: [KeyValue] -> [String] -> String -> String
resolvePublishedCurrentWorkspace entries workspaceNames fallbackCurrent
  | null workspaceNames = fallbackCurrent
  | requestedCurrent `elem` workspaceNames = requestedCurrent
  | fallbackCurrent `elem` workspaceNames = fallbackCurrent
  | otherwise =
      case workspaceNames of
        firstWorkspace:_ -> firstWorkspace
        [] -> fallbackCurrent
  where
    requestedCurrent =
      firstNonEmpty
        [ lookupEntry "NSCDE_CURRENT_WORKSPACE" "" entries
        , lookupEntry "NSCDE_PAGER_CURRENT" "" entries
        ]

firstNonEmpty :: [String] -> String
firstNonEmpty [] = ""
firstNonEmpty (candidate:rest)
  | null candidate = firstNonEmpty rest
  | otherwise = candidate

lookupEntry :: String -> String -> [KeyValue] -> String
lookupEntry _ fallback [] = fallback
lookupEntry key fallback ((candidateKey, value):rest)
  | key == candidateKey = value
  | otherwise = lookupEntry key fallback rest

findExecutableInPath :: FilePath -> String -> IO (Maybe FilePath)
findExecutableInPath searchPath executableName =
  firstExistingExecutable (candidatePaths searchPath)
  where
    candidatePaths pathValue =
      [ dir </> executableName
      | dir <- splitSearchPath pathValue
      , not (null dir)
      ]

    firstExistingExecutable [] = pure Nothing
    firstExistingExecutable (candidate:rest) = do
      exists <- doesFileExist candidate
      if exists
        then pure (Just candidate)
        else firstExistingExecutable rest

splitSearchPath :: FilePath -> [FilePath]
splitSearchPath "" = []
splitSearchPath pathValue =
  case break (== ':') pathValue of
    (segment, ':' : rest) -> segment : splitSearchPath rest
    (segment, _) -> [segment]

applyResolvedRuntimeStyleState :: RuntimeState -> StyleStore.ResolvedStyleState -> IO ()
applyResolvedRuntimeStyleState runtimeState resolvedStyle =
  case runtimeBackendName runtimeState of
    "labwc" -> do
      StyleApply.applyResolvedStyleState
        "labwc"
        (runtimeStyleContext runtimeState)
        resolvedStyle
      reloadBackend runtimeState
    _ -> pure ()

performRuntimeTransitionEffects :: RuntimeTransition -> IO String
performRuntimeTransitionEffects transition = do
  effectStatuses <- mapM (performRuntimeEffect (runtimeTransitionState transition)) (runtimeTransitionEffects transition)
  let failedEffects = filter (not . fst) effectStatuses
  pure $
    case failedEffects of
      [] -> runtimeTransitionMessage transition
      _ -> runtimeTransitionMessage transition ++ " (compat bridge unavailable)"

performRuntimeEffect :: RuntimeState -> RuntimeEffect -> IO (Bool, RuntimeEffect)
performRuntimeEffect runtimeState effect =
  case effect of
    RuntimeEffectCompatCommand fifoPath commandLine -> do
      success <- writeCompatCommand fifoPath commandLine
      pure (success, effect)
    RuntimeEffectApplyResolvedStyle resolvedStyle -> do
      writeBackdropOutputs runtimeState
      applyResolvedRuntimeStyleState runtimeState resolvedStyle
      pure (True, effect)
    RuntimeEffectReloadBackend -> do
      reloadBackend runtimeState
      pure (True, effect)

runtimeStyleContext :: RuntimeState -> RuntimeStyleContext
runtimeStyleContext runtimeState =
  RuntimeStyleContext
    { runtimeStyleBackendName = runtimeBackendName runtimeState
    , runtimeStyleHomeDir = runtimeHomeDir runtimeState
    , runtimeStyleRootDir = runtimeRootDir runtimeState
    , runtimeStyleDataDir = runtimeDataDir runtimeState
    , runtimeStyleToolsDir = runtimeToolsDir runtimeState
    , runtimeStyleFvwmUserDir = runtimeFvwmUserDir runtimeState
    , runtimeStyleXdgConfigHome = runtimeXdgConfigHome runtimeState
    , runtimeStyleXdgCacheHome = runtimeXdgCacheHome runtimeState
    , runtimeStyleXdgDataHome = runtimeXdgDataHome runtimeState
    , runtimeStyleXdgRuntimeDir = runtimeXdgRuntimeDir runtimeState
    , runtimeStyleThemeName = runtimeThemeName runtimeState
    , runtimeStyleWorkspaces = runtimeWorkspaces runtimeState
    , runtimeStyleLabwcConfigDir = runtimeLabwcConfigDir runtimeState
    , runtimeStyleLabwcKeybindXmlFile = runtimeLabwcKeybindXmlFile runtimeState
    , runtimeStyleTitleFontName = runtimeLabwcTitleFontName runtimeState
    , runtimeStyleTitleFontSize = runtimeLabwcTitleFontSize runtimeState
    , runtimeStyleTitleFontSlant = runtimeLabwcTitleFontSlant runtimeState
    , runtimeStyleTitleFontWeight = runtimeLabwcTitleFontWeight runtimeState
    , runtimeStyleWaylandDisplay = runtimeWaylandDisplay runtimeState
    , runtimeStyleDisplayName = runtimeDisplayName runtimeState
    , runtimeStyleSystemPath = runtimeSystemPath runtimeState
    , runtimeStyleStateDir = runtimeStateDir (runtimePaths runtimeState)
    }

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
