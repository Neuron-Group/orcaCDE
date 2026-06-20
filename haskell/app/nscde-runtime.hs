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
import NsCDE.Foundation.Common (writeAtomicFile)
import NsCDE.Foundation.EnvFile (renderEnvFile)
import NsCDE.Foundation.Settings (lookupText)
import NsCDE.Parse.AppMenus (loadAppMenuEntries)
import NsCDE.Policy.Keybinds (buildKeybinds, resolveTerminal)
import NsCDE.Policy.Menu (buildMenuModel)
import NsCDE.Policy.PanelLayout (emitPanelLayout, loadStaticPanelProfile)
import NsCDE.Policy.SessionPlan (buildRcConfig, buildSessionPlan)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["panel-layout", "publish"] -> publishPanelLayout Nothing
    ["panel-layout", "publish", staticPath] -> publishPanelLayout (Just staticPath)
    ["labwc-menu", "publish", configDir] -> publishLabwcMenuXml configDir
    ["labwc-keybinds", "publish"] -> publishLabwcKeybindXml
    ["labwc-rc", "publish", configDir] -> publishLabwcRcXml configDir
    ["labwc-session", "publish", configDir] -> publishLabwcSessionFiles configDir
    _ -> do
      hPutStrLn stderr "Usage: nscde-runtime panel-layout publish [STATIC_PANEL_LAYOUT_FILE]"
      hPutStrLn stderr "       nscde-runtime labwc-menu publish CONFIG_DIR"
      hPutStrLn stderr "       nscde-runtime labwc-keybinds publish"
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

publishLabwcRcXml :: FilePath -> IO ()
publishLabwcRcXml configDir = do
  env <- getEnvironment
  keybindXml <- readOptionalFile (lookupText env "NSCDE_LABWC_KEYBIND_XML_FILE" "")
  createDirectoryIfMissing True configDir
  writeAtomicFile (configDir </> "rc.xml") (renderRcXml (buildRcConfig env keybindXml))

publishLabwcSessionFiles :: FilePath -> IO ()
publishLabwcSessionFiles configDir = do
  env <- getEnvironment
  let plan = buildSessionPlan env
  createDirectoryIfMissing True configDir
  writeAtomicFile (configDir </> "autostart") (renderAutostart plan)
  writeAtomicFile (configDir </> "environment") (renderEnvironment plan)
  writeAtomicFile (configDir </> "shutdown") (renderShutdown plan)

readOptionalFile :: FilePath -> IO String
readOptionalFile "" = pure ""
readOptionalFile path = do
  exists <- doesFileExist path
  if exists
    then readFile path
    else pure ""
