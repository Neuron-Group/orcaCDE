module Main (main) where

import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

import Test.HUnit

import NsCDE.Backend.Labwc.KeybindXml (renderKeyboardXml)
import NsCDE.Backend.Labwc.MenuXml (renderMenuXml)
import NsCDE.Backend.Labwc.RcXml (renderRcXml)
import NsCDE.Backend.Labwc.Theme (renderLabwcThemeFiles)
import NsCDE.Domain.Backdrop
  ( BackdropMode(..)
  , BackdropPlan(..)
  )
import NsCDE.Domain.Keybinds
import NsCDE.Domain.Keymap (KeymapEnvironment(..))
import NsCDE.Domain.Menu
import NsCDE.Domain.Palette (PaletteColor, parseHexColor8)
import NsCDE.Domain.PanelLayout
import NsCDE.Domain.Session (RcFont(..), RcInput(..))
import NsCDE.Domain.Style
  ( DeskBackdrop(..)
  , FocusPolicy(..)
  , IconFill(..)
  , IconPlacement(..)
  , IconSize(..)
  , defaultStyleState
  , lookupDeskBackdrop
  , styleAutoRaise
  , styleEdgeMoveDelayMs
  , styleEdgeMoveResistancePx
  , styleEdgeResistancePx
  , styleFocusPolicy
  , styleIconFill
  , styleIconPlacement
  , styleIconSize
  , styleMoveThresholdPx
  , styleOpaqueMovePercent
  , stylePagerPreview
  , styleRaiseDelayMs
  , styleRaiseFrontPanelOnPage
  )
import NsCDE.Foundation.EnvFile (renderEnvFile)
import NsCDE.Parse.AppMenus (parseAppMenuContents)
import NsCDE.Parse.Keybindings (ParsedKeybinding(..), parseKeybindingsContents)
import NsCDE.Parse.StyleMgrIni (lookupIniValueInContents)
import NsCDE.Parse.StyleState (parseStyleStateEntries)
import NsCDE.Policy.Backdrop (backdropCandidatePaths, currentBackdropDesk)
import NsCDE.Policy.Backdrop (buildBackdropPlan)
import NsCDE.Policy.Keymap (buildBindingIntent, renderBindingIntent)
import NsCDE.Policy.Menu (buildMenuModel)
import NsCDE.Policy.PanelLayout (emitPanelLayout)
import NsCDE.Policy.SessionPlan (buildRcConfig)
import qualified NsCDE.Runtime.TopicState as RuntimeTopicState

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
    , TestLabel "rc focus mapping" testRcFocusMapping
    , TestLabel "panel env rendering" testPanelEnvRendering
    , TestLabel "style ini parsing" testStyleIniParsing
    , TestLabel "style state parsing" testStyleStateParsing
    , TestLabel "theme rendering" testThemeRendering
    , TestLabel "backdrop candidates" testBackdropCandidates
    , TestLabel "backdrop desk fallback" testBackdropDeskFallback
    , TestLabel "default backdrop plan" testDefaultBackdropPlan
    , TestLabel "keymap translation" testKeymapTranslation
    , TestLabel "keymap mixed context rejected" testKeymapMixedContextRejected
    , TestLabel "workspace publish keeps canonical order" testWorkspacePublishKeepsCanonicalOrder
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
    assertBool "workspace action uses runtime control path"
      ("nscde-runtime ctl workspace-switch" `containsSubstring` menuXml)
    assertBool "workspace action still performs compositor desktop switch"
      ("GoToDesktop" `containsSubstring` menuXml)

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
    let rcInput =
          RcInput
            { rcInputThemeName = "NsCDE-Stage1"
            , rcInputTitleFont =
                RcFont "" "DejaVu Sans" "10" "normal" "bold"
            , rcInputWorkspaces = ["Alpha", "Beta"]
            , rcInputKeybindXml =
                "  <keyboard>\n    <default />\n  </keyboard>\n"
            }
        rcXml =
          renderRcXml
            (buildRcConfig rcInput defaultStyleState)
    assertBool "workspace count present" ("<number>2</number>" `containsSubstring` rcXml)
    assertBool "keyboard fragment preserved" ("<keyboard>" `containsSubstring` rcXml)
    assertBool "default focus follow mouse" ("<followMouse>yes</followMouse>" `containsSubstring` rcXml)
    assertBool "default focus requires movement" ("<followMouseRequiresMovement>yes</followMouseRequiresMovement>" `containsSubstring` rcXml)
    assertBool "default raise on focus disabled" ("<raiseOnFocus>no</raiseOnFocus>" `containsSubstring` rcXml)

testRcFocusMapping :: Test
testRcFocusMapping =
  TestCase $ do
    let rcInput =
          RcInput
            { rcInputThemeName = "NsCDE-Stage1"
            , rcInputTitleFont =
                RcFont "" "DejaVu Sans" "10" "normal" "bold"
            , rcInputWorkspaces = ["Alpha", "Beta"]
            , rcInputKeybindXml =
                "  <keyboard>\n    <default />\n  </keyboard>\n"
            }
        styleState =
          defaultStyleState
            { styleFocusPolicy = SloppyFocus
            , styleAutoRaise = True
            , styleRaiseDelayMs = 250
            }
        rcXml =
          renderRcXml
            (buildRcConfig rcInput styleState)
    assertBool "sloppy focus follow mouse" ("<followMouse>yes</followMouse>" `containsSubstring` rcXml)
    assertBool "sloppy focus does not require movement" ("<followMouseRequiresMovement>no</followMouseRequiresMovement>" `containsSubstring` rcXml)
    assertBool "auto raise enabled" ("<raiseOnFocus>yes</raiseOnFocus>" `containsSubstring` rcXml)
    assertBool "raise delay preserved" ("<raiseOnFocusDelay>250</raiseOnFocusDelay>" `containsSubstring` rcXml)

testPanelEnvRendering :: Test
testPanelEnvRendering =
  TestCase $ do
    let envText =
          renderEnvFile
            (emitPanelLayout
              samplePanelProfile)
    assertBool "panel layout source present" ("NSCDE_PANEL_LAYOUT_SOURCE=haskell-runtime" `containsSubstring` envText)
    assertBool "panel profile present" ("NSCDE_PANEL_PROFILE=reference" `containsSubstring` envText)

testStyleIniParsing :: Test
testStyleIniParsing =
  TestCase $ do
    let iniContents =
          unlines
            [ "[FontMgr]"
            , "integrate_gtk3=1"
            , "integrate_qt5 = yes"
            , ""
            , "[Other]"
            , "ignored=value"
            ]
    assertEqual "gtk3 flag parsed" (Just "1") (lookupIniValueInContents "FontMgr" "integrate_gtk3" iniContents)
    assertEqual "qt5 flag parsed" (Just "yes") (lookupIniValueInContents "FontMgr" "integrate_qt5" iniContents)
    assertEqual "missing key" Nothing (lookupIniValueInContents "FontMgr" "integrate_local" iniContents)

testStyleStateParsing :: Test
testStyleStateParsing =
  TestCase $ do
    let styleState =
          parseStyleStateEntries
            [ ("NSCDE_FOCUS_POLICY", "SloppyFocus")
            , ("NSCDE_AUTO_RAISE", "1")
            , ("NSCDE_RAISE_DELAY", "175")
            , ("NSCDE_OPAQUE_MOVE", "85")
            , ("NSCDE_MOVE_THRESHOLD", "3")
            , ("NSCDE_ICON_PLACEMENT", "1")
            , ("NSCDE_ICON_FILL", "top.right")
            , ("NSCDE_ICON_SIZE", "32,32,96,96")
            , ("NSCDE_RAISE_FP_ON_PAGE", "1")
            , ("NSCDE_PAGER_PREVIEW", "1")
            , ("NSCDE_EDGE_RESISTANCE", "500")
            , ("NSCDE_EDGE_MOVE_RESISTANCE", "25")
            , ("NSCDE_EDGE_MOVE_DELAY", "400")
            , ("NSCDE_BACKDROP_DESK_1_MODE", "tiled")
            , ("NSCDE_BACKDROP_DESK_1_IMAGE", "DeskOne")
            , ("NSCDE_BACKDROP_DESK_2_MODE", "photo")
            , ("NSCDE_BACKDROP_DESK_2_IMAGE", "DeskTwo")
            ]
        parsedIconSize = styleIconSize styleState
    assertEqual "focus policy parsed" SloppyFocus (styleFocusPolicy styleState)
    assertBool "auto raise parsed" (styleAutoRaise styleState)
    assertEqual "raise delay parsed" 175 (styleRaiseDelayMs styleState)
    assertEqual "opaque move parsed" 85 (styleOpaqueMovePercent styleState)
    assertEqual "move threshold parsed" 3 (styleMoveThresholdPx styleState)
    assertEqual "icon placement parsed" IconPlacementIconBox (styleIconPlacement styleState)
    assertEqual "icon fill parsed" IconFillTopRight (styleIconFill styleState)
    assertEqual "icon default width parsed" 32 (styleIconDefaultWidth parsedIconSize)
    assertEqual "icon max height parsed" 96 (styleIconMaxHeight parsedIconSize)
    assertBool "front panel raise parsed" (styleRaiseFrontPanelOnPage styleState)
    assertBool "pager preview parsed" (stylePagerPreview styleState)
    assertEqual "edge resistance parsed" 500 (styleEdgeResistancePx styleState)
    assertEqual "edge move resistance parsed" 25 (styleEdgeMoveResistancePx styleState)
    assertEqual "edge move delay parsed" 400 (styleEdgeMoveDelayMs styleState)
    case lookupDeskBackdrop 1 styleState of
      Just deskBackdrop -> do
        assertEqual "desk one backdrop mode parsed" (Just BackdropModeTiled) (deskBackdropMode deskBackdrop)
        assertEqual "desk one backdrop image parsed" "DeskOne" (deskBackdropImage deskBackdrop)
      Nothing ->
        assertFailure "expected desk one backdrop"
    case lookupDeskBackdrop 2 styleState of
      Just deskBackdrop -> do
        assertEqual "desk two backdrop mode parsed" (Just BackdropModePhoto) (deskBackdropMode deskBackdrop)
        assertEqual "desk two backdrop image parsed" "DeskTwo" (deskBackdropImage deskBackdrop)
      Nothing ->
        assertFailure "expected desk two backdrop"

testThemeRendering :: Test
testThemeRendering =
  TestCase $ do
    let themeFiles =
          renderLabwcThemeFiles
            [ expectPaletteColor "#102030"
            , expectPaletteColor "#405060"
            , expectPaletteColor "#708090"
            , expectPaletteColor "#90a0b0"
            , expectPaletteColor "#b0c0d0"
            , expectPaletteColor "#d0e0f0"
            ]
    case lookup "themerc" themeFiles of
      Just themerc -> do
        assertBool "active title uses palette slot one" ("window.active.title.bg.color: #102030" `containsSubstring` themerc)
        assertBool "inactive title uses palette slot two" ("window.inactive.title.bg.color: #405060" `containsSubstring` themerc)
        assertBool "osd bg uses palette slot six" ("osd.bg.color: #d0e0f0" `containsSubstring` themerc)
      Nothing ->
        assertFailure "expected themerc output"
    case lookup "menu-active.xpm" themeFiles of
      Just menuXpm ->
        assertBool "menu xpm emitted" ("static char *menu_xpm[]" `containsSubstring` menuXpm)
      Nothing ->
        assertFailure "expected menu-active.xpm output"
    case lookup "2x/close.xbm" themeFiles of
      Just close2x ->
        assertBool "2x close glyph emitted" ("#define close_width 16" `containsSubstring` close2x)
      Nothing ->
        assertFailure "expected 2x close glyph output"

testBackdropCandidates :: Test
testBackdropCandidates =
  TestCase $
    assertEqual "tiled backdrop search order"
      [ "/tmp/home/.NsCDE/backer/Desk1-Example.png"
      , "/tmp/home/.NsCDE/backer/Desk1-Example.pm"
      , "/tmp/home/.NsCDE/backdrops/Example.pm"
      , "/tmp/assets/backdrops/Example.pm"
      ]
      (backdropCandidatePaths "/tmp/home/.NsCDE" "/tmp/assets" 1 (Just BackdropModeTiled) "Example")

testBackdropDeskFallback :: Test
testBackdropDeskFallback =
  TestCase $ do
    assertEqual "workspace maps to desk index" 2 (currentBackdropDesk ["Alpha", "Beta"] "Beta")
    assertEqual "missing workspace falls back to desk one" 1 (currentBackdropDesk ["Alpha", "Beta"] "Missing")

testDefaultBackdropPlan :: Test
testDefaultBackdropPlan =
  TestCase $ do
    let assetRoot = "/tmp/nscde-wayland-runtime-tests/assets"
        backdropDir = assetRoot </> "backdrops"
        backdropPath = backdropDir </> "Convex.pm"
    createDirectoryIfMissing True backdropDir
    writeFile backdropPath "/* runtime test backdrop */\n"
    backdropPlan <-
      buildBackdropPlan
        "/tmp/home/.NsCDE"
        assetRoot
        ["One", "Two", "Three", "Four"]
        "Three"
        defaultStyleState
        [("NSCDE_PALETTE_1", "#123456")]
    assertEqual "default desk uses workspace index" 3 (backdropPlanDesk backdropPlan)
    assertEqual "default backdrop image name" "Convex" (backdropPlanImage backdropPlan)
    assertEqual "default backdrop mode" (Just BackdropModeTiled) (backdropPlanMode backdropPlan)
    assertEqual "default backdrop path"
      (Just backdropPath)
      (backdropPlanSourcePath backdropPlan)

testKeymapTranslation :: Test
testKeymapTranslation =
  TestCase $ do
    let keymapEnv =
          KeymapEnvironment
            { keymapTerminal = "xterm"
            , keymapToolsDir = "/tools"
            , keymapDataDir = "/data"
            }
        parsedBinding =
          ParsedKeybinding
            { parsedKeyName = "Page_Up"
            , parsedContext = "R"
            , parsedModifier = "C"
            , parsedAction = "Scroll 0 100000"
            }
    case buildBindingIntent keymapEnv parsedBinding of
      Just bindingIntent -> do
        let binding = renderBindingIntent bindingIntent
        assertEqual "mapped key keeps modifiers" "C-Prior" (keybindKey binding)
        assertEqual "mapped action count" 1 (length (keybindActions binding))
        case keybindActions binding of
          action:_ -> do
            assertEqual "mapped action name" "GoToDesktop" (keybindActionName action)
            assertEqual "mapped action attrs" [("to", "right"), ("wrap", "yes")] (keybindActionAttrs action)
          [] ->
            assertFailure "expected translated action"
      Nothing ->
        assertFailure "expected translated key binding"

testKeymapMixedContextRejected :: Test
testKeymapMixedContextRejected =
  TestCase $ do
    let keymapEnv =
          KeymapEnvironment
            { keymapTerminal = "xterm"
            , keymapToolsDir = "/tools"
            , keymapDataDir = "/data"
            }
        parsedBinding =
          ParsedKeybinding
            { parsedKeyName = "Right"
            , parsedContext = "RWFST"
            , parsedModifier = "CM"
            , parsedAction = "Next ($[w.accepts_focus], Iconic off, CurrentPage, CurrentDesk) FlipFocus"
            }
    assertEqual "mixed FVWM contexts are not accepted as labwc keybind contexts"
      Nothing
      (buildBindingIntent keymapEnv parsedBinding)

testWorkspacePublishKeepsCanonicalOrder :: Test
testWorkspacePublishKeepsCanonicalOrder =
  TestCase $ do
    let canonical = ["One", "Two", "Three", "Four"]
        publishedEntries =
          [ ("NSCDE_WORKSPACES", "Four,Three,Two,One")
          , ("NSCDE_CURRENT_WORKSPACE", "Four")
          ]
    assertEqual "producer publish does not reorder canonical workspaces"
      canonical
      (RuntimeTopicState.canonicalWorkspaceNames canonical publishedEntries)
    assertEqual "published current workspace is still accepted when it exists canonically"
      "Four"
      (RuntimeTopicState.resolvePublishedCurrentWorkspace
        publishedEntries
        canonical
        "One")

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

expectPaletteColor :: String -> PaletteColor
expectPaletteColor rawValue =
  case parseHexColor8 rawValue of
    Just color -> color
    Nothing -> error ("invalid test palette color: " ++ rawValue)
