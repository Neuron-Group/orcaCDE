module NsCDE.Runtime.Labwc
  ( RuntimeLabwcContext(..)
  , loadRuntimeLabwcContext
  , refreshLabwcArtifact
  , refreshLabwcArtifacts
  , refreshLabwcGeneratedConfig
  , refreshLabwcReloadConfig
  , runtimeEnvironmentEntries
  , runtimeStyleContext
  ) where

import Control.Monad (unless)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))

import NsCDE.Backend.Labwc.KeybindXml (renderKeyboardXml)
import NsCDE.Backend.Labwc.MenuXml (renderMenuXml)
import NsCDE.Backend.Labwc.RcXml (renderRcXml)
import NsCDE.Backend.Labwc.SessionFiles (renderAutostart, renderEnvironment, renderShutdown)
import NsCDE.Backend.Labwc.Theme (labwcThemeDir, writeLabwcTheme)
import NsCDE.Domain.Runtime (RuntimeRefreshTarget(..), RuntimeStyleContext(..))
import NsCDE.Domain.Style (StyleState)
import NsCDE.Foundation.Common (writeAtomicFile)
import NsCDE.Foundation.EnvFile (KeyValue)
import NsCDE.Foundation.Paths (RuntimePaths(..), resolveRuntimePaths)
import NsCDE.Foundation.Settings (lookupText)
import NsCDE.Parse.AppMenus (loadAppMenuEntries)
import NsCDE.Parse.PaletteDp (loadPaletteColors)
import NsCDE.Policy.Keybinds (buildKeybinds)
import NsCDE.Policy.Menu (buildMenuModel)
import NsCDE.Policy.SessionPlan (buildRcConfig, buildRcInputFromEnv, buildSessionPlan)
import qualified NsCDE.Store.StyleState as StyleStore

data RuntimeLabwcContext = RuntimeLabwcContext
  { runtimeLabwcBackendName :: String
  , runtimeLabwcHomeDir :: FilePath
  , runtimeLabwcRootDir :: FilePath
  , runtimeLabwcDataDir :: FilePath
  , runtimeLabwcToolsDir :: FilePath
  , runtimeLabwcFvwmUserDir :: FilePath
  , runtimeLabwcXdgConfigHome :: FilePath
  , runtimeLabwcXdgCacheHome :: FilePath
  , runtimeLabwcXdgDataHome :: FilePath
  , runtimeLabwcXdgRuntimeDir :: FilePath
  , runtimeLabwcSystemPath :: FilePath
  , runtimeLabwcThemeName :: String
  , runtimeLabwcWorkspaces :: [String]
  , runtimeLabwcCurrentWorkspace :: String
  , runtimeLabwcPaletteFallbackFile :: FilePath
  , runtimeLabwcPaletteFile :: FilePath
  , runtimeLabwcConfigDir :: FilePath
  , runtimeLabwcKeybindXmlFile :: FilePath
  , runtimeLabwcTerminal :: String
  , runtimeLabwcKeybindSet :: String
  , runtimeLabwcTitleFontName :: String
  , runtimeLabwcTitleFontSize :: String
  , runtimeLabwcTitleFontSlant :: String
  , runtimeLabwcTitleFontWeight :: String
  , runtimeLabwcWaylandDisplay :: String
  , runtimeLabwcDisplayName :: String
  , runtimeLabwcStyleState :: StyleState
  , runtimeLabwcStateDir :: FilePath
  } deriving (Eq, Show)

refreshLabwcGeneratedConfig :: RuntimeLabwcContext -> IO ()
refreshLabwcGeneratedConfig runtimeContext =
  unless (runtimeLabwcBackendName runtimeContext /= "labwc") $
    writeLabwcKeybindXml runtimeContext

refreshLabwcReloadConfig :: RuntimeLabwcContext -> IO ()
refreshLabwcReloadConfig runtimeContext =
  unless (runtimeLabwcBackendName runtimeContext /= "labwc") $ do
    refreshLabwcArtifacts
      runtimeContext
      [ RefreshKeybinds
      , RefreshMenu
      , RefreshRc
      , RefreshTheme
      ]

loadRuntimeLabwcContext :: [KeyValue] -> IO RuntimeLabwcContext
loadRuntimeLabwcContext env = do
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
      fallbackWorkspace =
        case workspaceNames of
          firstWorkspace:_ -> firstWorkspace
          [] -> "One"
      currentWorkspace =
        lookupText env "NSCDE_CURRENT_WORKSPACE"
          (lookupText env "NSCDE_LABWC_CURRENT_WORKSPACE" fallbackWorkspace)
      paletteFallbackFile = lookupText env "NSCDE_PALETTE_FILE" ""
  resolvedStyle <-
    StyleStore.readResolvedStyleState paths paletteFallbackFile
  pure
    RuntimeLabwcContext
      { runtimeLabwcBackendName = backendName
      , runtimeLabwcHomeDir = homeDir
      , runtimeLabwcRootDir = rootDir
      , runtimeLabwcDataDir = dataDir
      , runtimeLabwcToolsDir = lookupText env "NSCDE_TOOLSDIR" ""
      , runtimeLabwcFvwmUserDir = lookupText env "FVWM_USERDIR" (homeDir </> ".NsCDE")
      , runtimeLabwcXdgConfigHome = lookupText env "XDG_CONFIG_HOME" (homeDir </> ".config")
      , runtimeLabwcXdgCacheHome = lookupText env "XDG_CACHE_HOME" (homeDir </> ".cache")
      , runtimeLabwcXdgDataHome = lookupText env "XDG_DATA_HOME" (homeDir </> ".local" </> "share")
      , runtimeLabwcXdgRuntimeDir = lookupText env "XDG_RUNTIME_DIR" ""
      , runtimeLabwcSystemPath = lookupText env "PATH" ""
      , runtimeLabwcThemeName = lookupText env "NSCDE_THEME_NAME" (lookupText env "NSCDE_LABWC_THEME_NAME" "NsCDE-Stage1")
      , runtimeLabwcWorkspaces = workspaceNames
      , runtimeLabwcCurrentWorkspace = currentWorkspace
      , runtimeLabwcPaletteFallbackFile = paletteFallbackFile
      , runtimeLabwcPaletteFile = StyleStore.resolvedStylePaletteFile resolvedStyle
      , runtimeLabwcConfigDir = lookupText env "NSCDE_LABWC_CONFIG_DIR" ""
      , runtimeLabwcKeybindXmlFile =
          lookupText env "NSCDE_LABWC_KEYBIND_XML_FILE" (runtimeStateDir paths </> "labwc-keybinds.xml")
      , runtimeLabwcTerminal = lookupText env "NSCDE_LABWC_TERMINAL" "xterm"
      , runtimeLabwcKeybindSet = lookupText env "NSCDE_KBD_BIND_SET" "cua"
      , runtimeLabwcTitleFontName = lookupText env "NSCDE_LABWC_TITLE_FONT_NAME" "Sans"
      , runtimeLabwcTitleFontSize = lookupText env "NSCDE_LABWC_TITLE_FONT_SIZE" "10"
      , runtimeLabwcTitleFontSlant = lookupText env "NSCDE_LABWC_TITLE_FONT_SLANT" "normal"
      , runtimeLabwcTitleFontWeight = lookupText env "NSCDE_LABWC_TITLE_FONT_WEIGHT" "bold"
      , runtimeLabwcWaylandDisplay = lookupText env "WAYLAND_DISPLAY" ""
      , runtimeLabwcDisplayName = lookupText env "DISPLAY" ""
      , runtimeLabwcStyleState = StyleStore.resolvedStyleState resolvedStyle
      , runtimeLabwcStateDir = runtimeStateDir paths
      }

runtimeEnvironmentEntries :: RuntimeLabwcContext -> [KeyValue]
runtimeEnvironmentEntries runtimeContext =
  [ ("HOME", runtimeLabwcHomeDir runtimeContext)
  , ("NSCDE_ROOT", runtimeLabwcRootDir runtimeContext)
  , ("NSCDE_DATADIR", runtimeLabwcDataDir runtimeContext)
  , ("NSCDE_TOOLSDIR", runtimeLabwcToolsDir runtimeContext)
  , ("FVWM_USERDIR", runtimeLabwcFvwmUserDir runtimeContext)
  , ("XDG_CONFIG_HOME", runtimeLabwcXdgConfigHome runtimeContext)
  , ("XDG_CACHE_HOME", runtimeLabwcXdgCacheHome runtimeContext)
  , ("XDG_DATA_HOME", runtimeLabwcXdgDataHome runtimeContext)
  , ("XDG_RUNTIME_DIR", runtimeLabwcXdgRuntimeDir runtimeContext)
  , ("NSCDE_BACKEND", runtimeLabwcBackendName runtimeContext)
  , ("NSCDE_THEME_NAME", runtimeLabwcThemeName runtimeContext)
  , ("NSCDE_LABWC_THEME_NAME", runtimeLabwcThemeName runtimeContext)
  , ("NSCDE_LABWC_CONFIG_DIR", runtimeLabwcConfigDir runtimeContext)
  , ("NSCDE_LABWC_KEYBIND_XML_FILE", runtimeLabwcKeybindXmlFile runtimeContext)
  , ("NSCDE_LABWC_TERMINAL", runtimeLabwcTerminal runtimeContext)
  , ("NSCDE_KBD_BIND_SET", runtimeLabwcKeybindSet runtimeContext)
  , ("NSCDE_LABWC_TITLE_FONT_NAME", runtimeLabwcTitleFontName runtimeContext)
  , ("NSCDE_LABWC_TITLE_FONT_SIZE", runtimeLabwcTitleFontSize runtimeContext)
  , ("NSCDE_LABWC_TITLE_FONT_SLANT", runtimeLabwcTitleFontSlant runtimeContext)
  , ("NSCDE_LABWC_TITLE_FONT_WEIGHT", runtimeLabwcTitleFontWeight runtimeContext)
  , ("NSCDE_WORKSPACES", renderWorkspaceList (runtimeLabwcWorkspaces runtimeContext))
  , ("NSCDE_CURRENT_WORKSPACE", runtimeLabwcCurrentWorkspace runtimeContext)
  , ("NSCDE_LABWC_WORKSPACES", renderWorkspaceList (runtimeLabwcWorkspaces runtimeContext))
  , ("NSCDE_LABWC_CURRENT_WORKSPACE", runtimeLabwcCurrentWorkspace runtimeContext)
  , ("NSCDE_PALETTE_FILE", runtimeLabwcPaletteFallbackFile runtimeContext)
  , ("NSCDE_STATE_DIR", runtimeLabwcStateDir runtimeContext)
  ] ++
    [ ("PATH", runtimeLabwcSystemPath runtimeContext)
    | not (null (runtimeLabwcSystemPath runtimeContext))
    ] ++
    [ ("WAYLAND_DISPLAY", runtimeLabwcWaylandDisplay runtimeContext)
    | not (null (runtimeLabwcWaylandDisplay runtimeContext))
    ] ++
    [ ("DISPLAY", runtimeLabwcDisplayName runtimeContext)
    | not (null (runtimeLabwcDisplayName runtimeContext))
    ]

refreshLabwcArtifact :: RuntimeLabwcContext -> RuntimeRefreshTarget -> IO ()
refreshLabwcArtifact runtimeContext refreshTarget = do
  let env = runtimeEnvironmentEntries runtimeContext
      configDir = runtimeLabwcConfigDir runtimeContext
  case refreshTarget of
    RefreshKeybinds ->
      writeLabwcKeybindXml runtimeContext
    RefreshMenu ->
      unless (null configDir) $ do
        createDirectoryIfMissing True configDir
        writeLabwcMenuXml runtimeContext env
    RefreshRc ->
      unless (null configDir) $ do
        createDirectoryIfMissing True configDir
        writeLabwcRcXml runtimeContext env
    RefreshTheme ->
      writeLabwcThemeFiles runtimeContext
    RefreshSession ->
      unless (null configDir) $ do
        createDirectoryIfMissing True configDir
        writeLabwcSessionFiles runtimeContext env

refreshLabwcArtifacts :: RuntimeLabwcContext -> [RuntimeRefreshTarget] -> IO ()
refreshLabwcArtifacts runtimeContext =
  mapM_ (refreshLabwcArtifact runtimeContext)

runtimeStyleContext :: RuntimeLabwcContext -> RuntimeStyleContext
runtimeStyleContext runtimeContext =
  RuntimeStyleContext
    { runtimeStyleBackendName = runtimeLabwcBackendName runtimeContext
    , runtimeStyleHomeDir = runtimeLabwcHomeDir runtimeContext
    , runtimeStyleRootDir = runtimeLabwcRootDir runtimeContext
    , runtimeStyleDataDir = runtimeLabwcDataDir runtimeContext
    , runtimeStyleToolsDir = runtimeLabwcToolsDir runtimeContext
    , runtimeStyleFvwmUserDir = runtimeLabwcFvwmUserDir runtimeContext
    , runtimeStyleXdgConfigHome = runtimeLabwcXdgConfigHome runtimeContext
    , runtimeStyleXdgCacheHome = runtimeLabwcXdgCacheHome runtimeContext
    , runtimeStyleXdgDataHome = runtimeLabwcXdgDataHome runtimeContext
    , runtimeStyleXdgRuntimeDir = runtimeLabwcXdgRuntimeDir runtimeContext
    , runtimeStyleThemeName = runtimeLabwcThemeName runtimeContext
    , runtimeStyleWorkspaces = runtimeLabwcWorkspaces runtimeContext
    , runtimeStyleLabwcConfigDir = runtimeLabwcConfigDir runtimeContext
    , runtimeStyleLabwcKeybindXmlFile = runtimeLabwcKeybindXmlFile runtimeContext
    , runtimeStyleTitleFontName = runtimeLabwcTitleFontName runtimeContext
    , runtimeStyleTitleFontSize = runtimeLabwcTitleFontSize runtimeContext
    , runtimeStyleTitleFontSlant = runtimeLabwcTitleFontSlant runtimeContext
    , runtimeStyleTitleFontWeight = runtimeLabwcTitleFontWeight runtimeContext
    , runtimeStyleWaylandDisplay = runtimeLabwcWaylandDisplay runtimeContext
    , runtimeStyleDisplayName = runtimeLabwcDisplayName runtimeContext
    , runtimeStyleSystemPath = runtimeLabwcSystemPath runtimeContext
    , runtimeStyleStateDir = runtimeLabwcStateDir runtimeContext
    }

writeLabwcKeybindXml :: RuntimeLabwcContext -> IO ()
writeLabwcKeybindXml runtimeContext = do
  let keybindFile = runtimeLabwcKeybindXmlFile runtimeContext
  unless (null keybindFile) $ do
    createDirectoryIfMissing True (runtimeLabwcStateDir runtimeContext)
    bindings <- buildKeybinds (runtimeEnvironmentEntries runtimeContext)
    writeAtomicFile keybindFile (renderKeyboardXml bindings)

writeLabwcMenuXml :: RuntimeLabwcContext -> [KeyValue] -> IO ()
writeLabwcMenuXml runtimeContext env = do
  appEntries <- loadAppMenuEntries env
  writeAtomicFile
    (runtimeLabwcConfigDir runtimeContext </> "menu.xml")
    (renderMenuXml
      (buildMenuModel env (runtimeLabwcTerminal runtimeContext) appEntries))

writeLabwcRcXml :: RuntimeLabwcContext -> [KeyValue] -> IO ()
writeLabwcRcXml runtimeContext env = do
  keybindXml <- readOptionalFile (runtimeLabwcKeybindXmlFile runtimeContext)
  writeAtomicFile
    (runtimeLabwcConfigDir runtimeContext </> "rc.xml")
    (renderRcXml
      (buildRcConfig
        (buildRcInputFromEnv env keybindXml)
        (runtimeLabwcStyleState runtimeContext)))

writeLabwcThemeFiles :: RuntimeLabwcContext -> IO ()
writeLabwcThemeFiles runtimeContext = do
  paletteColors <- loadPaletteColors (runtimeLabwcPaletteFile runtimeContext)
  writeLabwcTheme
    (labwcThemeDir
      (runtimeLabwcXdgDataHome runtimeContext </> "themes")
      (runtimeLabwcThemeName runtimeContext))
    paletteColors

writeLabwcSessionFiles :: RuntimeLabwcContext -> [KeyValue] -> IO ()
writeLabwcSessionFiles runtimeContext env = do
  let configDir = runtimeLabwcConfigDir runtimeContext
      plan = buildSessionPlan env
  writeAtomicFile (configDir </> "autostart") (renderAutostart plan)
  writeAtomicFile (configDir </> "environment") (renderEnvironment plan)
  writeAtomicFile (configDir </> "shutdown") (renderShutdown plan)

renderWorkspaceList :: [String] -> String
renderWorkspaceList [] = ""
renderWorkspaceList [workspaceName] = workspaceName
renderWorkspaceList (workspaceName:rest) =
  workspaceName ++ "," ++ renderWorkspaceList rest

splitCommaList :: String -> [String]
splitCommaList [] = []
splitCommaList rawText =
  splitSegments rawText
  where
    splitSegments [] = []
    splitSegments text =
      case break (== ',') text of
        ("", ',' : rest) -> splitSegments rest
        ("", _) -> []
        (segment, ',' : rest) -> segment : splitSegments rest
        (segment, _) -> [segment]

readOptionalFile :: FilePath -> IO String
readOptionalFile "" = pure ""
readOptionalFile path = do
  exists <- doesFileExist path
  if exists
    then readFile path
    else pure ""
