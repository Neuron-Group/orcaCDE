module NsCDE.Runtime.LabwcSession
  ( publishLabwcRcXml
  , publishLabwcSessionFiles
  ) where

import Data.Char (isSpace)
import Data.List (find)
import System.Directory (createDirectoryIfMissing, doesFileExist, renameFile)
import System.Environment (getEnvironment)
import System.FilePath ((</>))

import NsCDE.Runtime.EnvFile (KeyValue, renderEnvFile)

publishLabwcSessionFiles :: FilePath -> IO ()
publishLabwcSessionFiles configDir = do
  env <- getEnvironment
  createDirectoryIfMissing True configDir
  writeAtomicFile (configDir </> "autostart") (renderAutostart env)
  writeAtomicFile (configDir </> "environment") (renderEnvironment env)
  writeAtomicFile (configDir </> "shutdown") renderShutdown

publishLabwcRcXml :: FilePath -> IO ()
publishLabwcRcXml configDir = do
  env <- getEnvironment
  keybindXml <- readOptionalFile (lookupText env "NSCDE_LABWC_KEYBIND_XML_FILE" "")
  createDirectoryIfMissing True configDir
  writeAtomicFile (configDir </> "rc.xml") (renderRcXml env keybindXml)

renderAutostart :: [KeyValue] -> String
renderAutostart env =
  unlines $
    [ "#!/bin/sh"
    , renderShellExport "NSCDE_BACKEND" "labwc"
    , renderShellExport "NSCDE_ROOT" nsRoot
    , renderShellExport "NSCDE_TOOLSDIR" toolsDir
    , renderShellExport "NSCDE_DATADIR" dataDir
    , renderShellExport "FVWM_USERDIR" fvwmUserDir
    , renderShellExport "NSCDE_LABWC_THEME_NAME" themeName
    , renderShellExport "NSCDE_LABWC_WORKSPACES" workspaces
    , renderShellExport "NSCDE_LABWC_CURRENT_WORKSPACE" currentWorkspace
    , renderShellExport "NSCDE_LABWC_AUTOSTART_TERMINAL" autostartTerminal
    , renderShellExport "NSCDE_LABWC_TERMINAL" terminal
    , renderShellExport "NSCDE_STATE_DIR" stateDir
    , renderShellExport "NSCDE_COMMAND_FIFO" commandFifo
    , renderShellExport "NSCDE_PALETTE_FILE" paletteFile
    , renderPathExport (nsRoot ++ "/bin")
    , renderShellExport "XDG_CURRENT_DESKTOP" "NsCDE"
    , renderShellExport "XDG_SESSION_DESKTOP" "NsCDE"
    , renderShellExport "DESKTOP_SESSION" "NsCDE"
    , renderShellExport "XDG_SESSION_TYPE" "wayland"
    , renderShellExport "NSCDE_PANEL_LAYOUT_EXTERNAL" panelLayoutExternal
    , renderShellExport "NSCDE_RUNTIME_BIN" runtimeBin
    , renderShellExport "NSCDE_STATIC_PANEL_LAYOUT_FILE" staticPanelLayoutFile
    , renderShellExport "NSCDE_STATIC_SESSION_ENV_FILE" staticSessionEnvFile
    , renderCommand (toolsDir </> "nscde_sessiond") ++ " &"
    , renderCommand (toolsDir </> "nscde_labwc_pagerd") ++ " &"
    , renderCommand (toolsDir </> "nscde_labwc_toplevel") ++ " &"
    , renderCommand (toolsDir </> "nscde_labwc_taskd") ++ " &"
    , renderCommand (toolsDir </> "nscde_labwc_bg") ++ " &"
    , renderCommand (toolsDir </> "nscde_labwc_paneld") ++ " &"
    ] ++ renderTerminalLaunch autostartTerminal terminal
  where
    nsRoot = lookupText env "NSCDE_ROOT" ""
    toolsDir = lookupText env "NSCDE_TOOLSDIR" ""
    dataDir = lookupText env "NSCDE_DATADIR" ""
    homeDir = lookupText env "HOME" ""
    fvwmUserDir = lookupText env "FVWM_USERDIR" (homeDir ++ "/.NsCDE")
    themeName = lookupText env "NSCDE_THEME_NAME" (lookupText env "NSCDE_LABWC_THEME_NAME" "NsCDE-Stage1")
    workspaces = lookupText env "NSCDE_WORKSPACES" (lookupText env "NSCDE_LABWC_WORKSPACES" "One,Two,Three,Four")
    currentWorkspace = lookupText env "NSCDE_CURRENT_WORKSPACE" (lookupText env "NSCDE_LABWC_CURRENT_WORKSPACE" "One")
    autostartTerminal = lookupText env "NSCDE_LABWC_AUTOSTART_TERMINAL" "1"
    terminal = lookupText env "NSCDE_LABWC_TERMINAL" "xterm"
    stateDir = lookupText env "NSCDE_STATE_DIR" ""
    commandFifo = lookupText env "NSCDE_COMMAND_FIFO" ""
    paletteFile = lookupText env "NSCDE_PALETTE_FILE" ""
    panelLayoutExternal = lookupText env "NSCDE_PANEL_LAYOUT_EXTERNAL" "0"
    runtimeBin = lookupText env "NSCDE_RUNTIME_BIN" "nscde-runtime"
    staticPanelLayoutFile = lookupText env "NSCDE_STATIC_PANEL_LAYOUT_FILE" ""
    staticSessionEnvFile = lookupText env "NSCDE_STATIC_SESSION_ENV_FILE" ""

renderEnvironment :: [KeyValue] -> String
renderEnvironment env =
  renderEnvFile
    [ ("NSCDE_BACKEND", "labwc")
    , ("NSCDE_ROOT", lookupText env "NSCDE_ROOT" "")
    , ("NSCDE_TOOLSDIR", lookupText env "NSCDE_TOOLSDIR" "")
    , ("NSCDE_DATADIR", lookupText env "NSCDE_DATADIR" "")
    , ("FVWM_USERDIR", lookupText env "FVWM_USERDIR" (lookupText env "HOME" "" ++ "/.NsCDE"))
    , ("NSCDE_PALETTE_FILE", lookupText env "NSCDE_PALETTE_FILE" "")
    , ("NSCDE_LABWC_THEME_NAME", lookupText env "NSCDE_THEME_NAME" (lookupText env "NSCDE_LABWC_THEME_NAME" "NsCDE-Stage1"))
    , ("NSCDE_LABWC_WORKSPACES", lookupText env "NSCDE_WORKSPACES" (lookupText env "NSCDE_LABWC_WORKSPACES" "One,Two,Three,Four"))
    , ("NSCDE_LABWC_CURRENT_WORKSPACE", lookupText env "NSCDE_CURRENT_WORKSPACE" (lookupText env "NSCDE_LABWC_CURRENT_WORKSPACE" "One"))
    , ("NSCDE_LABWC_AUTOSTART_TERMINAL", lookupText env "NSCDE_LABWC_AUTOSTART_TERMINAL" "1")
    , ("NSCDE_LABWC_TERMINAL", lookupText env "NSCDE_LABWC_TERMINAL" "xterm")
    , ("NSCDE_STATE_DIR", lookupText env "NSCDE_STATE_DIR" "")
    , ("NSCDE_COMMAND_FIFO", lookupText env "NSCDE_COMMAND_FIFO" "")
    , ("NSCDE_PANEL_LAYOUT_EXTERNAL", lookupText env "NSCDE_PANEL_LAYOUT_EXTERNAL" "0")
    , ("NSCDE_RUNTIME_BIN", lookupText env "NSCDE_RUNTIME_BIN" "nscde-runtime")
    , ("NSCDE_STATIC_PANEL_LAYOUT_FILE", lookupText env "NSCDE_STATIC_PANEL_LAYOUT_FILE" "")
    , ("NSCDE_STATIC_SESSION_ENV_FILE", lookupText env "NSCDE_STATIC_SESSION_ENV_FILE" "")
    , ("XDG_CURRENT_DESKTOP", "NsCDE")
    , ("XDG_SESSION_DESKTOP", "NsCDE")
    , ("DESKTOP_SESSION", "NsCDE")
    , ("XDG_SESSION_TYPE", "wayland")
    , ("XDG_CONFIG_HOME", lookupText env "XDG_CONFIG_HOME" (lookupText env "HOME" "" ++ "/.config"))
    , ("XDG_CACHE_HOME", lookupText env "XDG_CACHE_HOME" (lookupText env "HOME" "" ++ "/.cache"))
    , ("XDG_DATA_HOME", lookupText env "XDG_DATA_HOME" (lookupText env "HOME" "" ++ "/.local/share"))
    ]

renderShutdown :: String
renderShutdown =
  unlines
    [ "#!/bin/sh"
    , "exit 0"
    ]

renderRcXml :: [KeyValue] -> String -> String
renderRcXml env keybindXml =
  concat
    [ "<?xml version=\"1.0\"?>\n"
    , "<labwc_config>\n"
    , "  <core>\n"
    , "    <decoration>server</decoration>\n"
    , "    <gap>0</gap>\n"
    , "  </core>\n"
    , "  <focus>\n"
    , "    <followMouse>" ++ escapeXml followMouse ++ "</followMouse>\n"
    , "    <raiseOnFocus>" ++ escapeXml raiseOnFocus ++ "</raiseOnFocus>\n"
    , "  </focus>\n"
    , "  <theme>\n"
    , "    <name>" ++ escapeXml themeName ++ "</name>\n"
    , "    <cornerRadius>0</cornerRadius>\n"
    , "    <titlebar>\n"
    , "      <layout>menu:iconify,max</layout>\n"
    , "    </titlebar>\n"
    , renderWindowFont "ActiveWindow"
    , renderWindowFont "InactiveWindow"
    , "  </theme>\n"
    , "  <desktops>\n"
    , "    <number>" ++ show (length workspaces) ++ "</number>\n"
    , "    <names>\n"
    , concatMap renderWorkspaceName workspaces
    , "    </names>\n"
    , "  </desktops>\n"
    , renderKeybindXml keybindXml
    , "  <mouse>\n"
    , "    <default />\n"
    , "    <doubleClickTime>500</doubleClickTime>\n"
    , "    <context name=\"Root\">\n"
    , "      <mousebind button=\"Left\" action=\"Press\">\n"
    , "        <action name=\"ShowMenu\" menu=\"root-menu\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind button=\"Right\" action=\"Press\">\n"
    , "        <action name=\"ShowMenu\" menu=\"root-menu\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind direction=\"Up\" action=\"Scroll\">\n"
    , "        <action name=\"GoToDesktop\" to=\"left\" wrap=\"yes\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind direction=\"Down\" action=\"Scroll\">\n"
    , "        <action name=\"GoToDesktop\" to=\"right\" wrap=\"yes\" />\n"
    , "      </mousebind>\n"
    , "    </context>\n"
    , "    <context name=\"TitleBar\">\n"
    , "      <mousebind button=\"Left\" action=\"Press\">\n"
    , "        <action name=\"Focus\" />\n"
    , "        <action name=\"Raise\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind button=\"Right\" action=\"Click\">\n"
    , "        <action name=\"Focus\" />\n"
    , "        <action name=\"Raise\" />\n"
    , "        <action name=\"ShowMenu\" menu=\"client-menu\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind direction=\"Up\" action=\"Scroll\">\n"
    , "        <action name=\"Unshade\" />\n"
    , "        <action name=\"Focus\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind direction=\"Down\" action=\"Scroll\">\n"
    , "        <action name=\"Shade\" />\n"
    , "      </mousebind>\n"
    , "    </context>\n"
    , "    <context name=\"Title\">\n"
    , "      <mousebind button=\"Left\" action=\"Drag\">\n"
    , "        <action name=\"Move\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind button=\"Left\" action=\"DoubleClick\">\n"
    , "        <action name=\"ToggleMaximize\" />\n"
    , "      </mousebind>\n"
    , "      <mousebind button=\"Right\" action=\"Click\">\n"
    , "        <action name=\"ShowMenu\" menu=\"client-menu\" />\n"
    , "      </mousebind>\n"
    , "    </context>\n"
    , "  </mouse>\n"
    , "</labwc_config>\n"
    ]
  where
    themeName = lookupText env "NSCDE_THEME_NAME" (lookupText env "NSCDE_LABWC_THEME_NAME" "NsCDE-Stage1")
    followMouse = lookupText env "NSCDE_LABWC_FOLLOW_MOUSE" "yes"
    raiseOnFocus = lookupText env "NSCDE_LABWC_RAISE_ON_FOCUS" "no"
    fontName = lookupText env "NSCDE_LABWC_TITLE_FONT_NAME" "Sans"
    fontSize = lookupText env "NSCDE_LABWC_TITLE_FONT_SIZE" "10"
    fontSlant = lookupText env "NSCDE_LABWC_TITLE_FONT_SLANT" "normal"
    fontWeight = lookupText env "NSCDE_LABWC_TITLE_FONT_WEIGHT" "bold"
    workspaces = resolveWorkspaces env
    renderWindowFont place =
      concat
        [ "    <font place=\"" ++ place ++ "\">\n"
        , "      <name>" ++ escapeXml fontName ++ "</name>\n"
        , "      <size>" ++ escapeXml fontSize ++ "</size>\n"
        , "      <slant>" ++ escapeXml fontSlant ++ "</slant>\n"
        , "      <weight>" ++ escapeXml fontWeight ++ "</weight>\n"
        , "    </font>\n"
        ]

renderWorkspaceName :: String -> String
renderWorkspaceName workspace =
  "      <name>" ++ escapeXml workspace ++ "</name>\n"

renderKeybindXml :: String -> String
renderKeybindXml keybindXml
  | all isSpace keybindXml = ""
  | otherwise = ensureTrailingNewline keybindXml

resolveWorkspaces :: [KeyValue] -> [String]
resolveWorkspaces env =
  case splitCommaList workspaceText of
    [] -> defaultWorkspaces
    names -> names
  where
    workspaceText = lookupText env "NSCDE_WORKSPACES" (lookupText env "NSCDE_LABWC_WORKSPACES" "")

defaultWorkspaces :: [String]
defaultWorkspaces =
  ["One", "Two", "Three", "Four"]

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

readOptionalFile :: FilePath -> IO String
readOptionalFile "" = pure ""
readOptionalFile path = do
  exists <- doesFileExist path
  if exists
    then readFile path
    else pure ""

renderShellExport :: String -> String -> String
renderShellExport key value =
  "export " ++ key ++ "=" ++ shellQuote value

renderPathExport :: String -> String
renderPathExport prefix =
  "export PATH=" ++ shellQuote prefix ++ ":$PATH"

renderCommand :: String -> String
renderCommand = shellQuote

renderTerminalLaunch :: String -> String -> [String]
renderTerminalLaunch autostartTerminal terminal
  | autostartTerminal == "1" =
      [ "if [ \"$NSCDE_LABWC_AUTOSTART_TERMINAL\" = \"1\" ]; then"
      , "  " ++ renderCommand terminal ++ " &"
      , "fi"
      ]
  | otherwise = []

shellQuote :: String -> String
shellQuote value =
  "'" ++ concatMap escapeChar value ++ "'"
  where
    escapeChar '\'' = "'\"'\"'"
    escapeChar ch = [ch]

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

ensureTrailingNewline :: String -> String
ensureTrailingNewline "" = ""
ensureTrailingNewline value
  | last value == '\n' = value
  | otherwise = value ++ "\n"

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
