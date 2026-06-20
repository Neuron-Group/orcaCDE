module Main (main) where

import System.Environment (getArgs, getEnv)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

import NsCDE.Runtime.EnvFile (renderEnvFile)
import NsCDE.Runtime.LabwcMenu (publishLabwcMenuXml)
import NsCDE.Runtime.LabwcSession (publishLabwcRcXml, publishLabwcSessionFiles)
import NsCDE.Runtime.PanelLayout (emitPanelLayout, loadStaticPanelProfile)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["panel-layout", "publish"] -> publishPanelLayout Nothing
    ["panel-layout", "publish", staticPath] -> publishPanelLayout (Just staticPath)
    ["labwc-menu", "publish", configDir] -> publishLabwcMenuXml configDir
    ["labwc-rc", "publish", configDir] -> publishLabwcRcXml configDir
    ["labwc-session", "publish", configDir] -> publishLabwcSessionFiles configDir
    _ -> do
      hPutStrLn stderr "Usage: nscde-runtime panel-layout publish [STATIC_PANEL_LAYOUT_FILE]"
      hPutStrLn stderr "       nscde-runtime labwc-menu publish CONFIG_DIR"
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
