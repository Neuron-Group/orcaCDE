module NsCDE.Policy.SessionPlan
  ( buildRcConfig
  , buildSessionPlan
  ) where

import Data.Char (isSpace)
import System.FilePath ((</>))

import NsCDE.Domain.Session
import NsCDE.Foundation.EnvFile (KeyValue)
import NsCDE.Foundation.Settings (lookupText)

buildSessionPlan :: [KeyValue] -> SessionPlan
buildSessionPlan env =
  SessionPlan
    { sessionAutostartLines =
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
        , renderCommand runtimeBin ++ " daemon &"
        , renderCommand (toolsDir </> "nscde_labwc_pagerd") ++ " &"
        , renderCommand (toolsDir </> "nscde_labwc_toplevel") ++ " &"
        , renderCommand (toolsDir </> "nscde_labwc_taskd") ++ " &"
        , renderCommand (toolsDir </> "nscde_labwc_bg") ++ " &"
        , renderCommand (toolsDir </> "nscde_labwc_paneld") ++ " &"
        ]
        ++ renderTerminalLaunch autostartTerminal terminal
    , sessionEnvironmentEntries =
        [ ("NSCDE_BACKEND", "labwc")
        , ("NSCDE_ROOT", nsRoot)
        , ("NSCDE_TOOLSDIR", toolsDir)
        , ("NSCDE_DATADIR", dataDir)
        , ("FVWM_USERDIR", fvwmUserDir)
        , ("NSCDE_PALETTE_FILE", paletteFile)
        , ("NSCDE_LABWC_THEME_NAME", themeName)
        , ("NSCDE_LABWC_WORKSPACES", workspaces)
        , ("NSCDE_LABWC_CURRENT_WORKSPACE", currentWorkspace)
        , ("NSCDE_LABWC_AUTOSTART_TERMINAL", autostartTerminal)
        , ("NSCDE_LABWC_TERMINAL", terminal)
        , ("NSCDE_STATE_DIR", stateDir)
        , ("NSCDE_COMMAND_FIFO", commandFifo)
        , ("NSCDE_PANEL_LAYOUT_EXTERNAL", panelLayoutExternal)
        , ("NSCDE_RUNTIME_BIN", runtimeBin)
        , ("NSCDE_STATIC_PANEL_LAYOUT_FILE", staticPanelLayoutFile)
        , ("NSCDE_STATIC_SESSION_ENV_FILE", staticSessionEnvFile)
        , ("XDG_CURRENT_DESKTOP", "NsCDE")
        , ("XDG_SESSION_DESKTOP", "NsCDE")
        , ("DESKTOP_SESSION", "NsCDE")
        , ("XDG_SESSION_TYPE", "wayland")
        , ("XDG_CONFIG_HOME", lookupText env "XDG_CONFIG_HOME" (homeDir ++ "/.config"))
        , ("XDG_CACHE_HOME", lookupText env "XDG_CACHE_HOME" (homeDir ++ "/.cache"))
        , ("XDG_DATA_HOME", lookupText env "XDG_DATA_HOME" (homeDir ++ "/.local/share"))
        ]
    , sessionShutdownLines =
        [ "#!/bin/sh"
        , "exit 0"
        ]
    }
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

buildRcConfig :: [KeyValue] -> String -> RcConfig
buildRcConfig env keybindXml =
  RcConfig
    { rcThemeName = themeName
    , rcFollowMouse = followMouse
    , rcRaiseOnFocus = raiseOnFocus
    , rcFonts =
        [ RcFont "ActiveWindow" fontName fontSize fontSlant fontWeight
        , RcFont "InactiveWindow" fontName fontSize fontSlant fontWeight
        ]
    , rcWorkspaces = resolveWorkspaces env
    , rcKeybindXml = keybindXml
    }
  where
    themeName = lookupText env "NSCDE_THEME_NAME" (lookupText env "NSCDE_LABWC_THEME_NAME" "NsCDE-Stage1")
    followMouse = lookupText env "NSCDE_LABWC_FOLLOW_MOUSE" "yes"
    raiseOnFocus = lookupText env "NSCDE_LABWC_RAISE_ON_FOCUS" "no"
    fontName = lookupText env "NSCDE_LABWC_TITLE_FONT_NAME" "Sans"
    fontSize = lookupText env "NSCDE_LABWC_TITLE_FONT_SIZE" "10"
    fontSlant = lookupText env "NSCDE_LABWC_TITLE_FONT_SLANT" "normal"
    fontWeight = lookupText env "NSCDE_LABWC_TITLE_FONT_WEIGHT" "bold"

resolveWorkspaces :: [KeyValue] -> [String]
resolveWorkspaces env =
  case splitCommaList workspaceText of
    [] -> ["One", "Two", "Three", "Four"]
    names -> names
  where
    workspaceText = lookupText env "NSCDE_WORKSPACES" (lookupText env "NSCDE_LABWC_WORKSPACES" "")

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
