module Main (main) where

import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (getArgs, getEnv, getEnvironment)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)

import NsCDE.Backend.Labwc.KeybindXml (renderKeyboardXml)
import NsCDE.Backend.Labwc.MenuXml (renderMenuXml)
import NsCDE.Backend.Labwc.RcXml (renderRcXml)
import NsCDE.Domain.Runtime
import NsCDE.Foundation.EnvFile (parseEnvContents, renderEnvFile)
import NsCDE.Parse.AppMenus (loadAppMenuEntries)
import NsCDE.Policy.Keybinds (buildKeybinds, resolveTerminal)
import NsCDE.Policy.Menu (buildMenuModel)
import NsCDE.Policy.PanelLayout (emitPanelLayout, loadStaticPanelProfile)
import NsCDE.Runtime.Daemon (runCtl, runDaemon, runPublishState, runQuery, runSubscribe)
import qualified NsCDE.Runtime.Labwc as RuntimeLabwc

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["daemon"] -> runDaemon
    ["ctl", "workspace-switch", workspaceName] ->
      runCtl (CommandWorkspaceSwitch workspaceName)
    ["ctl", "workspace-rename", oldWorkspace, newWorkspace] ->
      runCtl (CommandWorkspaceRename oldWorkspace newWorkspace)
    ["ctl", "color-select", paletteName, colorCountText] ->
      publishColorSelectCtl paletteName colorCountText
    ["ctl", "backdrop-select", deskText, modeText, imageName] ->
      publishBackdropSelectCtl deskText modeText imageName
    ["ctl", "style-set", key, value] ->
      runCtl (CommandStyleSet [(key, value)] False)
    ["ctl", "style-apply"] ->
      runCtl CommandStyleApply
    ["ctl", "refresh", refreshTargetText] ->
      publishRefreshCtl refreshTargetText
    ["ctl", "publish-state", topicText] ->
      publishState topicText
    ["ctl", "failsafe"] ->
      runCtl CommandFailsafe
    ["ctl", "power", powerActionText] ->
      publishPowerCtl powerActionText
    ["ctl", "logout"] ->
      runCtl CommandLogout
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
      hPutStrLn stderr "       nscde-runtime ctl color-select PALETTE COLORS"
      hPutStrLn stderr "       nscde-runtime ctl backdrop-select DESK MODE IMAGE"
      hPutStrLn stderr "       nscde-runtime ctl style-set KEY VALUE"
      hPutStrLn stderr "       nscde-runtime ctl style-apply"
      hPutStrLn stderr "       nscde-runtime ctl refresh <keybinds|menu|rc|theme|session>"
      hPutStrLn stderr "       nscde-runtime ctl publish-state TOPIC"
      hPutStrLn stderr "       nscde-runtime ctl window <activate|close|minimize|restore|maximize> ID"
      hPutStrLn stderr "       nscde-runtime ctl failsafe"
      hPutStrLn stderr "       nscde-runtime ctl power <poweroff|reboot|suspend|hybrid-suspend|hibernate>"
      hPutStrLn stderr "       nscde-runtime ctl logout"
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
  let updatedEnv = [("NSCDE_LABWC_CONFIG_DIR", configDir), ("NSCDE_LABWC_TERMINAL", terminal)] ++ env
  runtimeContext <- RuntimeLabwc.loadRuntimeLabwcContext updatedEnv
  RuntimeLabwc.refreshLabwcArtifact runtimeContext RefreshMenu

publishLabwcKeybindXml :: IO ()
publishLabwcKeybindXml = do
  env <- getEnvironment
  bindings <- buildKeybinds env
  putStr (renderKeyboardXml bindings)

publishLabwcTheme :: IO ()
publishLabwcTheme = do
  env <- getEnvironment
  runtimeContext <- RuntimeLabwc.loadRuntimeLabwcContext env
  RuntimeLabwc.refreshLabwcArtifact runtimeContext RefreshTheme

publishLabwcRcXml :: FilePath -> IO ()
publishLabwcRcXml configDir = do
  env <- getEnvironment
  runtimeContext <-
    RuntimeLabwc.loadRuntimeLabwcContext
      (("NSCDE_LABWC_CONFIG_DIR", configDir) : env)
  RuntimeLabwc.refreshLabwcArtifact runtimeContext RefreshRc

publishLabwcSessionFiles :: FilePath -> IO ()
publishLabwcSessionFiles configDir = do
  env <- getEnvironment
  runtimeContext <-
    RuntimeLabwc.loadRuntimeLabwcContext
      (("NSCDE_LABWC_CONFIG_DIR", configDir) : env)
  RuntimeLabwc.refreshLabwcArtifact runtimeContext RefreshSession

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

publishPowerCtl :: String -> IO ()
publishPowerCtl powerActionText =
  case powerActionText of
    "poweroff" -> runCtl (CommandPower PowerShutdown)
    "reboot" -> runCtl (CommandPower PowerReboot)
    "suspend" -> runCtl (CommandPower PowerSuspend)
    "hybrid-suspend" -> runCtl (CommandPower PowerHybridSuspend)
    "hibernate" -> runCtl (CommandPower PowerHibernate)
    _ -> do
      hPutStrLn stderr ("Unsupported power action: " ++ powerActionText)
      exitFailure

publishRefreshCtl :: String -> IO ()
publishRefreshCtl refreshTargetText =
  case parseRuntimeRefreshTarget refreshTargetText of
    Just refreshTarget ->
      runCtl (CommandRefresh refreshTarget)
    Nothing -> do
      hPutStrLn stderr ("Unsupported refresh target: " ++ refreshTargetText)
      exitFailure

publishColorSelectCtl :: String -> String -> IO ()
publishColorSelectCtl paletteName colorCountText =
  case reads colorCountText of
    [(colorCount, "")] ->
      runCtl (CommandColorSelect paletteName colorCount)
    _ -> do
      hPutStrLn stderr ("Invalid color count: " ++ colorCountText)
      exitFailure

publishBackdropSelectCtl :: String -> String -> String -> IO ()
publishBackdropSelectCtl deskText modeText imageName =
  case reads deskText of
    [(deskNumber, "")] ->
      runCtl (CommandBackdropSelect deskNumber modeText imageName)
    _ -> do
      hPutStrLn stderr ("Invalid desk number: " ++ deskText)
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
