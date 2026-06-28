module NsCDE.Policy.Keybinds
  ( buildKeybinds
  , resolveTerminal
  ) where

import System.Directory (findExecutable)

import NsCDE.Domain.Keybinds
import NsCDE.Domain.Keymap (KeymapEnvironment(..))
import NsCDE.Foundation.EnvFile (KeyValue)
import NsCDE.Foundation.Settings (lookupText)
import NsCDE.Parse.Keybindings (loadParsedKeybindings)
import NsCDE.Policy.Keymap
  ( buildBindingIntent
  , buildDefaultBindingIntents
  , buildMediaBindingIntents
  , renderBindingIntent
  )

buildKeybinds :: [KeyValue] -> IO [KeybindBinding]
buildKeybinds env = do
  terminal <- resolveTerminal env
  parsed <- loadParsedKeybindings env
  let keymapEnv =
        KeymapEnvironment
          { keymapTerminal = terminal
          , keymapToolsDir = lookupText env "NSCDE_TOOLSDIR" ""
          , keymapDataDir = lookupText env "NSCDE_DATADIR" ""
          }
      dynamicBindings =
        map renderBindingIntent (mapMaybe (buildBindingIntent keymapEnv) parsed)
      mediaBindings =
        map renderBindingIntent (buildMediaBindingIntents keymapEnv)
      defaultBindings =
        map renderBindingIntent (buildDefaultBindingIntents keymapEnv)
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

dedupeBindings :: [KeybindBinding] -> [KeybindBinding]
dedupeBindings bindings =
  reverse (foldl keepLatest [] (reverse bindings))
  where
    keepLatest acc bindingValue =
      if any ((== keybindKey bindingValue) . keybindKey) acc
        then acc
        else bindingValue : acc

mapMaybe :: (a -> Maybe b) -> [a] -> [b]
mapMaybe _ [] = []
mapMaybe function (value:rest) =
  case function value of
    Nothing -> mapMaybe function rest
    Just result -> result : mapMaybe function rest
