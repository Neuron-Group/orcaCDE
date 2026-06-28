module NsCDE.Domain.Keymap
  ( DesktopDirection(..)
  , KeyActionIntent(..)
  , KeyBindingIntent(..)
  , KeyContext(..)
  , KeyModifier(..)
  , KeymapEnvironment(..)
  ) where

data DesktopDirection
  = DesktopLeft
  | DesktopRight
  | DesktopUp
  | DesktopDown
  deriving (Eq, Show)

data KeyContext
  = KeyContextRoot
  | KeyContextAll
  | KeyContextWindow
  | KeyContextFrame
  | KeyContextSystem
  | KeyContextTitle
  | KeyContextIcon
  | KeyContextOther String
  deriving (Eq, Show)

data KeyModifier
  = KeyModifierControl
  | KeyModifierShift
  | KeyModifierAlt
  | KeyModifierSuper
  deriving (Eq, Show)

data KeyActionIntent
  = KeyActionGoToDesktop DesktopDirection Bool
  | KeyActionNextWindow
  | KeyActionPreviousWindow
  | KeyActionClose
  | KeyActionIconify
  | KeyActionToggleMaximize
  | KeyActionToggleShade
  | KeyActionRaise
  | KeyActionLower
  | KeyActionToggleAlwaysOnTop
  | KeyActionMove
  | KeyActionResize
  | KeyActionShowMenu String
  | KeyActionReconfigure
  | KeyActionExecute String
  deriving (Eq, Show)

data KeyBindingIntent = KeyBindingIntent
  { keyBindingIntentKey :: String
  , keyBindingIntentModifiers :: [KeyModifier]
  , keyBindingIntentActions :: [KeyActionIntent]
  } deriving (Eq, Show)

data KeymapEnvironment = KeymapEnvironment
  { keymapTerminal :: String
  , keymapToolsDir :: FilePath
  , keymapDataDir :: FilePath
  } deriving (Eq, Show)
