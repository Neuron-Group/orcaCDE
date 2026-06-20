module NsCDE.Domain.Keybinds
  ( KeybindAction(..)
  , KeybindBinding(..)
  ) where

data KeybindAction = KeybindAction
  { keybindActionName :: String
  , keybindActionAttrs :: [(String, String)]
  , keybindActionCommand :: Maybe String
  } deriving (Eq, Show)

data KeybindBinding = KeybindBinding
  { keybindKey :: String
  , keybindActions :: [KeybindAction]
  } deriving (Eq, Show)
