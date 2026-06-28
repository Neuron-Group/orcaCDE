module NsCDE.Domain.Runtime
  ( RuntimeCommand(..)
  , RuntimeRequest(..)
  , RuntimeResponse(..)
  , RuntimeStyleContext(..)
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
  | TopicBackdrops
  | TopicWindows
  | TopicSubpanels
  | TopicPager
  | TopicTaskd
  | TopicCapabilities
  | TopicStyle
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
  | CommandPublishState RuntimeTopic [KeyValue]
  | CommandStyleSet [KeyValue] Bool
  | CommandStyleApply
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

data RuntimeStyleContext = RuntimeStyleContext
  { runtimeStyleBackendName :: String
  , runtimeStyleHomeDir :: FilePath
  , runtimeStyleRootDir :: FilePath
  , runtimeStyleDataDir :: FilePath
  , runtimeStyleToolsDir :: FilePath
  , runtimeStyleFvwmUserDir :: FilePath
  , runtimeStyleXdgConfigHome :: FilePath
  , runtimeStyleXdgCacheHome :: FilePath
  , runtimeStyleXdgDataHome :: FilePath
  , runtimeStyleXdgRuntimeDir :: FilePath
  , runtimeStyleThemeName :: String
  , runtimeStyleWorkspaces :: [String]
  , runtimeStyleLabwcConfigDir :: FilePath
  , runtimeStyleLabwcKeybindXmlFile :: FilePath
  , runtimeStyleTitleFontName :: String
  , runtimeStyleTitleFontSize :: String
  , runtimeStyleTitleFontSlant :: String
  , runtimeStyleTitleFontWeight :: String
  , runtimeStyleWaylandDisplay :: String
  , runtimeStyleDisplayName :: String
  , runtimeStyleSystemPath :: FilePath
  , runtimeStyleStateDir :: FilePath
  } deriving (Eq, Show)

renderRuntimeTopic :: RuntimeTopic -> String
renderRuntimeTopic topic =
  case topic of
    TopicSession -> "session"
    TopicPanel -> "panel"
    TopicPanelLayout -> "panel-layout"
    TopicWorkspaces -> "workspaces"
    TopicBackdrops -> "backdrops"
    TopicWindows -> "windows"
    TopicSubpanels -> "subpanels"
    TopicPager -> "pager"
    TopicTaskd -> "taskd"
    TopicCapabilities -> "capabilities"
    TopicStyle -> "style"

parseRuntimeTopic :: String -> Maybe RuntimeTopic
parseRuntimeTopic rawTopic =
  case map toLower rawTopic of
    "session" -> Just TopicSession
    "panel" -> Just TopicPanel
    "panel-layout" -> Just TopicPanelLayout
    "workspaces" -> Just TopicWorkspaces
    "backdrops" -> Just TopicBackdrops
    "windows" -> Just TopicWindows
    "subpanels" -> Just TopicSubpanels
    "pager" -> Just TopicPager
    "taskd" -> Just TopicTaskd
    "capabilities" -> Just TopicCapabilities
    "style" -> Just TopicStyle
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
