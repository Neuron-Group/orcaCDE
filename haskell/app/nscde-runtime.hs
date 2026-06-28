module Main (main) where

import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (getArgs, getEnv, getEnvironment)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)

import NsCDE.Backend.Labwc.KeybindXml (renderKeyboardXml)
import NsCDE.Backend.Labwc.MenuXml (renderMenuXml)
import NsCDE.Backend.Labwc.RcXml (renderRcXml)
import NsCDE.Backend.Labwc.SessionFiles (renderAutostart, renderEnvironment, renderShutdown)
import NsCDE.Backend.Labwc.Theme (labwcThemeDir, writeLabwcTheme)
import NsCDE.Domain.Runtime
import NsCDE.Foundation.Common (writeAtomicFile)
import NsCDE.Foundation.EnvFile (parseEnvContents, renderEnvFile)
import NsCDE.Foundation.Paths (RuntimePaths(..), resolveRuntimePaths)
import NsCDE.Foundation.Settings (lookupText)
import NsCDE.Parse.AppMenus (loadAppMenuEntries)
import NsCDE.Parse.PaletteDp (loadPaletteColors)
import NsCDE.Policy.Keybinds (buildKeybinds, resolveTerminal)
import NsCDE.Policy.Menu (buildMenuModel)
import NsCDE.Policy.PanelLayout (emitPanelLayout, loadStaticPanelProfile)
import NsCDE.Policy.SessionPlan (buildRcConfig, buildRcInputFromEnv, buildSessionPlan)
import NsCDE.Runtime.Daemon (runCtl, runDaemon, runPublishState, runQuery, runSubscribe)
import NsCDE.Store.StyleState (readStyleState)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["daemon"] -> runDaemon
    ["ctl", "workspace-switch", workspaceName] ->
      runCtl (CommandWorkspaceSwitch workspaceName)
    ["ctl", "workspace-rename", oldWorkspace, newWorkspace] ->
      runCtl (CommandWorkspaceRename oldWorkspace newWorkspace)
    ["ctl", "style-set", key, value] ->
      runCtl (CommandStyleSet [(key, value)] False)
    ["ctl", "style-apply"] ->
      runCtl CommandStyleApply
    ["ctl", "publish-state", topicText] ->
      publishState topicText
    ["ctl", "reload"] ->
      runCtl CommandReload
    ["ctl", "window", windowCommandText, windowIdText] ->
      publishWindowCtl windowCommandText windowIdText
    ["query", topicText] ->
      publishQuery topicText
    ["subscribe", topicsText] ->
      publishSubscribe topicsText
    ["panel-layout", "publish"] -> publishPanelLayout Nothing
    ["panel-layout", "publish", staticPath] -> publishPanelLayout (Just staticPath)
    ["labwc-menu", "publish", configDir] -> publishLabwcMenuXml configDir
    ["labwc-keybinds", "publish"] -> publishLabwcKeybindXml
    ["labwc-theme", "publish"] -> publishLabwcTheme
    ["labwc-rc", "publish", configDir] -> publishLabwcRcXml configDir
    ["labwc-session", "publish", configDir] -> publishLabwcSessionFiles configDir
    _ -> do
      hPutStrLn stderr "Usage: nscde-runtime daemon"
      hPutStrLn stderr "       nscde-runtime ctl workspace-switch WORKSPACE"
      hPutStrLn stderr "       nscde-runtime ctl workspace-rename OLD NEW"
      hPutStrLn stderr "       nscde-runtime ctl style-set KEY VALUE"
      hPutStrLn stderr "       nscde-runtime ctl style-apply"
      hPutStrLn stderr "       nscde-runtime ctl publish-state TOPIC"
      hPutStrLn stderr "       nscde-runtime ctl window <activate|close|minimize|restore|maximize> ID"
      hPutStrLn stderr "       nscde-runtime ctl reload"
      hPutStrLn stderr "       nscde-runtime query <session|panel|panel-layout|workspaces|backdrops|windows|subpanels|pager|taskd|capabilities|style>"
      hPutStrLn stderr "       nscde-runtime subscribe <topic[,topic...]>"
      hPutStrLn stderr "Usage: nscde-runtime panel-layout publish [STATIC_PANEL_LAYOUT_FILE]"
      hPutStrLn stderr "       nscde-runtime labwc-menu publish CONFIG_DIR"
      hPutStrLn stderr "       nscde-runtime labwc-keybinds publish"
      hPutStrLn stderr "       nscde-runtime labwc-theme publish"
      hPutStrLn stderr "       nscde-runtime labwc-rc publish CONFIG_DIR"
      hPutStrLn stderr "       nscde-runtime labwc-session publish CONFIG_DIR"
      exitFailure

publishPanelLayout :: Maybe FilePath -> IO ()
publishPanelLayout maybeStaticPath = do
  staticPath <- case maybeStaticPath of
    Just path -> pure path
    Nothing -> getEnv "NSCDE_STATIC_PANEL_LAYOUT_FILE"
  profile <- loadStaticPanelProfile staticPath
  putStr (renderEnvFile (emitPanelLayout profile))

publishLabwcMenuXml :: FilePath -> IO ()
publishLabwcMenuXml configDir = do
  env <- getEnvironment
  terminal <- resolveTerminal env
  appEntries <- loadAppMenuEntries env
  createDirectoryIfMissing True configDir
  writeAtomicFile (configDir </> "menu.xml") (renderMenuXml (buildMenuModel env terminal appEntries))

publishLabwcKeybindXml :: IO ()
publishLabwcKeybindXml = do
  env <- getEnvironment
  bindings <- buildKeybinds env
  putStr (renderKeyboardXml bindings)

publishLabwcTheme :: IO ()
publishLabwcTheme = do
  env <- getEnvironment
  let homeDir = lookupText env "HOME" "/tmp"
      xdgDataHome = lookupText env "XDG_DATA_HOME" (homeDir </> ".local" </> "share")
      themesRoot = lookupText env "NSCDE_THEMES_DIR" (xdgDataHome </> "themes")
      themeName =
        lookupText env "NSCDE_THEME_NAME"
          (lookupText env "NSCDE_LABWC_THEME_NAME" "NsCDE-Stage1")
      paletteFile = lookupText env "NSCDE_PALETTE_FILE" ""
      themeDir = labwcThemeDir themesRoot themeName
  paletteColors <- loadPaletteColors paletteFile
  writeLabwcTheme themeDir paletteColors
  putStrLn themeDir

publishLabwcRcXml :: FilePath -> IO ()
publishLabwcRcXml configDir = do
  env <- getEnvironment
  let paths = resolveRuntimePaths env
      keybindFile =
        lookupText env "NSCDE_LABWC_KEYBIND_XML_FILE"
          (runtimeStateDir paths </> "labwc-keybinds.xml")
  keybindXml <- readOptionalFile keybindFile
  styleState <- readStyleState paths
  createDirectoryIfMissing True configDir
  writeAtomicFile
    (configDir </> "rc.xml")
    (renderRcXml (buildRcConfig (buildRcInputFromEnv env keybindXml) styleState))

publishLabwcSessionFiles :: FilePath -> IO ()
publishLabwcSessionFiles configDir = do
  env <- getEnvironment
  let plan = buildSessionPlan env
  createDirectoryIfMissing True configDir
  writeAtomicFile (configDir </> "autostart") (renderAutostart plan)
  writeAtomicFile (configDir </> "environment") (renderEnvironment plan)
  writeAtomicFile (configDir </> "shutdown") (renderShutdown plan)

publishWindowCtl :: String -> String -> IO ()
publishWindowCtl windowCommandText windowIdText =
  case parseRuntimeWindowCommand windowCommandText of
    Nothing -> do
      hPutStrLn stderr ("Unsupported window command: " ++ windowCommandText)
      exitFailure
    Just windowCommand ->
      case reads windowIdText of
        [(windowId, "")] ->
          runCtl (CommandWindow windowCommand windowId)
        _ -> do
          hPutStrLn stderr ("Invalid window id: " ++ windowIdText)
          exitFailure

publishState :: String -> IO ()
publishState topicText =
  case parseRuntimeTopic topicText of
    Just topic -> do
      contents <- getContents
      runPublishState topic (parseEnvContents contents)
    Nothing -> do
      hPutStrLn stderr ("Unsupported publish topic: " ++ topicText)
      exitFailure

publishQuery :: String -> IO ()
publishQuery topicText =
  case parseRuntimeTopic topicText of
    Just topic -> runQuery topic
    Nothing -> do
      hPutStrLn stderr ("Unsupported query topic: " ++ topicText)
      exitFailure

publishSubscribe :: String -> IO ()
publishSubscribe topicsText =
  let topics = parseTopics topicsText
  in if null topics
       then do
         hPutStrLn stderr ("Unsupported subscribe topic list: " ++ topicsText)
         exitFailure
       else runSubscribe topics

parseTopics :: String -> [RuntimeTopic]
parseTopics [] = []
parseTopics rawText =
  mapMaybe parseRuntimeTopic (splitOnComma rawText)

splitOnComma :: String -> [String]
splitOnComma [] = [""]
splitOnComma (',':rest) = "" : splitOnComma rest
splitOnComma (char:rest) =
  case splitOnComma rest of
    [] -> [[char]]
    token:tokens -> (char : token) : tokens

mapMaybe :: (a -> Maybe b) -> [a] -> [b]
mapMaybe _ [] = []
mapMaybe fn (value:rest) =
  case fn value of
    Just result -> result : mapMaybe fn rest
    Nothing -> mapMaybe fn rest

readOptionalFile :: FilePath -> IO String
readOptionalFile "" = pure ""
readOptionalFile path = do
  exists <- doesFileExist path
  if exists
    then readFile path
    else pure ""
