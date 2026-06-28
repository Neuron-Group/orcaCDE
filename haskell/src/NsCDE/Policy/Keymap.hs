module NsCDE.Policy.Keymap
  ( buildBindingIntent
  , buildDefaultBindingIntents
  , buildMediaBindingIntents
  , renderBindingIntent
  ) where

import Data.Char (toLower)

import NsCDE.Domain.Keybinds
import NsCDE.Domain.Keymap
import NsCDE.Parse.Keybindings (ParsedKeybinding(..))

buildBindingIntent :: KeymapEnvironment -> ParsedKeybinding -> Maybe KeyBindingIntent
buildBindingIntent keymapEnv parsedBinding =
  if shouldKeepContext (keyContextFromText (parsedContext parsedBinding))
    then do
      mappedKey <- mapKeyName (parsedKeyName parsedBinding)
      actions <- actionIntentsFromText keymapEnv (parsedAction parsedBinding)
      Just
        KeyBindingIntent
          { keyBindingIntentKey = mappedKey
          , keyBindingIntentModifiers = parseModifiers (parsedModifier parsedBinding)
          , keyBindingIntentActions = actions
          }
    else Nothing

buildMediaBindingIntents :: KeymapEnvironment -> [KeyBindingIntent]
buildMediaBindingIntents keymapEnv =
  [ makeBindingIntent "XF86AudioLowerVolume" [] [KeyActionExecute "pactl set-sink-volume @DEFAULT_SINK@ -5%"]
  , makeBindingIntent "XF86AudioRaiseVolume" [] [KeyActionExecute "pactl set-sink-volume @DEFAULT_SINK@ +5%"]
  , makeBindingIntent "XF86AudioMute" [] [KeyActionExecute "pactl set-sink-mute @DEFAULT_SINK@ toggle"]
  , makeBindingIntent "Home" [KeyModifierAlt] [KeyActionExecute styleManagerCommand]
  ]
  where
    styleManagerCommand =
      "sh -c "
        ++ quoteDouble
          ("QT_QPA_PLATFORM=wayland NSCDE_BACKEND=labwc NSCDE_TOOLSDIR="
            ++ keymapToolsDir keymapEnv
            ++ " NSCDE_DATADIR="
            ++ keymapDataDir keymapEnv
            ++ " "
            ++ keymapToolsDir keymapEnv
            ++ "/nscde_labwc_stylemgr")

buildDefaultBindingIntents :: KeymapEnvironment -> [KeyBindingIntent]
buildDefaultBindingIntents keymapEnv =
  [ makeBindingIntent "Return" [KeyModifierSuper] [KeyActionExecute (keymapTerminal keymapEnv)]
  , makeBindingIntent "Menu" [] [KeyActionShowMenu "root-menu"]
  , makeBindingIntent "Space" [KeyModifierAlt] [KeyActionShowMenu "root-menu"]
  , makeBindingIntent "Escape" [KeyModifierAlt] [KeyActionShowMenu "client-list-combined-menu"]
  , makeBindingIntent "Left" [KeyModifierControl] [KeyActionGoToDesktop DesktopLeft True]
  , makeBindingIntent "Right" [KeyModifierControl] [KeyActionGoToDesktop DesktopRight True]
  , makeBindingIntent "Up" [KeyModifierControl] [KeyActionGoToDesktop DesktopUp True]
  , makeBindingIntent "Down" [KeyModifierControl] [KeyActionGoToDesktop DesktopDown True]
  , makeBindingIntent "Tab" [KeyModifierAlt] [KeyActionNextWindow]
  , makeBindingIntent "Tab" [KeyModifierAlt, KeyModifierShift] [KeyActionPreviousWindow]
  , makeBindingIntent "F4" [KeyModifierAlt] [KeyActionClose]
  , makeBindingIntent "Home" [KeyModifierSuper] [KeyActionShowMenu "client-list-combined-menu"]
  ]

renderBindingIntent :: KeyBindingIntent -> KeybindBinding
renderBindingIntent intent =
  KeybindBinding
    { keybindKey =
        renderModifiers (keyBindingIntentModifiers intent)
          ++ keyBindingIntentKey intent
    , keybindActions = map renderActionIntent (keyBindingIntentActions intent)
    }

makeBindingIntent :: String -> [KeyModifier] -> [KeyActionIntent] -> KeyBindingIntent
makeBindingIntent keyValue modifiers actions =
  KeyBindingIntent
    { keyBindingIntentKey = keyValue
    , keyBindingIntentModifiers = modifiers
    , keyBindingIntentActions = actions
    }

renderActionIntent :: KeyActionIntent -> KeybindAction
renderActionIntent actionIntent =
  case actionIntent of
    KeyActionGoToDesktop direction wrapAround ->
      KeybindAction
        { keybindActionName = "GoToDesktop"
        , keybindActionAttrs =
            [ ("to", renderDesktopDirection direction)
            , ("wrap", if wrapAround then "yes" else "no")
            ]
        , keybindActionCommand = Nothing
        }
    KeyActionNextWindow ->
      simpleAction "NextWindow" []
    KeyActionPreviousWindow ->
      simpleAction "PreviousWindow" []
    KeyActionClose ->
      simpleAction "Close" []
    KeyActionIconify ->
      simpleAction "Iconify" []
    KeyActionToggleMaximize ->
      simpleAction "ToggleMaximize" []
    KeyActionToggleShade ->
      simpleAction "ToggleShade" []
    KeyActionRaise ->
      simpleAction "Raise" []
    KeyActionLower ->
      simpleAction "Lower" []
    KeyActionToggleAlwaysOnTop ->
      simpleAction "ToggleAlwaysOnTop" []
    KeyActionMove ->
      simpleAction "Move" []
    KeyActionResize ->
      simpleAction "Resize" []
    KeyActionShowMenu menuName ->
      simpleAction "ShowMenu" [("menu", menuName)]
    KeyActionReconfigure ->
      simpleAction "Reconfigure" []
    KeyActionExecute command ->
      KeybindAction
        { keybindActionName = "Execute"
        , keybindActionAttrs = []
        , keybindActionCommand = Just command
        }

simpleAction :: String -> [(String, String)] -> KeybindAction
simpleAction name attrs =
  KeybindAction
    { keybindActionName = name
    , keybindActionAttrs = attrs
    , keybindActionCommand = Nothing
    }

renderDesktopDirection :: DesktopDirection -> String
renderDesktopDirection direction =
  case direction of
    DesktopLeft -> "left"
    DesktopRight -> "right"
    DesktopUp -> "up"
    DesktopDown -> "down"

renderModifiers :: [KeyModifier] -> String
renderModifiers =
  concatMap renderModifier
  where
    renderModifier KeyModifierControl = "C-"
    renderModifier KeyModifierShift = "S-"
    renderModifier KeyModifierAlt = "A-"
    renderModifier KeyModifierSuper = "W-"

keyContextFromText :: String -> KeyContext
keyContextFromText contextName =
  case contextName of
    "R" -> KeyContextRoot
    "A" -> KeyContextAll
    "W" -> KeyContextWindow
    "F" -> KeyContextFrame
    "S" -> KeyContextSystem
    "T" -> KeyContextTitle
    "I" -> KeyContextIcon
    _ -> KeyContextOther contextName

shouldKeepContext :: KeyContext -> Bool
shouldKeepContext keyContext =
  case keyContext of
    KeyContextRoot -> True
    KeyContextAll -> True
    KeyContextWindow -> True
    KeyContextFrame -> False
    KeyContextSystem -> False
    KeyContextTitle -> False
    KeyContextIcon -> False
    KeyContextOther _ -> False

parseModifiers :: String -> [KeyModifier]
parseModifiers modifierName =
  case modifierName of
    "N" -> []
    "" -> []
    "A" -> []
    _ -> foldr collect [] modifierName
  where
    collect 'C' acc = KeyModifierControl : acc
    collect 'S' acc = KeyModifierShift : acc
    collect 'M' acc = KeyModifierAlt : acc
    collect '4' acc = KeyModifierSuper : acc
    collect 'A' acc = acc
    collect _ acc = acc

mapKeyName :: String -> Maybe String
mapKeyName keyName =
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

actionIntentsFromText :: KeymapEnvironment -> String -> Maybe [KeyActionIntent]
actionIntentsFromText _ actionText
  | actionText == "Scroll 0 100000" =
      Just [KeyActionGoToDesktop DesktopRight True]
  | actionText == "Scroll 0 -100000" =
      Just [KeyActionGoToDesktop DesktopLeft True]
  | "Scroll " `isPrefixOf` actionText = Nothing
  | "f_GotoDesk " `isPrefixOf` actionText = Nothing
  | matchesAnyPrefix actionText ["Next ", "Next\t"] && containsAny actionText ["AcceptsFocus", "FlipFocus", "Focus"] =
      Just [KeyActionNextWindow]
  | matchesAnyPrefix actionText ["Prev ", "Prev\t"] && containsAny actionText ["AcceptsFocus", "FlipFocus", "Focus"] =
      Just [KeyActionPreviousWindow]
  | actionText == "Close" = Just [KeyActionClose]
  | actionText == "Iconify" = Just [KeyActionIconify]
  | actionText == "Maximize" = Just [KeyActionToggleMaximize]
  | "f_ButtonMaximize" `isPrefixOf` actionText = Just [KeyActionToggleMaximize]
  | "WindowShade" `isPrefixOf` actionText = Just [KeyActionToggleShade]
  | actionText == "Raise" = Just [KeyActionRaise]
  | actionText == "Lower" = Just [KeyActionLower]
  | actionText == "RaiseLower" = Just [KeyActionToggleAlwaysOnTop]
  | actionText == "Move" = Just [KeyActionMove]
  | containsSubstring "Resize" actionText || "f_StatefulResize" `isPrefixOf` actionText =
      Just [KeyActionResize]
  | "Exec exec " `isPrefixOf` actionText =
      let command = trimQuotes (drop (length ("Exec exec " :: String)) actionText)
      in if containsSubstring "$[" command
           then Nothing
           else Just [KeyActionExecute command]
  | "Exec " `isPrefixOf` actionText =
      let command = trimQuotes (drop (length ("Exec " :: String)) actionText)
      in if containsSubstring "$[" command
           then Nothing
           else Just [KeyActionExecute command]
  | "Menu MenuFvwmRoot" `isPrefixOf` actionText || "Menu m_WindowOpsRootWin" `isPrefixOf` actionText =
      Just [KeyActionShowMenu "root-menu"]
  | "Menu " `isPrefixOf` actionText =
      Just [KeyActionShowMenu "root-menu"]
  | actionText == "f_RootMenu" =
      Just [KeyActionShowMenu "root-menu"]
  | "WindowList" `isPrefixOf` actionText || "f_WinLists" `isPrefixOf` actionText =
      Just [KeyActionShowMenu "client-list-combined-menu"]
  | actionText == "Refresh" = Just [KeyActionReconfigure]
  | actionText == "Nop" = Nothing
  | shouldSkipAction actionText = Nothing
  | otherwise = Nothing

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
