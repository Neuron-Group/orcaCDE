module Main (main) where

import Test.HUnit

import NsCDE.Backend.Labwc.KeybindXml (renderKeyboardXml)
import NsCDE.Backend.Labwc.MenuXml (renderMenuXml)
import NsCDE.Backend.Labwc.RcXml (renderRcXml)
import NsCDE.Domain.Keybinds
import NsCDE.Domain.Menu
import NsCDE.Domain.PanelLayout
import NsCDE.Foundation.EnvFile (renderEnvFile)
import NsCDE.Parse.AppMenus (parseAppMenuContents)
import NsCDE.Parse.Keybindings (parseKeybindingsContents)
import NsCDE.Policy.Menu (buildMenuModel)
import NsCDE.Policy.PanelLayout (emitPanelLayout)
import NsCDE.Policy.SessionPlan (buildRcConfig)

main :: IO ()
main = do
  resultCounts <- runTestTT tests
  if failures resultCounts > 0 || errors resultCounts > 0
    then error "runtime-tests failed"
    else pure ()

tests :: Test
tests =
  TestList
    [ TestLabel "app-menu parsing" testAppMenuParsing
    , TestLabel "keybinding parsing" testKeybindingParsing
    , TestLabel "menu rendering" testMenuRendering
    , TestLabel "keybind rendering" testKeybindRendering
    , TestLabel "rc rendering" testRcRendering
    , TestLabel "panel env rendering" testPanelEnvRendering
    ]

testAppMenuParsing :: Test
testAppMenuParsing =
  TestCase $ do
    let entries = parseAppMenuContents "Terminal,Resource,$[gt.Terminal]\tF12,Exec exec \"xterm\"\n"
    assertEqual "one menu entry" 1 (length entries)
    case entries of
      firstEntry:_ ->
        assertEqual "clean label" "Terminal" (appMenuDisplayLabel firstEntry)
      [] ->
        assertFailure "expected a parsed menu entry"

testKeybindingParsing :: Test
testKeybindingParsing =
  TestCase $ do
    let bindings = parseKeybindingsContents "Silent Key F12 A 4 Exec exec xterm\nTest foo\n"
    assertEqual "one parsed keybinding" 1 (length bindings)

testMenuRendering :: Test
testMenuRendering =
  TestCase $ do
    let menuXml =
          renderMenuXml
            (buildMenuModel
              [ ("NSCDE_TOOLSDIR", "/tools")
              , ("NSCDE_LABWC_WORKSPACES", "Alpha,Beta")
              ]
              "xterm"
              [ AppMenuEntry "X" "Terminal" "Terminal" "Exec exec xterm" "X,Resource,Terminal,Exec exec xterm"
              ])
    assertBool "style manager item present" ("Style Manager" `containsSubstring` menuXml)
    assertBool "workspace item present" ("Workspace Alpha" `containsSubstring` menuXml)

testKeybindRendering :: Test
testKeybindRendering =
  TestCase $ do
    let xml =
          renderKeyboardXml
            [ KeybindBinding "W-Return" [KeybindAction "Execute" [] (Just "xterm")]
            , KeybindBinding "A-Space" [KeybindAction "ShowMenu" [("menu", "root-menu")] Nothing]
            ]
    assertBool "execute binding present" ("W-Return" `containsSubstring` xml)
    assertBool "show menu binding present" ("root-menu" `containsSubstring` xml)

testRcRendering :: Test
testRcRendering =
  TestCase $ do
    let rcXml =
          renderRcXml
            (buildRcConfig
              [ ("NSCDE_THEME_NAME", "NsCDE-Stage1")
              , ("NSCDE_LABWC_WORKSPACES", "Alpha,Beta")
              ]
              "  <keyboard>\n    <default />\n  </keyboard>\n")
    assertBool "workspace count present" ("<number>2</number>" `containsSubstring` rcXml)
    assertBool "keyboard fragment preserved" ("<keyboard>" `containsSubstring` rcXml)

testPanelEnvRendering :: Test
testPanelEnvRendering =
  TestCase $ do
    let envText =
          renderEnvFile
            (emitPanelLayout
              samplePanelProfile)
    assertBool "panel layout source present" ("NSCDE_PANEL_LAYOUT_SOURCE=haskell-runtime" `containsSubstring` envText)
    assertBool "panel profile present" ("NSCDE_PANEL_PROFILE=reference" `containsSubstring` envText)

samplePanelProfile :: StaticPanelProfile
samplePanelProfile =
  StaticPanelProfile
    { panelHeight = 79
    , panelEdge = "bottom"
    , panelBorderWidth = 4
    , panelMargin = 0
    , panelPaddingX = 6
    , panelPaddingY = 4
    , panelWorkspaceMinButtonWidth = 84
    , panelWorkspaceButtonPaddingX = 10
    , panelWorkspaceButtonGap = 6
    , panelWorkspaceRecessHeight = 32
    , panelBevelWidth = 1
    , panelFont = "DejaVu Serif 9"
    , panelRightAreaWidth = 200
    , panelLeftModules = "clock,date,home,term,mail"
    , panelLauncherUnitWidth = 63
    , panelLauncherIconSize = 48
    , panelLauncherGap = 0
    , panelRightModules = "print,style,apps,multimedia,help"
    , panelAppletUnitWidth = 50
    , panelProfile = "reference"
    , panelSubpanelEntryHeight = 32
    , panelSubpanelIconSize = 32
    , panelSubpanelTitleHeight = 20
    , panelSubpanelPadding = 4
    , panelLeftHandleWidth = 21
    , panelRightHandleWidth = 21
    , panelTriggerHeight = 16
    , panelBodyHeight = 62
    , panelBottomStripHeight = 1
    , panelSectionSeparatorWidth = 1
    , panelRightAppletGap = 4
    , panelDeskCount = 4
    , panelWsmWidth = 343
    , panelWsmLockWidth = 2
    , panelWsmExitWidth = 2
    , panelWsmButtonsWidth = 257
    , panelLeftBankWidth = 315
    , panelRightBankWidth = 315
    , panelCenterSectionX = 336
    , panelCenterSectionWidth = 343
    , panelWsmInnerPad = 5
    , panelWsmSideWidth = 43
    , panelWsmUtilityWidth = 43
    , panelWsmSectionGap = 6
    , panelWsmGridVpad = 3
    , panelWsmLockHeight = 34
    , panelWsmLoadInsetTop = 8
    , panelWsmLoadInsetSide = 5
    , panelWsmLoadHeight = 14
    , panelWsmExitHeight = 30
    , panelWsmExitInsetBottom = 4
    , panelWsmUtilityInsetSide = 5
    , panelScale = 100
    , panelWsFont = "DejaVu Serif 10"
    , panelAppletDateFont = "DejaVu Sans Bold 12"
    , panelAppletMailFont = "DejaVu Sans 10"
    , panelAppletClockSize = 56
    , panelAppletDateSize = 56
    , panelAppletMailSize = 56
    , panelAppletLoadWidth = 36
    , panelAppletLoadHeight = 34
    }

containsSubstring :: String -> String -> Bool
containsSubstring needle haystack =
  any (isPrefixOf needle) (tails haystack)

tails :: [a] -> [[a]]
tails [] = [[]]
tails value@(_:rest) = value : tails rest

isPrefixOf :: Eq a => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (left:leftRest) (right:rightRest) =
  left == right && isPrefixOf leftRest rightRest
