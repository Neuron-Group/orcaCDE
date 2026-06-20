module NsCDE.Policy.Keybinds
  ( buildKeybinds
  , resolveTerminal
  ) where

import Data.Char (toLower)
import System.Directory (findExecutable)

import NsCDE.Domain.Keybinds
import NsCDE.Foundation.EnvFile (KeyValue)
import NsCDE.Foundation.Settings (lookupText)
import NsCDE.Parse.Keybindings (ParsedKeybinding(..), loadParsedKeybindings)

buildKeybinds :: [KeyValue] -> IO [KeybindBinding]
buildKeybinds env = do
  terminal <- resolveTerminal env
  parsed <- loadParsedKeybindings env
  let dynamicBindings = mapMaybe (resolveParsedBinding terminal env) parsed
      mediaBindings = buildMediaBindings env
      defaultBindings = buildDefaultBindings terminal
  pure (dedupeBindings (dynamicBindings ++ mediaBindings ++ defaultBindings))

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

resolveParsedBinding :: String -> [KeyValue] -> ParsedKeybinding -> Maybe KeybindBinding
resolveParsedBinding terminal env parsedBinding = do
  if shouldKeepContext (parsedContext parsedBinding)
    then do
      mappedKey <- mapKeyWithModifier (parsedModifier parsedBinding) (parsedKeyName parsedBinding)
      actions <- mapAction terminal env (parsedAction parsedBinding)
      Just (binding mappedKey actions)
    else Nothing

shouldKeepContext :: String -> Bool
shouldKeepContext contextName =
  case contextName of
    "R" -> True
    "A" -> True
    "W" -> True
    "F" -> False
    "S" -> False
    "T" -> False
    "I" -> False
    _ ->
      not
        (or
          [ "FrontPanel" `isPrefixOf` contextName
          , "NsCDE" `isPrefixOf` contextName
          , "LocalPager" `isPrefixOf` contextName
          , "GWMPager" `isPrefixOf` contextName
          , "GlobalPager" `isPrefixOf` contextName
          , "term" `isInfixOfIgnoreCase` contextName
          , "terminal" `isInfixOfIgnoreCase` contextName
          ])

mapKeyWithModifier :: String -> String -> Maybe String
mapKeyWithModifier modifierName keyName = do
  keyValue <- mapKey keyName
  pure (mapModifier modifierName ++ keyValue)

mapModifier :: String -> String
mapModifier modifierName =
  case modifierName of
    "N" -> ""
    "" -> ""
    "A" -> ""
    _ -> concatMap mapModifierChar modifierName
  where
    mapModifierChar 'C' = "C-"
    mapModifierChar 'S' = "S-"
    mapModifierChar 'M' = "A-"
    mapModifierChar '4' = "W-"
    mapModifierChar 'A' = ""
    mapModifierChar _ = ""

mapKey :: String -> Maybe String
mapKey keyName =
  Just $
    case keyName of
      "Page_Up" -> "Prior"
      "Prior" -> "Prior"
      "Page_Down" -> "Next"
      "Next" -> "Next"
      [single] -> [single]
      ('X':'F':'8':'6':_) -> keyName
      ('S':'u':'n':_) -> keyName
      _ -> normalizeKey keyName

normalizeKey :: String -> String
normalizeKey keyName =
  case keyName of
    "Return" -> "Return"
    "Tab" -> "Tab"
    "Escape" -> "Escape"
    "Space" -> "Space"
    "BackSpace" -> "BackSpace"
    "Delete" -> "Delete"
    "Home" -> "Home"
    "End" -> "End"
    "Insert" -> "Insert"
    "Up" -> "Up"
    "Down" -> "Down"
    "Left" -> "Left"
    "Right" -> "Right"
    "F1" -> "F1"
    "F2" -> "F2"
    "F3" -> "F3"
    "F4" -> "F4"
    "F5" -> "F5"
    "F6" -> "F6"
    "F7" -> "F7"
    "F8" -> "F8"
    "F9" -> "F9"
    "F10" -> "F10"
    "F11" -> "F11"
    "F12" -> "F12"
    "Menu" -> "Menu"
    _ -> map toLower keyName

mapAction :: String -> [KeyValue] -> String -> Maybe [KeybindAction]
mapAction _ _ actionText
  | actionText == "Scroll 0 100000" =
      Just [simpleAction "GoToDesktop" [("to", "right"), ("wrap", "yes")]]
  | actionText == "Scroll 0 -100000" =
      Just [simpleAction "GoToDesktop" [("to", "left"), ("wrap", "yes")]]
  | "Scroll " `isPrefixOf` actionText = Nothing
  | "f_GotoDesk " `isPrefixOf` actionText = Nothing
  | matchesAnyPrefix actionText ["Next ", "Next\t"] && containsAny actionText ["AcceptsFocus", "FlipFocus", "Focus"] =
      Just [simpleAction "NextWindow" []]
  | matchesAnyPrefix actionText ["Prev ", "Prev\t"] && containsAny actionText ["AcceptsFocus", "FlipFocus", "Focus"] =
      Just [simpleAction "PreviousWindow" []]
  | actionText == "Close" = Just [simpleAction "Close" []]
  | actionText == "Iconify" = Just [simpleAction "Iconify" []]
  | actionText == "Maximize" = Just [simpleAction "ToggleMaximize" []]
  | "f_ButtonMaximize" `isPrefixOf` actionText = Just [simpleAction "ToggleMaximize" []]
  | "WindowShade" `isPrefixOf` actionText = Just [simpleAction "ToggleShade" []]
  | actionText == "Raise" = Just [simpleAction "Raise" []]
  | actionText == "Lower" = Just [simpleAction "Lower" []]
  | actionText == "RaiseLower" = Just [simpleAction "ToggleAlwaysOnTop" []]
  | actionText == "Move" = Just [simpleAction "Move" []]
  | containsSubstring "Resize" actionText || "f_StatefulResize" `isPrefixOf` actionText =
      Just [simpleAction "Resize" []]
  | "Exec exec " `isPrefixOf` actionText =
      let command = trimQuotes (drop (length ("Exec exec " :: String)) actionText)
      in if containsSubstring "$[" command
           then Nothing
           else Just [commandAction command]
  | "Exec " `isPrefixOf` actionText =
      let command = trimQuotes (drop (length ("Exec " :: String)) actionText)
      in if containsSubstring "$[" command
           then Nothing
           else Just [commandAction command]
  | "Menu MenuFvwmRoot" `isPrefixOf` actionText || "Menu m_WindowOpsRootWin" `isPrefixOf` actionText =
      Just [simpleAction "ShowMenu" [("menu", "root-menu")]]
  | "Menu " `isPrefixOf` actionText =
      Just [simpleAction "ShowMenu" [("menu", "root-menu")]]
  | actionText == "f_RootMenu" =
      Just [simpleAction "ShowMenu" [("menu", "root-menu")]]
  | "WindowList" `isPrefixOf` actionText || "f_WinLists" `isPrefixOf` actionText =
      Just [simpleAction "ShowMenu" [("menu", "client-list-combined-menu")]]
  | actionText == "Refresh" = Just [simpleAction "Reconfigure" []]
  | actionText == "Nop" = Nothing
  | shouldSkipAction actionText = Nothing
  | otherwise = Nothing
simpleAction :: String -> [(String, String)] -> KeybindAction
simpleAction name attrs =
  KeybindAction
    { keybindActionName = name
    , keybindActionAttrs = attrs
    , keybindActionCommand = Nothing
    }

commandAction :: String -> KeybindAction
commandAction command =
  KeybindAction
    { keybindActionName = "Execute"
    , keybindActionAttrs = []
    , keybindActionCommand = Just command
    }

buildMediaBindings :: [KeyValue] -> [KeybindBinding]
buildMediaBindings env =
  [ binding "XF86AudioLowerVolume" [commandAction "pactl set-sink-volume @DEFAULT_SINK@ -5%"]
  , binding "XF86AudioRaiseVolume" [commandAction "pactl set-sink-volume @DEFAULT_SINK@ +5%"]
  , binding "XF86AudioMute" [commandAction "pactl set-sink-mute @DEFAULT_SINK@ toggle"]
  , binding "A-Home" [commandAction styleManagerCommand]
  ]
  where
    toolsDir = lookupText env "NSCDE_TOOLSDIR" ""
    dataDir = lookupText env "NSCDE_DATADIR" ""
    styleManagerCommand =
      "sh -c "
        ++ quoteDouble
          ("QT_QPA_PLATFORM=wayland NSCDE_BACKEND=labwc NSCDE_TOOLSDIR="
            ++ toolsDir
            ++ " NSCDE_DATADIR="
            ++ dataDir
            ++ " "
            ++ toolsDir
            ++ "/nscde_labwc_stylemgr")

buildDefaultBindings :: String -> [KeybindBinding]
buildDefaultBindings terminal =
  [ binding "W-Return" [commandAction terminal]
  , binding "Menu" [simpleAction "ShowMenu" [("menu", "root-menu")]]
  , binding "A-Space" [simpleAction "ShowMenu" [("menu", "root-menu")]]
  , binding "A-Escape" [simpleAction "ShowMenu" [("menu", "client-list-combined-menu")]]
  , binding "C-Left" [simpleAction "GoToDesktop" [("to", "left"), ("wrap", "yes")]]
  , binding "C-Right" [simpleAction "GoToDesktop" [("to", "right"), ("wrap", "yes")]]
  , binding "C-Up" [simpleAction "GoToDesktop" [("to", "up"), ("wrap", "yes")]]
  , binding "C-Down" [simpleAction "GoToDesktop" [("to", "down"), ("wrap", "yes")]]
  , binding "A-Tab" [simpleAction "NextWindow" []]
  , binding "A-S-Tab" [simpleAction "PreviousWindow" []]
  , binding "A-F4" [simpleAction "Close" []]
  , binding "W-Home" [simpleAction "ShowMenu" [("menu", "client-list-combined-menu")]]
  ]

binding :: String -> [KeybindAction] -> KeybindBinding
binding keyValue actions =
  KeybindBinding
    { keybindKey = keyValue
    , keybindActions = actions
    }

dedupeBindings :: [KeybindBinding] -> [KeybindBinding]
dedupeBindings bindings =
  reverse (foldl keepLatest [] (reverse bindings))
  where
    keepLatest acc bindingValue =
      if any ((== keybindKey bindingValue) . keybindKey) acc
        then acc
        else bindingValue : acc

trimQuotes :: String -> String
trimQuotes value =
  case value of
    '"':rest ->
      case reverse rest of
        '"':remaining -> reverse remaining
        _ -> value
    _ -> value

quoteDouble :: String -> String
quoteDouble value =
  "\"" ++ concatMap escapeChar value ++ "\""
  where
    escapeChar '"' = "\\\""
    escapeChar ch = [ch]

containsAny :: String -> [String] -> Bool
containsAny _ [] = False
containsAny haystack (needle:rest) =
  containsSubstring needle haystack || containsAny haystack rest

matchesAnyPrefix :: String -> [String] -> Bool
matchesAnyPrefix _ [] = False
matchesAnyPrefix value (prefix:rest) =
  isPrefixOf prefix value || matchesAnyPrefix value rest

containsSubstring :: String -> String -> Bool
containsSubstring needle haystack =
  any (isPrefixOf needle) (tails haystack)

tails :: [a] -> [[a]]
tails [] = [[]]
tails value@(_:rest) = value : tails rest

isPrefixOf :: Eq a => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (left:leftRest) (right:rightRest) =
  left == right && isPrefixOf leftRest rightRest

isInfixOfIgnoreCase :: String -> String -> Bool
isInfixOfIgnoreCase needle haystack =
  containsSubstring (map toLower needle) (map toLower haystack)

shouldSkipAction :: String -> Bool
shouldSkipAction actionText =
  containsAny actionText
    [ "$["
    , "f_GotoDesk"
    , "f_SwitchFocus"
    , "f_FlipOverlapped"
    , "f_BrowseIcons"
    , "f_ToggleFvwm"
    , "f_ShowFPPGMenu"
    , "f_TileWindows"
    , "f_Zoom"
    , "f_Rofi"
    , "f_CleanRestore"
    , "f_RaiseLowerX"
    , "f_SendToOccupy"
    , "f_Find"
    , "f_KeyFromFp"
    , "f_KeyFromSub"
    , "f_Mixer"
    , "f_WideTerm"
    , "f_DoubleBindKey"
    , "f_KeyShowLocalPager"
    , "f_ShowGlobalPager"
    , "f_HideLocalPager"
    , "f_RepositionWindow"
    , "f_Xscreensaver"
    , "f_ToggleExecWindow"
    , "f_DisplayURL"
    , "f_RunQuickScriptDialog"
    , "f_RestoreFrontPanel"
    , "f_IconOps"
    , "SendToModule"
    , "CursorMove"
    , "FakeClick"
    , "WarpToWindow"
    , "CurrentPage"
    , "CurrentDesk"
    , "ThisWindow"
    , "FrontPanel"
    , "Subpanel"
    , "Occupy"
    , "GWM"
    , "LocalPager"
    , "Iconic"
    , "IconMan"
    , "FvwmScript"
    , "FvwmButtons"
    , "FvwmPager"
    ]

mapMaybe :: (a -> Maybe b) -> [a] -> [b]
mapMaybe _ [] = []
mapMaybe function (value:rest) =
  case function value of
    Nothing -> mapMaybe function rest
    Just result -> result : mapMaybe function rest
