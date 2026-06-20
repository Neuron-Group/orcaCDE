module NsCDE.Domain.Runtime
  ( RuntimeCommand(..)
  , RuntimeRequest(..)
  , RuntimeResponse(..)
  , RuntimeTopic(..)
  , RuntimeWindowCommand(..)
  , parseRuntimeTopic
  , parseRuntimeWindowCommand
  , renderRuntimeTopic
  , renderRuntimeWindowCommand
  ) where

import Data.Char (toLower)

import NsCDE.Foundation.EnvFile (KeyValue)

data RuntimeTopic
  = TopicSession
  | TopicPanel
  | TopicPanelLayout
  | TopicWorkspaces
  | TopicWindows
  | TopicSubpanels
  | TopicPager
  | TopicTaskd
  | TopicCapabilities
  deriving (Eq, Show)

data RuntimeWindowCommand
  = WindowActivate
  | WindowClose
  | WindowMinimize
  | WindowRestore
  | WindowMaximize
  deriving (Eq, Show)

data RuntimeCommand
  = CommandWorkspaceSwitch String
  | CommandWorkspaceRename String String
  | CommandWindow RuntimeWindowCommand Int
  | CommandReload
  deriving (Eq, Show)

data RuntimeRequest
  = RequestHello (Maybe String)
  | RequestSubscribe [RuntimeTopic]
  | RequestQuery RuntimeTopic
  | RequestCommand RuntimeCommand
  deriving (Eq, Show)

data RuntimeResponse
  = ResponseState RuntimeTopic [KeyValue]
  | ResponseAck String
  | ResponseError String
  deriving (Eq, Show)

renderRuntimeTopic :: RuntimeTopic -> String
renderRuntimeTopic topic =
  case topic of
    TopicSession -> "session"
    TopicPanel -> "panel"
    TopicPanelLayout -> "panel-layout"
    TopicWorkspaces -> "workspaces"
    TopicWindows -> "windows"
    TopicSubpanels -> "subpanels"
    TopicPager -> "pager"
    TopicTaskd -> "taskd"
    TopicCapabilities -> "capabilities"

parseRuntimeTopic :: String -> Maybe RuntimeTopic
parseRuntimeTopic rawTopic =
  case map toLower rawTopic of
    "session" -> Just TopicSession
    "panel" -> Just TopicPanel
    "panel-layout" -> Just TopicPanelLayout
    "workspaces" -> Just TopicWorkspaces
    "windows" -> Just TopicWindows
    "subpanels" -> Just TopicSubpanels
    "pager" -> Just TopicPager
    "taskd" -> Just TopicTaskd
    "capabilities" -> Just TopicCapabilities
    _ -> Nothing

renderRuntimeWindowCommand :: RuntimeWindowCommand -> String
renderRuntimeWindowCommand windowCommand =
  case windowCommand of
    WindowActivate -> "activate"
    WindowClose -> "close"
    WindowMinimize -> "minimize"
    WindowRestore -> "restore"
    WindowMaximize -> "maximize"

parseRuntimeWindowCommand :: String -> Maybe RuntimeWindowCommand
parseRuntimeWindowCommand rawCommand =
  case map toLower rawCommand of
    "activate" -> Just WindowActivate
    "close" -> Just WindowClose
    "minimize" -> Just WindowMinimize
    "restore" -> Just WindowRestore
    "maximize" -> Just WindowMaximize
    _ -> Nothing
