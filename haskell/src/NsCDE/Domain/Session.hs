module NsCDE.Domain.Session
  ( RcConfig(..)
  , RcFont(..)
  , RcInput(..)
  , SessionPlan(..)
  ) where

import NsCDE.Foundation.EnvFile (KeyValue)

data RcFont = RcFont
  { rcFontPlace :: String
  , rcFontName :: String
  , rcFontSize :: String
  , rcFontSlant :: String
  , rcFontWeight :: String
  } deriving (Eq, Show)

data RcInput = RcInput
  { rcInputThemeName :: String
  , rcInputTitleFont :: RcFont
  , rcInputWorkspaces :: [String]
  , rcInputKeybindXml :: String
  } deriving (Eq, Show)

data RcConfig = RcConfig
  { rcThemeName :: String
  , rcFollowMouse :: Bool
  , rcFollowMouseRequiresMovement :: Bool
  , rcRaiseOnFocus :: Bool
  , rcRaiseOnFocusDelayMs :: Int
  , rcFonts :: [RcFont]
  , rcWorkspaces :: [String]
  , rcKeybindXml :: String
  } deriving (Eq, Show)

data SessionPlan = SessionPlan
  { sessionAutostartLines :: [String]
  , sessionEnvironmentEntries :: [KeyValue]
  , sessionShutdownLines :: [String]
  } deriving (Eq, Show)
