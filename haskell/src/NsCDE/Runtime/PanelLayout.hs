module NsCDE.Runtime.PanelLayout
  ( StaticPanelProfile(..)
  , emitPanelLayout
  , loadStaticPanelProfile
  ) where

import Data.Char (isSpace)
import Data.List (find)
import System.Environment (getEnvironment)

import NsCDE.Runtime.EnvFile (KeyValue, readEnvFile)

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

loadStaticPanelProfile :: FilePath -> IO StaticPanelProfile
loadStaticPanelProfile staticPath = do
  staticSettings <- readEnvFile staticPath
  envSettings <- getEnvironment
  pure $ buildStaticPanelProfile envSettings staticSettings

emitPanelLayout :: StaticPanelProfile -> [KeyValue]
emitPanelLayout profile =
  let leftModules = splitModules (panelLeftModules profile)
      rightModules = splitModules (panelRightModules profile)
      leftLauncherCount = length leftModules
      rightLauncherCount = length rightModules
      leftBankWidth =
        if leftLauncherCount > 0
          then panelLeftBankWidth profile
          else 0
      rightBankWidth =
        if null rightModules
          then 0
          else panelRightBankWidth profile
  in
    [ ("NSCDE_PANEL_LAYOUT_SOURCE", "haskell-runtime")
    , ("NSCDE_PANEL_LAYOUT_VERSION", "1")
    , ("NSCDE_PANEL_HEIGHT", show (panelHeight profile))
    , ("NSCDE_PANEL_EDGE", panelEdge profile)
    , ("NSCDE_PANEL_BORDER_WIDTH", show (panelBorderWidth profile))
    , ("NSCDE_PANEL_MARGIN", show (panelMargin profile))
    , ("NSCDE_PANEL_PADDING_X", show (panelPaddingX profile))
    , ("NSCDE_PANEL_PADDING_Y", show (panelPaddingY profile))
    , ("NSCDE_PANEL_WORKSPACE_MIN_BUTTON_WIDTH", show (panelWorkspaceMinButtonWidth profile))
    , ("NSCDE_PANEL_WORKSPACE_BUTTON_PADDING_X", show (panelWorkspaceButtonPaddingX profile))
    , ("NSCDE_PANEL_WORKSPACE_BUTTON_GAP", show (panelWorkspaceButtonGap profile))
    , ("NSCDE_PANEL_WORKSPACE_RECESS_HEIGHT", show (panelWorkspaceRecessHeight profile))
    , ("NSCDE_PANEL_BEVEL_WIDTH", show (panelBevelWidth profile))
    , ("NSCDE_PANEL_FONT", panelFont profile)
    , ("NSCDE_PANEL_RIGHT_AREA_WIDTH", show (panelRightAreaWidth profile))
    , ("NSCDE_PANEL_LEFT_MODULES", panelLeftModules profile)
    , ("NSCDE_PANEL_LAUNCHER_UNIT_WIDTH", show (panelLauncherUnitWidth profile))
    , ("NSCDE_PANEL_LAUNCHER_ICON_SIZE", show (panelLauncherIconSize profile))
    , ("NSCDE_PANEL_LAUNCHER_GAP", show (panelLauncherGap profile))
    , ("NSCDE_PANEL_RIGHT_MODULES", panelRightModules profile)
    , ("NSCDE_PANEL_APPLET_UNIT_WIDTH", show (panelAppletUnitWidth profile))
    , ("NSCDE_PANEL_PROFILE", panelProfile profile)
    , ("NSCDE_PANEL_SUBPANEL_ENTRY_HEIGHT", show (panelSubpanelEntryHeight profile))
    , ("NSCDE_PANEL_SUBPANEL_ICON_SIZE", show (panelSubpanelIconSize profile))
    , ("NSCDE_PANEL_SUBPANEL_TITLE_HEIGHT", show (panelSubpanelTitleHeight profile))
    , ("NSCDE_PANEL_SUBPANEL_PADDING", show (panelSubpanelPadding profile))
    , ("NSCDE_PANEL_LEFT_HANDLE_WIDTH", show (panelLeftHandleWidth profile))
    , ("NSCDE_PANEL_RIGHT_HANDLE_WIDTH", show (panelRightHandleWidth profile))
    , ("NSCDE_PANEL_TRIGGER_HEIGHT", show (panelTriggerHeight profile))
    , ("NSCDE_PANEL_BODY_HEIGHT", show (panelBodyHeight profile))
    , ("NSCDE_PANEL_BOTTOM_STRIP_HEIGHT", show (panelBottomStripHeight profile))
    , ("NSCDE_PANEL_SECTION_SEPARATOR_WIDTH", show (panelSectionSeparatorWidth profile))
    , ("NSCDE_PANEL_RIGHT_APPLET_GAP", show (panelRightAppletGap profile))
    , ("NSCDE_DESK_COUNT", show (panelDeskCount profile))
    , ("NSCDE_PANEL_WSM_WIDTH", show (panelWsmWidth profile))
    , ("NSCDE_PANEL_WSM_LOCK_WIDTH", show (panelWsmLockWidth profile))
    , ("NSCDE_PANEL_WSM_EXIT_WIDTH", show (panelWsmExitWidth profile))
    , ("NSCDE_PANEL_WSM_BUTTONS_WIDTH", show (panelWsmButtonsWidth profile))
    , ("NSCDE_PANEL_LEFT_LAUNCHER_COUNT", show leftLauncherCount)
    , ("NSCDE_PANEL_RIGHT_LAUNCHER_COUNT", show rightLauncherCount)
    , ("NSCDE_PANEL_LEFT_LAUNCHER_UNIT_WIDTH", show (panelLauncherUnitWidth profile))
    , ("NSCDE_PANEL_RIGHT_LAUNCHER_UNIT_WIDTH", show (panelLauncherUnitWidth profile))
    , ("NSCDE_PANEL_LEFT_BANK_WIDTH", show leftBankWidth)
    , ("NSCDE_PANEL_RIGHT_BANK_WIDTH", show rightBankWidth)
    , ("NSCDE_PANEL_CENTER_SECTION_X", show (panelCenterSectionX profile))
    , ("NSCDE_PANEL_CENTER_SECTION_WIDTH", show (panelCenterSectionWidth profile))
    , ("NSCDE_PANEL_WSM_INNER_PAD", show (panelWsmInnerPad profile))
    , ("NSCDE_PANEL_WSM_SIDE_WIDTH", show (panelWsmSideWidth profile))
    , ("NSCDE_PANEL_WSM_UTILITY_WIDTH", show (panelWsmUtilityWidth profile))
    , ("NSCDE_PANEL_WSM_SECTION_GAP", show (panelWsmSectionGap profile))
    , ("NSCDE_PANEL_WSM_GRID_VPAD", show (panelWsmGridVpad profile))
    , ("NSCDE_PANEL_WSM_LOCK_HEIGHT", show (panelWsmLockHeight profile))
    , ("NSCDE_PANEL_WSM_LOAD_INSET_TOP", show (panelWsmLoadInsetTop profile))
    , ("NSCDE_PANEL_WSM_LOAD_INSET_SIDE", show (panelWsmLoadInsetSide profile))
    , ("NSCDE_PANEL_WSM_LOAD_HEIGHT", show (panelWsmLoadHeight profile))
    , ("NSCDE_PANEL_WSM_EXIT_HEIGHT", show (panelWsmExitHeight profile))
    , ("NSCDE_PANEL_WSM_EXIT_INSET_BOTTOM", show (panelWsmExitInsetBottom profile))
    , ("NSCDE_PANEL_WSM_UTILITY_INSET_SIDE", show (panelWsmUtilityInsetSide profile))
    , ("NSCDE_PANEL_SCALE", show (panelScale profile))
    , ("NSCDE_PANEL_WS_FONT", panelWsFont profile)
    , ("NSCDE_PANEL_APPLET_DATE_FONT", panelAppletDateFont profile)
    , ("NSCDE_PANEL_APPLET_MAIL_FONT", panelAppletMailFont profile)
    , ("NSCDE_PANEL_APPLET_CLOCK_SIZE", show (panelAppletClockSize profile))
    , ("NSCDE_PANEL_APPLET_DATE_SIZE", show (panelAppletDateSize profile))
    , ("NSCDE_PANEL_APPLET_MAIL_SIZE", show (panelAppletMailSize profile))
    , ("NSCDE_PANEL_APPLET_LOAD_WIDTH", show (panelAppletLoadWidth profile))
    , ("NSCDE_PANEL_APPLET_LOAD_HEIGHT", show (panelAppletLoadHeight profile))
    ]

buildStaticPanelProfile :: [KeyValue] -> [KeyValue] -> StaticPanelProfile
buildStaticPanelProfile envSettings staticSettings =
  let scale = normalizeScale (lookupInt envSettings staticSettings "NSCDE_PANEL_SCALE" (lookupInt envSettings staticSettings "GDK_SCALE" 100))
      panelHeightBase = lookupInt envSettings staticSettings "NSCDE_PANEL_HEIGHT" 79
      panelBorderWidthBase = lookupInt envSettings staticSettings "NSCDE_PANEL_BORDER_WIDTH" 4
      panelMarginBase = lookupInt envSettings staticSettings "NSCDE_PANEL_MARGIN" 0
      panelPaddingXBase = lookupInt envSettings staticSettings "NSCDE_PANEL_PADDING_X" 6
      panelPaddingYBase = lookupInt envSettings staticSettings "NSCDE_PANEL_PADDING_Y" 4
      panelWorkspaceMinButtonWidthBase = lookupInt envSettings staticSettings "NSCDE_PANEL_WORKSPACE_MIN_BUTTON_WIDTH" 84
      panelWorkspaceButtonPaddingXBase = lookupInt envSettings staticSettings "NSCDE_PANEL_WORKSPACE_BUTTON_PADDING_X" 10
      panelWorkspaceButtonGapBase = lookupInt envSettings staticSettings "NSCDE_PANEL_WORKSPACE_BUTTON_GAP" 6
      panelWorkspaceRecessHeightBase = lookupInt envSettings staticSettings "NSCDE_PANEL_WORKSPACE_RECESS_HEIGHT" 32
      panelBevelWidthBase = lookupInt envSettings staticSettings "NSCDE_PANEL_BEVEL_WIDTH" 1
      panelRightAreaWidthBase = lookupInt envSettings staticSettings "NSCDE_PANEL_RIGHT_AREA_WIDTH" 200
      panelLauncherUnitWidthBase = lookupInt envSettings staticSettings "NSCDE_PANEL_LAUNCHER_UNIT_WIDTH" 63
      panelLauncherIconSizeBase = lookupInt envSettings staticSettings "NSCDE_PANEL_LAUNCHER_ICON_SIZE" 48
      panelLauncherGapBase = lookupInt envSettings staticSettings "NSCDE_PANEL_LAUNCHER_GAP" 0
      panelAppletUnitWidthBase = lookupInt envSettings staticSettings "NSCDE_PANEL_APPLET_UNIT_WIDTH" 50
      panelSubpanelEntryHeightBase = lookupInt envSettings staticSettings "NSCDE_PANEL_SUBPANEL_ENTRY_HEIGHT" 32
      panelSubpanelIconSizeBase = lookupInt envSettings staticSettings "NSCDE_PANEL_SUBPANEL_ICON_SIZE" 32
      panelSubpanelTitleHeightBase = lookupInt envSettings staticSettings "NSCDE_PANEL_SUBPANEL_TITLE_HEIGHT" 20
      panelSubpanelPaddingBase = lookupInt envSettings staticSettings "NSCDE_PANEL_SUBPANEL_PADDING" 4
      panelLeftHandleWidthBase = lookupInt envSettings staticSettings "NSCDE_PANEL_LEFT_HANDLE_WIDTH" 21
      panelRightHandleWidthBase = lookupInt envSettings staticSettings "NSCDE_PANEL_RIGHT_HANDLE_WIDTH" 21
      panelTriggerHeightBase = lookupInt envSettings staticSettings "NSCDE_PANEL_TRIGGER_HEIGHT" 16
      panelBodyHeightBase = lookupInt envSettings staticSettings "NSCDE_PANEL_BODY_HEIGHT" 62
      panelBottomStripHeightBase = lookupInt envSettings staticSettings "NSCDE_PANEL_BOTTOM_STRIP_HEIGHT" 1
      panelSectionSeparatorWidthBase = lookupInt envSettings staticSettings "NSCDE_PANEL_SECTION_SEPARATOR_WIDTH" 1
      panelRightAppletGapBase = lookupInt envSettings staticSettings "NSCDE_PANEL_RIGHT_APPLET_GAP" 4
      deskCount = lookupInt envSettings staticSettings "NSCDE_DESK_COUNT" 4
      wsmWidthBaseDefault = defaultWsmWidth deskCount
      wsmWidthBase = lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_WIDTH" wsmWidthBaseDefault
      wsmCols = defaultWsmCols deskCount
      wsmLockWidthBase = lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_LOCK_WIDTH" 2
      wsmExitWidthBase = lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_EXIT_WIDTH" 2
      panelWsmWidthScaled = scalePx scale wsmWidthBase
      wsmSideWidthDefault = divRound (panelWsmWidthScaled * wsmLockWidthBase) wsmCols
      wsmUtilityWidthDefault = divRound (panelWsmWidthScaled * wsmExitWidthBase) wsmCols
      wsmButtonsWidthDefault = panelWsmWidthScaled - wsmSideWidthDefault - wsmUtilityWidthDefault
      leftModules = lookupText envSettings staticSettings "NSCDE_PANEL_LEFT_MODULES" "clock,date,home,term,mail"
      rightModules = lookupText envSettings staticSettings "NSCDE_PANEL_RIGHT_MODULES" "print,style,apps,multimedia,help"
      leftLauncherCount = length (splitModules leftModules)
      appletClockSizeScaled = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_APPLET_CLOCK_SIZE" 56)
      appletDateSizeScaled = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_APPLET_DATE_SIZE" 56)
      appletMailSizeScaled = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_APPLET_MAIL_SIZE" 56)
      appletLoadWidthScaled = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_APPLET_LOAD_WIDTH" 36)
      appletLoadHeightScaled = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_APPLET_LOAD_HEIGHT" 34)
      launcherUnitWidthScaled = scalePx scale panelLauncherUnitWidthBase
      rightAppletGapScaled = scalePx scale panelRightAppletGapBase
      rightBankWidthDefault = computeRightBankWidth (splitModules rightModules) launcherUnitWidthScaled rightAppletGapScaled appletClockSizeScaled appletDateSizeScaled appletMailSizeScaled appletLoadWidthScaled
      leftBankWidthDefault =
        if leftLauncherCount > 0
          then leftLauncherCount * launcherUnitWidthScaled
          else 0
      centerSectionXDefault = scalePx scale panelLeftHandleWidthBase + leftBankWidthDefault
      centerSectionWidthDefault = panelWsmWidthScaled
  in StaticPanelProfile
      { panelHeight = scalePx scale panelHeightBase
      , panelEdge = lookupText envSettings staticSettings "NSCDE_PANEL_EDGE" "bottom"
      , panelBorderWidth = scalePx scale panelBorderWidthBase
      , panelMargin = scalePx scale panelMarginBase
      , panelPaddingX = scalePx scale panelPaddingXBase
      , panelPaddingY = scalePx scale panelPaddingYBase
      , panelWorkspaceMinButtonWidth = scalePx scale panelWorkspaceMinButtonWidthBase
      , panelWorkspaceButtonPaddingX = scalePx scale panelWorkspaceButtonPaddingXBase
      , panelWorkspaceButtonGap = scalePx scale panelWorkspaceButtonGapBase
      , panelWorkspaceRecessHeight = scalePx scale panelWorkspaceRecessHeightBase
      , panelBevelWidth = scalePx scale panelBevelWidthBase
      , panelFont = lookupText envSettings staticSettings "NSCDE_PANEL_FONT" "DejaVu Serif 9"
      , panelRightAreaWidth = scalePx scale panelRightAreaWidthBase
      , panelLeftModules = leftModules
      , panelLauncherUnitWidth = launcherUnitWidthScaled
      , panelLauncherIconSize = scalePx scale panelLauncherIconSizeBase
      , panelLauncherGap = scalePx scale panelLauncherGapBase
      , panelRightModules = rightModules
      , panelAppletUnitWidth = scalePx scale panelAppletUnitWidthBase
      , panelProfile = lookupText envSettings staticSettings "NSCDE_PANEL_PROFILE" "reference"
      , panelSubpanelEntryHeight = scalePx scale panelSubpanelEntryHeightBase
      , panelSubpanelIconSize = scalePx scale panelSubpanelIconSizeBase
      , panelSubpanelTitleHeight = scalePx scale panelSubpanelTitleHeightBase
      , panelSubpanelPadding = scalePx scale panelSubpanelPaddingBase
      , panelLeftHandleWidth = scalePx scale panelLeftHandleWidthBase
      , panelRightHandleWidth = scalePx scale panelRightHandleWidthBase
      , panelTriggerHeight = scalePx scale panelTriggerHeightBase
      , panelBodyHeight = scalePx scale panelBodyHeightBase
      , panelBottomStripHeight = scalePx scale panelBottomStripHeightBase
      , panelSectionSeparatorWidth = scalePx scale panelSectionSeparatorWidthBase
      , panelRightAppletGap = rightAppletGapScaled
      , panelDeskCount = deskCount
      , panelWsmWidth = panelWsmWidthScaled
      , panelWsmLockWidth = wsmLockWidthBase
      , panelWsmExitWidth = wsmExitWidthBase
      , panelWsmButtonsWidth = lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_BUTTONS_WIDTH" wsmButtonsWidthDefault
      , panelLeftBankWidth = lookupInt envSettings staticSettings "NSCDE_PANEL_LEFT_BANK_WIDTH" leftBankWidthDefault
      , panelRightBankWidth = lookupInt envSettings staticSettings "NSCDE_PANEL_RIGHT_BANK_WIDTH" rightBankWidthDefault
      , panelCenterSectionX = lookupInt envSettings staticSettings "NSCDE_PANEL_CENTER_SECTION_X" centerSectionXDefault
      , panelCenterSectionWidth = lookupInt envSettings staticSettings "NSCDE_PANEL_CENTER_SECTION_WIDTH" centerSectionWidthDefault
      , panelWsmInnerPad = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_INNER_PAD" 5)
      , panelWsmSideWidth = lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_SIDE_WIDTH" wsmSideWidthDefault
      , panelWsmUtilityWidth = lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_UTILITY_WIDTH" wsmUtilityWidthDefault
      , panelWsmSectionGap = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_SECTION_GAP" 6)
      , panelWsmGridVpad = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_GRID_VPAD" 3)
      , panelWsmLockHeight = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_LOCK_HEIGHT" 34)
      , panelWsmLoadInsetTop = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_LOAD_INSET_TOP" 8)
      , panelWsmLoadInsetSide = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_LOAD_INSET_SIDE" 5)
      , panelWsmLoadHeight = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_LOAD_HEIGHT" 14)
      , panelWsmExitHeight = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_EXIT_HEIGHT" 30)
      , panelWsmExitInsetBottom = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_EXIT_INSET_BOTTOM" 4)
      , panelWsmUtilityInsetSide = scalePx scale (lookupInt envSettings staticSettings "NSCDE_PANEL_WSM_UTILITY_INSET_SIDE" 5)
      , panelScale = scale
      , panelWsFont = lookupText envSettings staticSettings "NSCDE_PANEL_WS_FONT" "DejaVu Serif 10"
      , panelAppletDateFont = lookupText envSettings staticSettings "NSCDE_PANEL_APPLET_DATE_FONT" "DejaVu Sans Bold 12"
      , panelAppletMailFont = lookupText envSettings staticSettings "NSCDE_PANEL_APPLET_MAIL_FONT" "DejaVu Sans 10"
      , panelAppletClockSize = appletClockSizeScaled
      , panelAppletDateSize = appletDateSizeScaled
      , panelAppletMailSize = appletMailSizeScaled
      , panelAppletLoadWidth = appletLoadWidthScaled
      , panelAppletLoadHeight = appletLoadHeightScaled
      }

lookupText :: [KeyValue] -> [KeyValue] -> String -> String -> String
lookupText envSettings staticSettings key fallback =
  case findValue key envSettings of
    Just value | not (null value) -> value
    _ ->
      case findValue key staticSettings of
        Just value | not (null value) -> value
        _ -> fallback

lookupInt :: [KeyValue] -> [KeyValue] -> String -> Int -> Int
lookupInt envSettings staticSettings key fallback =
  case findRead key envSettings of
    Just value -> value
    Nothing ->
      case findRead key staticSettings of
        Just value -> value
        Nothing -> fallback

findRead :: String -> [KeyValue] -> Maybe Int
findRead key settings =
  case findValue key settings of
    Nothing -> Nothing
    Just value ->
      case reads value of
        [(parsed, "")] -> Just parsed
        _ -> Nothing

findValue :: String -> [KeyValue] -> Maybe String
findValue key settings = snd <$> find (\(candidate, _) -> candidate == key) settings

splitModules :: String -> [String]
splitModules raw =
  let trimmed = trim raw
  in if null trimmed
       then []
       else filter (not . null) (map trim (splitOnComma trimmed))

splitOnComma :: String -> [String]
splitOnComma [] = [""]
splitOnComma (',':rest) = "" : splitOnComma rest
splitOnComma (char:rest) =
  case splitOnComma rest of
    [] -> [[char]]
    token:tokens -> (char : token) : tokens

trim :: String -> String
trim = dropWhileEnd isSpace . dropWhile isSpace

dropWhileEnd :: (a -> Bool) -> [a] -> [a]
dropWhileEnd predicate = reverse . dropWhile predicate . reverse

normalizeScale :: Int -> Int
normalizeScale rawScale
  | rawScale == 1 = 100
  | rawScale == 2 = 200
  | rawScale `elem` [100, 125, 150, 175, 200, 225, 250, 300, 400] = rawScale
  | rawScale >= 10 && rawScale <= 999 = rawScale
  | otherwise = 100

scalePx :: Int -> Int -> Int
scalePx scale value = (value * scale + 50) `div` 100

defaultWsmWidth :: Int -> Int
defaultWsmWidth deskCount =
  case deskCount of
    0 -> 79
    2 -> 211
    4 -> 343
    6 -> 475
    8 -> 607
    _ -> 211 + (deskCount - 2) * 66

defaultWsmCols :: Int -> Int
defaultWsmCols deskCount =
  case deskCount of
    0 -> 4
    2 -> 8
    4 -> 16
    6 -> 24
    8 -> 32
    _ -> deskCount * 4

divRound :: Int -> Int -> Int
divRound numerator denominator =
  (numerator + denominator `div` 2) `div` denominator

computeRightBankWidth :: [String] -> Int -> Int -> Int -> Int -> Int -> Int -> Int
computeRightBankWidth modules launcherUnitWidth appletGap clockSize dateSize mailSize loadWidth =
  case modules of
    [] -> 0
    (firstModule:restModules) ->
      foldl accumulate (moduleWidth firstModule) restModules
  where
    accumulate total moduleName = total + appletGap + moduleWidth moduleName
    moduleWidth moduleName =
      case moduleName of
        "clock" -> clockSize
        "date" -> dateSize
        "mail" -> mailSize
        "load" -> loadWidth
        _ -> launcherUnitWidth
