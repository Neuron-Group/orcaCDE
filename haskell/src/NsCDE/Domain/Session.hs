module NsCDE.Domain.Session
  ( RcConfig(..)
  , RcFont(..)
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

data RcConfig = RcConfig
  { rcThemeName :: String
  , rcFollowMouse :: String
  , rcRaiseOnFocus :: String
  , rcFonts :: [RcFont]
  , rcWorkspaces :: [String]
  , rcKeybindXml :: String
  } deriving (Eq, Show)

data SessionPlan = SessionPlan
  { sessionAutostartLines :: [String]
  , sessionEnvironmentEntries :: [KeyValue]
  , sessionShutdownLines :: [String]
  } deriving (Eq, Show)
