module NsCDE.Domain.Runtime
  ( RuntimeCommand(..)
  , RuntimeEvent(..)
  , RuntimeEventDelta(..)
  , RuntimeEventKind(..)
  , RuntimeEventSource(..)
  , RuntimeEventPayload
  , RuntimePowerAction(..)
  , RuntimeRefreshTarget(..)
  , RuntimeProducerRole(..)
  , RuntimeRequest(..)
  , RuntimeResponse(..)
  , RuntimeStreamFrame(..)
  , RuntimeStreamRequest(..)
  , StreamBootstrap(..)
  , RuntimeStyleContext(..)
  , RuntimeTopic(..)
  , RuntimeWindowCommand(..)
  , parseRuntimeProducerRole
  , parseRuntimeRefreshTarget
  , parseRuntimeEventKind
  , renderRuntimeProducerRole
  , renderRuntimeRefreshTarget
  , renderRuntimeEventKind
  , renderRuntimeEventSource
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

data RuntimeProducerRole
  = ProducerPager
  | ProducerToplevel
  deriving (Eq, Show)

data RuntimePowerAction
  = PowerShutdown
  | PowerReboot
  | PowerSuspend
  | PowerHybridSuspend
  | PowerHibernate
  deriving (Eq, Show)

data RuntimeRefreshTarget
  = RefreshKeybinds
  | RefreshMenu
  | RefreshRc
  | RefreshTheme
  | RefreshSession
  deriving (Eq, Show)

data RuntimeCommand
  = CommandWorkspaceSwitch String
  | CommandWorkspaceRename String String
  | CommandWindow RuntimeWindowCommand Int
  | CommandPublishState RuntimeTopic [KeyValue]
  | CommandColorSelect String Int
  | CommandBackdropSelect Int String String
  | CommandStyleSet [KeyValue] Bool
  | CommandStyleApply
  | CommandRefresh RuntimeRefreshTarget
  | CommandPower RuntimePowerAction
  | CommandFailsafe
  | CommandLogout
  | CommandReload
  deriving (Eq, Show)

data RuntimeEventKind
  = EventWorkspaceCurrentChanged
  | EventWorkspaceNamesChanged
  | EventStyleChanged
  | EventPanelLayoutChanged
  | EventBackdropPlanChanged
  | EventBackdropMaterialized
  | EventWindowsChanged
  | EventTaskListChanged
  | EventSubpanelsChanged
  | EventCapabilitiesChanged
  | EventArtifactRefreshed
  | EventBackendActionRequested
  | EventBackendActionFailed
  deriving (Eq, Show)

data RuntimeEventSource
  = SourceStartup
  | SourceCommand RuntimeCommand
  | SourceProducer RuntimeProducerRole
  | SourceCompatFifo
  | SourceEffect
  deriving (Eq, Show)

data RuntimeEvent = RuntimeEvent
  { runtimeEventSeq :: Integer
  , runtimeEventTopic :: RuntimeTopic
  , runtimeEventKind :: RuntimeEventKind
  , runtimeEventSource :: RuntimeEventSource
  , runtimeEventReset :: Bool
  , runtimeEventUnsetKeys :: [String]
  } deriving (Eq, Show)

data RuntimeEventDelta = RuntimeEventDelta
  { runtimeEventDeltaTopic :: RuntimeTopic
  , runtimeEventDeltaKind :: RuntimeEventKind
  , runtimeEventDeltaEntries :: [KeyValue]
  , runtimeEventDeltaUnsetKeys :: [String]
  , runtimeEventDeltaReset :: Bool
  } deriving (Eq, Show)

type RuntimeEventPayload = RuntimeEventDelta

data StreamBootstrap
  = BootstrapWithSnapshots
  | BootstrapWithoutSnapshots
  deriving (Eq, Show)

data RuntimeStreamRequest
  = StreamSubscribeSnapshots [RuntimeTopic]
  | StreamSubscribeEvents [RuntimeTopic] StreamBootstrap
  deriving (Eq, Show)

data RuntimeStreamFrame
  = StreamFrameSnapshot RuntimeTopic [KeyValue]
  | StreamFrameEvent RuntimeEvent [KeyValue]
  | StreamFrameAck String
  | StreamFrameError String
  deriving (Eq, Show)

data RuntimeRequest
  = RequestHello (Maybe String)
  | RequestPublishStream RuntimeProducerRole [RuntimeTopic]
  | RequestProducerState RuntimeTopic [KeyValue]
  | RequestSubscribe [RuntimeTopic]
  | RequestSubscribeEvents [RuntimeTopic] Bool
  | RequestQuery RuntimeTopic
  | RequestCommand RuntimeCommand
  deriving (Eq, Show)

data RuntimeResponse
  = ResponseState RuntimeTopic [KeyValue]
  | ResponseSnapshot RuntimeTopic [KeyValue]
  | ResponseEvent RuntimeEvent [KeyValue]
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

renderRuntimeProducerRole :: RuntimeProducerRole -> String
renderRuntimeProducerRole producerRole =
  case producerRole of
    ProducerPager -> "pagerd"
    ProducerToplevel -> "toplevel"

parseRuntimeProducerRole :: String -> Maybe RuntimeProducerRole
parseRuntimeProducerRole rawRole =
  case map toLower rawRole of
    "pagerd" -> Just ProducerPager
    "toplevel" -> Just ProducerToplevel
    _ -> Nothing

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

renderRuntimeRefreshTarget :: RuntimeRefreshTarget -> String
renderRuntimeRefreshTarget refreshTarget =
  case refreshTarget of
    RefreshKeybinds -> "keybinds"
    RefreshMenu -> "menu"
    RefreshRc -> "rc"
    RefreshTheme -> "theme"
    RefreshSession -> "session"

parseRuntimeRefreshTarget :: String -> Maybe RuntimeRefreshTarget
parseRuntimeRefreshTarget rawTarget =
  case map toLower rawTarget of
    "keybinds" -> Just RefreshKeybinds
    "menu" -> Just RefreshMenu
    "rc" -> Just RefreshRc
    "theme" -> Just RefreshTheme
    "session" -> Just RefreshSession
    _ -> Nothing

renderRuntimeEventKind :: RuntimeEventKind -> String
renderRuntimeEventKind eventKind =
  case eventKind of
    EventWorkspaceCurrentChanged -> "workspace-current-changed"
    EventWorkspaceNamesChanged -> "workspace-names-changed"
    EventStyleChanged -> "style-changed"
    EventPanelLayoutChanged -> "panel-layout-changed"
    EventBackdropPlanChanged -> "backdrop-plan-changed"
    EventBackdropMaterialized -> "backdrop-materialized"
    EventWindowsChanged -> "windows-changed"
    EventTaskListChanged -> "task-list-changed"
    EventSubpanelsChanged -> "subpanels-changed"
    EventCapabilitiesChanged -> "capabilities-changed"
    EventArtifactRefreshed -> "artifact-refreshed"
    EventBackendActionRequested -> "backend-action-requested"
    EventBackendActionFailed -> "backend-action-failed"

parseRuntimeEventKind :: String -> Maybe RuntimeEventKind
parseRuntimeEventKind rawKind =
  case map toLower rawKind of
    "workspace-current-changed" -> Just EventWorkspaceCurrentChanged
    "workspace-names-changed" -> Just EventWorkspaceNamesChanged
    "style-changed" -> Just EventStyleChanged
    "panel-layout-changed" -> Just EventPanelLayoutChanged
    "backdrop-plan-changed" -> Just EventBackdropPlanChanged
    "backdrop-materialized" -> Just EventBackdropMaterialized
    "windows-changed" -> Just EventWindowsChanged
    "task-list-changed" -> Just EventTaskListChanged
    "subpanels-changed" -> Just EventSubpanelsChanged
    "capabilities-changed" -> Just EventCapabilitiesChanged
    "artifact-refreshed" -> Just EventArtifactRefreshed
    "backend-action-requested" -> Just EventBackendActionRequested
    "backend-action-failed" -> Just EventBackendActionFailed
    _ -> Nothing

renderRuntimeEventSource :: RuntimeEventSource -> String
renderRuntimeEventSource eventSource =
  case eventSource of
    SourceStartup -> "startup"
    SourceCommand command ->
      "command:" ++ renderCommandName command
    SourceProducer producerRole ->
      "producer:" ++ renderRuntimeProducerRole producerRole
    SourceCompatFifo -> "compat-fifo"
    SourceEffect -> "effect"

renderCommandName :: RuntimeCommand -> String
renderCommandName command =
  case command of
    CommandWorkspaceSwitch _ -> "workspace-switch"
    CommandWorkspaceRename _ _ -> "workspace-rename"
    CommandWindow windowCommand _ ->
      "window-" ++ renderRuntimeWindowCommand windowCommand
    CommandPublishState topic _ ->
      "publish-state:" ++ renderRuntimeTopic topic
    CommandColorSelect _ _ -> "color-select"
    CommandBackdropSelect _ _ _ -> "backdrop-select"
    CommandStyleSet _ _ -> "style-set"
    CommandStyleApply -> "style-apply"
    CommandRefresh refreshTarget ->
      "refresh:" ++ renderRuntimeRefreshTarget refreshTarget
    CommandPower powerAction ->
      case powerAction of
        PowerShutdown -> "power-poweroff"
        PowerReboot -> "power-reboot"
        PowerSuspend -> "power-suspend"
        PowerHybridSuspend -> "power-hybrid-suspend"
        PowerHibernate -> "power-hibernate"
    CommandFailsafe -> "failsafe"
    CommandLogout -> "logout"
    CommandReload -> "reload"
