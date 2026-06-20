module NsCDE.Backend.Labwc.KeybindXml
  ( renderKeyboardXml
  ) where

import NsCDE.Domain.Keybinds
import NsCDE.Foundation.Common (escapeXml)

renderKeyboardXml :: [KeybindBinding] -> String
renderKeyboardXml bindings =
  unlines $
    [ "  <keyboard>"
    , "    <default />"
    ]
    ++ concatMap renderBinding bindings
    ++ ["  </keyboard>"]

renderBinding :: KeybindBinding -> [String]
renderBinding binding =
  [ "    <keybind key=\"" ++ escapeXml (keybindKey binding) ++ "\">"
  ]
  ++ concatMap renderAction (keybindActions binding)
  ++ ["    </keybind>"]

renderAction :: KeybindAction -> [String]
renderAction action =
  case keybindActionCommand action of
    Just command ->
      [ "      <action name=\"Execute\"><command>" ++ escapeXml command ++ "</command></action>"
      ]
    Nothing ->
      [ "      <action name=\"" ++ escapeXml (keybindActionName action) ++ "\"" ++ renderAttrs (keybindActionAttrs action) ++ " />"
      ]

renderAttrs :: [(String, String)] -> String
renderAttrs [] = ""
renderAttrs attrs =
  concatMap renderAttr attrs
  where
    renderAttr (name, value) =
      " " ++ name ++ "=\"" ++ escapeXml value ++ "\""
