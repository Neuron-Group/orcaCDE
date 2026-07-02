module NsCDE.Domain.PanelLayout
  ( StaticPanelProfile(..)
  , PanelLayoutDelta(..)
  , PanelLayoutState(..)
  , panelLayoutStateEntries
  ) where

import NsCDE.Foundation.EnvFile (KeyValue)

data StaticPanelProfile = StaticPanelProfile
  { panelHeight :: Int
  , panelEdge :: String
  , panelBorderWidth :: Int
  , panelMargin :: Int
  , panelPaddingX :: Int
  , panelPaddingY :: Int
  , panelWorkspaceMinButtonWidth :: Int
  , panelWorkspaceButtonPaddingX :: Int
  , panelWorkspaceButtonGap :: Int
  , panelWorkspaceRecessHeight :: Int
  , panelBevelWidth :: Int
  , panelFont :: String
  , panelRightAreaWidth :: Int
  , panelLeftModules :: String
  , panelLauncherUnitWidth :: Int
  , panelLauncherIconSize :: Int
  , panelLauncherGap :: Int
  , panelRightModules :: String
  , panelAppletUnitWidth :: Int
  , panelProfile :: String
  , panelSubpanelEntryHeight :: Int
  , panelSubpanelIconSize :: Int
  , panelSubpanelTitleHeight :: Int
  , panelSubpanelPadding :: Int
  , panelLeftHandleWidth :: Int
  , panelRightHandleWidth :: Int
  , panelTriggerHeight :: Int
  , panelBodyHeight :: Int
  , panelBottomStripHeight :: Int
  , panelSectionSeparatorWidth :: Int
  , panelRightAppletGap :: Int
  , panelDeskCount :: Int
  , panelWsmWidth :: Int
  , panelWsmLockWidth :: Int
  , panelWsmExitWidth :: Int
  , panelWsmButtonsWidth :: Int
  , panelLeftBankWidth :: Int
  , panelRightBankWidth :: Int
  , panelCenterSectionX :: Int
  , panelCenterSectionWidth :: Int
  , panelWsmInnerPad :: Int
  , panelWsmSideWidth :: Int
  , panelWsmUtilityWidth :: Int
  , panelWsmSectionGap :: Int
  , panelWsmGridVpad :: Int
  , panelWsmLockHeight :: Int
  , panelWsmLoadInsetTop :: Int
  , panelWsmLoadInsetSide :: Int
  , panelWsmLoadHeight :: Int
  , panelWsmExitHeight :: Int
  , panelWsmExitInsetBottom :: Int
  , panelWsmUtilityInsetSide :: Int
  , panelScale :: Int
  , panelWsFont :: String
  , panelAppletDateFont :: String
  , panelAppletMailFont :: String
  , panelAppletClockSize :: Int
  , panelAppletDateSize :: Int
  , panelAppletMailSize :: Int
  , panelAppletLoadWidth :: Int
  , panelAppletLoadHeight :: Int
  } deriving (Eq, Show)

data PanelLayoutState = PanelLayoutState
  { panelLayoutProfile :: StaticPanelProfile
  , panelLayoutEntries :: [KeyValue]
  } deriving (Eq, Show)

data PanelLayoutDelta = PanelLayoutDelta
  { panelLayoutDeltaEntries :: [KeyValue]
  , panelLayoutDeltaUnsetKeys :: [String]
  , panelLayoutDeltaReset :: Bool
  } deriving (Eq, Show)

panelLayoutStateEntries :: PanelLayoutState -> [KeyValue]
panelLayoutStateEntries = panelLayoutEntries
